/// 编译 Rust 核心库，并带上它需要的推理运行时。
///
/// 仓库里唯一构建原生代码的地方。一个 hook 覆盖所有平台，取代 Flutter 插件
/// 需要的 CocoaPods / Gradle / CMake 那三套胶水；又因为它是 build hook，
/// `dart run` 与 `dart test` 同样适用。
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

import 'package:aircalc_native/src/hook/runtime.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // 有些构建模式压根不要原生代码，这时读 code 配置会抛异常。
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;

    // 编哪些后端由平台决定：Android 走 LiteRT，iOS/macOS 走裸 Core ML。
    // 用哪个由 Rust 侧按 EngineConfig.prefer 与模型文件分派，Dart 这边
    // 看不到区别。
    final backends = backendsFor(code.targetOS);
    final backend = backends.first;

    // 几个仓并排 checkout 是文档里写明的布局，按它给出默认位置，clone
    // 下来就能构建。放在别处的话用 user_defines 覆盖；相对路径按本包根
    // 目录解析，绝对路径原样使用——写死绝对路径会把用户名和目录结构带进
    // 仓库，别人也用不了。
    String resolveFromPackage(String path) =>
        path.startsWith('/') ? path : input.packageRoot.resolve(path).toFilePath();

    final cratePath = resolveFromPackage(
      input.userDefines['crate_path'] as String? ??
          '../../../air_calculator-rs/crates/aircalc-ffi',
    );
    if (!Directory(cratePath).existsSync()) {
      throw StateError(
        'aircalc_native: 找不到 Rust 核心库 $cratePath\n'
        '默认按几个仓并排 checkout 找；放在别处就在应用的 pubspec.yaml 里指出：\n'
        'hooks:\n'
        '  user_defines:\n'
        '    aircalc_native:\n'
        '      crate_path: ../path/to/air_calculator-rs/crates/aircalc-ffi',
      );
    }

    // Core ML 是系统框架，没有构件可取——苹果平台上这一步整个跳过。
    final runtime = !needsRuntime(backend)
        ? Runtime(cargoEnvironment: const {}, bundledLibraries: const [], dependencies: const [])
        : await fetchRuntime(
      backend: backend,
      os: code.targetOS,
      architecture: code.targetArchitecture,
      // 真机与模拟器是两份不同的构件，链接错了直接失败。
      // 这个信息只在配置里有——hook runner 会清掉 Xcode 设的环境变量。
      iosSdk: code.targetOS == OS.iOS ? code.iOS.targetSdk : null,
      packageRoot: Directory.fromUri(input.packageRoot),
      cache: Directory.fromUri(input.outputDirectoryShared.resolve('runtime/')),
      // 运行时构件还没发 release 之前，应用在自己的 pubspec 里指出本地产物：
      //   hooks:
      //     user_defines:
      //       aircalc_native:
      //         runtime_root: ../path/to/edge-infer/third_party/build
      // 或指到单个平台的产物（调试单一平台时）：
      //         runtime_dir: ../path/.../<target>/install
      // 走 user_defines 而不是环境变量，是因为 hook runner 会清空环境。
      localDir: switch (input.userDefines['runtime_dir'] as String?) {
        final d? => resolveFromPackage(d),
        null => null,
      },
      // 默认同样按并排 checkout 找。平台子目录由 hook 自己挑。
      localRoot: resolveFromPackage(
        input.userDefines['runtime_root'] as String? ??
            '../../../edge-infer/third_party/build',
      ),
    );

    await RustBuilder(
      assetName: 'src/bindings.dart',
      // Rust 核心在独立仓库 air_calculator-rs 里，不在本包内——它要给
      // Swift、JNI 以及将来的桌面版共用，不该埋在一个 Dart 包底下。
      // 位置由应用的 pubspec 指出，与 runtime_dir 同一处配置。
      cratePath: cratePath,
      // 只编目标平台要的那些后端，否则会链接到不存在的原生库。
      enableDefaultFeatures: false,
      features: [for (final b in backends) b.cargoFeature],
      // hook runner 会清空环境，链接器的搜索路径继承不过来，
      // build.rs 改从这几个变量读。
      extraCargoEnvironmentVariables: {
        ...runtime.cargoEnvironment,
        // Rust 的 Apple 目标自带的部署版本是它们被加入时的（aarch64-apple-ios
        // 是 iOS 10），这里没人会去说明；而多签名 Core ML 模型要 iOS 18。
        // Flutter 正在构建的版本就在配置里，rustc 认这两个变量。
        if (code.targetOS == OS.iOS)
          'IPHONEOS_DEPLOYMENT_TARGET': '${code.iOS.targetVersion}',
        if (code.targetOS == OS.macOS)
          'MACOSX_DEPLOYMENT_TARGET': '${code.macOS.targetVersion}',
      },
    ).run(input: input, output: output);

    // 动态运行时库与 Rust 库并排放置，Dart 工具链会把两者拷进同一个目录
    // 并改写依赖路径，不需要额外安排 rpath。iOS 是静态库、已经链进 Rust
    // 库里，没有可打包的东西。
    for (final lib in runtime.bundledLibraries) {
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: lib.uri.pathSegments.last,
          linkMode: DynamicLoadingBundled(),
          file: lib.uri,
        ),
      );
    }
    for (final f in runtime.dependencies) {
      output.dependencies.add(f.uri);
    }
  });
}
