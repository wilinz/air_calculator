// Copyright 2026 wilinz.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// 取推理运行时的预编译构件。
///
/// 构件不进仓库——每个平台都是几十兆。全部来自同一个 release：一个仓库、
/// 一个 tag，由 scripts/fetch_litert.sh 取来；每份构件在 tool/runtime.lock 里按
/// SHA-256 钉死，对不上就让构建失败。
///
/// 只有 Android 需要——iOS/macOS 走裸 Core ML，那是系统框架。
library;

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';

/// 推理后端。平台决定用哪个，Rust 侧的 Engine trait 抹平差异。
enum Backend {
  /// LiteRT 2.x。Android 用它，识别与手部检测都是——识别的 decoder 是双签名
  /// `.tflite`（prefill + decode 共享权重），手部检测走 GPU 加速器。
  litert('litert'),

  /// 裸 Core ML：整张图直接交给系统框架，模型是 `.mlpackage`（构建期编成
  /// `.mlmodelc`）。不需要任何第三方运行时构件，所以 [fetchRuntime] 不认它。
  coreml('coreml');

  const Backend(this.cargoFeature);

  /// 传给 cargo 的 feature 名，与 mwh-ffi 的 Cargo.toml 一致。
  final String cargoFeature;
}

/// 这个平台要编进哪个后端。
///
/// Android 只要 LiteRT。手部检测本来就得走它（GPU 加速器只在 LiteRT 2.x 上，
/// 而手部检测必须离开 CPU：同在 ExecuTorch 上时两者共用那个进程级单例线程
/// 池，识别一跑手部检测就掉帧 28 → 22fps）；识别跟过来则是为了别在一个进程
/// 里驮两套运行时——两套各自的线程池仍然会互相排队，而且包体白白多一份。
///
/// iOS/macOS 只要裸 Core ML：识别与手部检测的模型都是 `.mlpackage`（构建期
/// 由 coremlcompiler 编成 `.mlmodelc`），整张图交给系统框架。
///
/// ExecuTorch 曾经是三端统一的后端，现已整体移除：Android 换 LiteRT 是为了
/// 让手部检测吃上 GPU 加速器并与识别分开线程池；iOS 那边它本来也只是 Core ML
/// 的一层壳，撤掉后 500 条基准的 ExpRate 与延迟均不变。
List<Backend> backendsFor(OS os) =>
    os == OS.android ? const [Backend.litert] : const [Backend.coreml];

/// 这个后端是否需要预编译的运行时构件。
///
/// Core ML 是系统框架，什么都不用取；另两个要下对应平台的产物。
bool needsRuntime(Backend b) => b != Backend.coreml;

/// 只关心「主后端是谁」的调用方入口。
Backend backendFor(OS os) => backendsFor(os).first;

/// 一个平台的运行时构件落到磁盘后的样子。
class Runtime {
  Runtime({
    required this.cargoEnvironment,
    required this.bundledLibraries,
    required this.dependencies,
  });

  /// 传给 cargo 的环境变量，build.rs 从这里找头文件与库。
  final Map<String, String> cargoEnvironment;

  /// 需要与 Rust 库并排打包的动态库。静态链接的平台上为空。
  final List<File> bundledLibraries;

  /// 参与增量构建判断的文件。
  final List<File> dependencies;
}

/// 读 tool/runtime.lock，即钉死的构件清单。
///
/// 用扁平的 `KEY=value`，好让 shell 脚本与这个 hook 读同一份来源，
/// 升级时只改一个文件。
Map<String, String> readLock(Directory packageRoot) {
  final file = File.fromUri(packageRoot.uri.resolve('tool/runtime.lock'));
  if (!file.existsSync()) {
    throw StateError('aircalc: 缺少 ${file.path}');
  }
  final lock = <String, String>{};
  for (final line in const LineSplitter().convert(file.readAsStringSync())) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final eq = t.indexOf('=');
    if (eq > 0) lock[t.substring(0, eq)] = t.substring(eq + 1);
  }
  return lock;
}

/// 取指定平台的运行时。
///
/// [iosSdk] 区分真机与模拟器——两者是不同的构件，互换会直接链接失败。
/// 非 iOS 平台传 null。
///
/// 一切落在 [cache] 下，hook runner 在多次构建之间保留它，重复构建直接复用。
Future<Runtime> fetchRuntime({
  required Backend backend,
  required OS os,
  required Architecture architecture,
  required IOSSdk? iosSdk,
  required Directory packageRoot,
  required Directory cache,
  String? localDir,
  String? localRoot,
}) async {
  // 本地开发路径：直接指向 scripts/fetch_litert.sh 的产物，
  // 免去每改一次就要发一版 release。
  //
  // 来源优先 pubspec 的 hooks.user_defines——hook runner 会清空环境变量，
  // 所以 MWH_RUNTIME_DIR 只在少数能透传的场景下有效，作为回退保留。
  final target = _targetName(os, architecture, iosSdk);

  // runtime_root 指向 third_party/build，具体哪个平台由这里按目标挑；
  // runtime_dir 是单个 install 目录的直接覆盖，调试单一平台时用。
  // 之前只有后者，于是每换一个平台就得回去改 pubspec，改漏了就链上另一个
  // 平台的静态库——错在链接期还好，错在运行期就难查了。
  var dir = localDir ??
      const String.fromEnvironment('MWH_RUNTIME_DIR', defaultValue: '');
  if (dir.isEmpty && localRoot != null && localRoot.isNotEmpty) {
    dir = '$localRoot/$target/install';
    if (!Directory(dir).existsSync()) {
      throw StateError(
        'mwh: 找不到 $dir\n'
        '先编一份：air_calculator-rs/scripts/fetch_litert.sh $target',
      );
    }
  }
  if (dir.isNotEmpty) {
    return _fromLocalInstall(backend, Directory(dir));
  }

  // TODO(发布前): 按 tool/runtime.lock 从 release 下载并校验 SHA-256。
  // 在那之前，构件需要本地先编好并在 pubspec 里指过来。
  throw StateError(
    'mwh: 尚未配置运行时构件下载。\n'
    '先在 air_calculator-rs 里编一份：\n'
    '  scripts/fetch_litert.sh $target\n'
    '再在应用的 pubspec.yaml 里写明产物位置：\n'
    'hooks:\n'
    '  user_defines:\n'
    '    mwh:\n'
    '      runtime_dir: /abs/path/to/third_party/build/<target>/install',
  );
}

/// 用本地 install 目录（scripts/fetch_litert.sh 的产物）。
Runtime _fromLocalInstall(Backend backend, Directory install) {
  // backend 现在只是调用方的意图说明。
  // 只要 lib/：include/ 是 ExecuTorch 时代的头文件目录，那套整体移除后
  // fetch_litert.sh 只产出 lib/，再要求 include/ 会让新环境直接构建失败。
  final lib = Directory('${install.path}/lib');
  if (!lib.existsSync()) {
    throw StateError('aircalc: ${install.path} 下没有 lib/');
  }

  //
  // LiteRT 的两个动态库来自官方 AAR（com.google.ai.edge.litert:litert），
  // 不是我们编的：
  //   libLiteRt.so                  运行时，兼容经典 TFLite C API
  //   libLiteRtClGlAccelerator.so   GPU 加速器，OpenCL 与 OpenGL 两个后端
  // 加速器由运行时按名字 dlopen，所以它只要跟着进 lib/<abi>/ 就行，不参与链接。
  final dylibs = [
    File('${lib.path}/libLiteRt.so'),
    File('${lib.path}/libLiteRtClGlAccelerator.so'),
  ].where((f) => f.existsSync()).toList();

  return Runtime(
    cargoEnvironment: {'TFLITE_LIB_DIR': lib.path},
    // LiteRT 是动态库，要跟 Rust 库并排放进 lib/<abi>/。
    // Dart 工具链会把它们拷进同一个目录。
    bundledLibraries: dylibs,
    dependencies: [
      // 库目录变了就该重新链接。
      ...lib.listSync().whereType<File>().where((f) => f.path.endsWith('.a')),
    ],
  );
}

String _targetName(OS os, Architecture arch, IOSSdk? sdk) {
  if (os == OS.iOS) {
    return sdk == IOSSdk.iPhoneOS ? 'ios-arm64' : 'ios-sim-arm64';
  }
  if (os == OS.macOS) return 'macos-arm64';
  if (os == OS.android) {
    return arch == Architecture.arm64 ? 'android-arm64' : 'android-armv7';
  }
  return '${os.name}-${arch.name}';
}
