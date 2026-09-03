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

import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:aircalc_native/aircalc_native.dart' as native;
import 'package:flutter/services.dart';

import '../models/gesture.dart';
import 'mwh_core_engine.dart';

/// 单次推理的逐阶段延迟测量结果。
class BenchmarkTiming {
  final int encMs;
  final int prefillMs;
  final int decSteps;
  final double decStepAvgMs;
  final int totalMs;
  final int tokenCount;
  final String label;
  final String result;
  final List<int> tokenIds;

  const BenchmarkTiming({
    required this.encMs,
    required this.prefillMs,
    required this.decSteps,
    required this.decStepAvgMs,
    required this.totalMs,
    required this.tokenCount,
    required this.label,
    required this.result,
    this.tokenIds = const [],
  });
}

const int _specialN = 4; // PAD BOS EOS UNK

/// 硬件加速 delegate 选择。
///
/// 保留给调用方表达意图；实际选择在核心库里由 PTE 自带的 delegate 决定，
/// [MwhCoreEngine] 不消费这个值。
enum MwBackend {
  /// 平台默认：Android=XNNPACK，iOS=CoreML
  auto,
  xnnpack,
  gpu,
  cpu,
  coreml,
}

/// MathWriting Decoder-Only 端侧识别服务。
///
/// 三端同一条路径：aircalc 原生核心（Rust），跑在常驻 worker isolate 上。
/// 后端由核心库按平台选：iOS/macOS 裸 Core ML（.mlmodelc，吃神经引擎），
/// Android LiteRT。
class MathWritingRecognitionService {
  /// 当前运行档位，进基准结果与论文表格的标签。
  ///
  /// 取核心库实际选中的后端，不再按平台写死。写死那版会把任何后端的结果都
  /// 标成同一个名字，报告文件名与 meta 里看不出差别，换过后端就分不清哪份是哪份。
  /// 引擎还没初始化时退回按平台猜，只为让标签不至于是空的。
  static String get kQuantizationTag {
    final backend = instance._engine?.backendName;
    if (backend != null && backend != 'uninitialized') {
      return 'mwh_${backend.replaceAll('-', '_')}';
    }
    return Platform.isAndroid ? 'mwh_litert' : 'mwh_coreml';
  }

  /// 全局共享实例 —— 避免多个页面各自创建导致重复加载模型。
  static final MathWritingRecognitionService instance = MathWritingRecognitionService._();
  // ignore: unused_field, prefer_const_constructors_in_immutables
  MathWritingRecognitionService._();

  MwBackend _backend = MwBackend.auto;
  MwBackend get backend => _backend;

  /// 统一推理引擎。原先两端各一套（Android isolate + LiteRT、iOS 直连
  /// ExecuTorch），各带一份重复的解码逻辑，现已合并到核心库里。
  MwhCoreEngine? _engine;

  bool _ready = false;
  bool get isReady => _ready;

  // 防止并发 init() 导致重复加载
  Future<bool>? _initFuture;

  // ── 缓存 ──
  int _lastFingerprint = 0;
  String? _lastResult;
  // 引擎提供 vocab，供 token→字符串 转换
  List<String>? _vocab;

  /// 暴露 vocab 给离线评测（benchmark page 的 token-level CER 需要它做 BPE tokenize）。
  /// 未 init 完成时返回 null。
  List<String>? get vocab => _vocab;
  int get specialTokenCount => _specialN;

  // ---------------------------------------------------------------------------

  Future<bool> init({MwBackend backend = MwBackend.auto}) async {
    // 已完成初始化
    if (_ready) return true;
    // 已有正在进行的初始化，等待其结果
    if (_initFuture != null) return _initFuture!;
    _backend = backend;

    // 不再按平台分支：两端统一走 aircalc 原生核心，后端差异（iOS Core ML /
    // Android XNNPACK）由核心库内部的 Engine 抽象抹平。
    _initFuture = _initCore();
    return _initFuture!;
  }

  /// 备好模型目录，返回给核心库的路径。
  ///
  /// iOS 上优先用 app bundle：那里放着构建期 coremlcompiler 编好的三件
  /// `.mlmodelc`（见 Runner 的 Thin Binary 阶段）。核心库在 model_dir 里发现
  /// 它们就走裸 Core ML，不再需要 ExecuTorch，也省掉把几十兆 `.pte` 从
  /// asset 拷到临时目录那一趟——那是每次冷启动都要付的。
  ///
  /// 其余情况（Android，或 bundle 里没有预编译模型）照旧：模型以 asset 形式
  /// 打包，核心库要的是文件路径，先落到临时目录。
  Future<String> _prepareModelDir() async {
    if (Platform.isIOS) {
      // .app 目录 = 可执行文件所在目录。不为这一件事再开一条平台通道。
      final appDir = File(Platform.resolvedExecutable).parent.path;
      if (Directory('$appDir/prefix_enc.mlmodelc').existsSync()) {
        return appDir;
      }
    }
    final tmp = await Directory.systemTemp.createTemp('mw_models_');
    for (final asset in MwhCoreEngine.modelAssets) {
      await _materializeAsset(asset, tmp);
    }
    return tmp.path;
  }

  Future<bool> _initCore() async {
    final vocabJson = await rootBundle.loadString(MwhCoreEngine.vocabAsset);
    final modelDir = await _prepareModelDir();
    final engine = MwhCoreEngine(modelDir: modelDir);
    final ok = await engine.init(vocabJson: vocabJson);
    if (ok) {
      _engine = engine;
      _vocab = engine.vocab;
      // 预热必须算进初始化：Core ML 首次执行要编译模型（首次安装后几秒），
      // 编译完成前识别依然很慢。若在这里提前返回 ready，界面会显示"可识别"
      // 而用户实际写下去要等很久——状态与体验不符。
      //
      // App 启动时已经不 await 地调过一次 init，预热在那时就开始了；等用户
      // 进到编辑页，这里返回的是同一个 Future，多数情况已经完成。
      await engine.warmUp();
    }
    _ready = ok;
    return ok;
  }

  static Future<String> _materializeAsset(String assetPath, Directory dir) async {
    final name = assetPath.split('/').last;
    final f = File('${dir.path}/$name');
    if (await f.exists() && await f.length() > 0) return f.path;
    final byteData = await rootBundle.load(assetPath);
    final sink = f.openWrite();
    sink.add(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    await sink.flush();
    await sink.close();
    return f.path;
  }

  // ---------------------------------------------------------------------------

  /// 识别画布上的全部笔画，返回完整 LaTeX 串。
  Future<String?> recognize(List<Stroke> strokes, Size canvasSize) async {
    if (!_ready || strokes.isEmpty) return null;

    // 缓存命中
    final fp = _strokesFingerprint(strokes);
    if (fp == _lastFingerprint && _lastResult != null) {
      return _lastResult;
    }

    // 推理全程在 Rust 侧，不再需要 isolate 隔离——原先 Android 那条
    // isolate 路径是为了避免 Dart 侧的解码循环阻塞 UI。
    final raw = await _engine!.recognize(strokes, canvasSize);

    if (raw == null || _vocab == null) return null;

    final rawStr = raw.toRawString(_vocab!, _specialN);
    if (rawStr.isEmpty) return null;

    final result = _mergeKnownFunctions(rawStr);
    if (result.isNotEmpty) {
      _lastFingerprint = fp;
      _lastResult = result;
    }
    return result.isEmpty ? null : result;
  }

  /// 对 token 列表求值（如 ['1+2', '×3'] → '9'）。
  Future<String?> calculate(List<String> expression) async {
    if (expression.isEmpty) return null;
    // 纯计算逻辑，无 native 依赖——原先在 Android 上绕到 worker isolate，
    // 那是因为引擎在那边；现在推理不占 Dart 线程，直接算即可。
    try {
      return _evaluateExpression(expression.join());
    } catch (_) {
      return null;
    }
  }

  /// 单次推理延迟基准测试（跳过缓存，返回分阶段耗时）。
  Future<BenchmarkTiming?> benchmark(
    List<Stroke> strokes,
    Size canvasSize, {
    bool applyVarBias = true,
    bool applyPostProcess = true,
  }) async {
    if (!_ready || strokes.isEmpty || _vocab == null) return null;

    final raw =
        await _engine!.benchmark(strokes, canvasSize, applyVarBias: applyVarBias);

    if (raw == null) return null;

    final rawStr = raw.toRawString(_vocab!, _specialN);
    final result = rawStr.isEmpty
        ? ''
        : (applyPostProcess ? _mergeKnownFunctions(rawStr) : rawStr);
    final decSteps = raw.tokenIds.length - 1; // exclude BOS

    return BenchmarkTiming(
      encMs: raw.encMs,
      prefillMs: raw.prefillMs,
      decSteps: decSteps,
      decStepAvgMs: decSteps > 0 ? raw.decMs / decSteps : 0,
      totalMs: raw.encMs + raw.prefillMs + raw.decMs,
      tokenCount: decSteps,
      label: '',
      result: result,
      tokenIds: raw.tokenIds.sublist(1),
    );
  }

  int _strokesFingerprint(List<Stroke> strokes) {
    int h = strokes.length;
    int totalPts = 0;
    for (final s in strokes) {
      totalPts += s.points.length;
    }
    h = h * 31 + totalPts;
    if (totalPts > 0) {
      final p0 = strokes.first.points.first;
      final pN = strokes.last.points.last;
      h = h * 31 + (p0.dx * 1000).toInt();
      h = h * 31 + (p0.dy * 1000).toInt();
      h = h * 31 + (pN.dx * 1000).toInt();
      h = h * 31 + (pN.dy * 1000).toInt();
    }
    return h;
  }

  // ---------------------------------------------------------------------------

  void dispose() {
    _engine?.dispose();
    _engine = null;
    _ready = false;
    _vocab = null;
  }
}








// ─── 后处理：字母序列 → LaTeX 函数命令 ───────────────────────────────────────

String _mergeKnownFunctions(String s) {
  const replacements = [
    ('arcsin', r'\arcsin'),
    ('arccos', r'\arccos'),
    ('arctan', r'\arctan'),
    ('sinh', r'\sinh'),
    ('cosh', r'\cosh'),
    ('tanh', r'\tanh'),
    ('sin', r'\sin'),
    ('cos', r'\cos'),
    ('tan', r'\tan'),
    ('cot', r'\cot'),
    ('sec', r'\sec'),
    ('csc', r'\csc'),
    ('log', r'\log'),
    ('ln', r'\ln'),
    ('exp', r'\exp'),
    ('lim', r'\lim'),
    ('max', r'\max'),
    ('min', r'\min'),
    ('sqrt', r'\sqrt'),
    ('frac', r'\frac'),
    ('sum', r'\sum'),
    ('prod', r'\prod'),
    ('int', r'\int'),
    ('pi', r'\pi'),
    ('inf', r'\infty'),
  ];

  for (final (from, _) in replacements) {
    s = s.replaceAllMapped(
      RegExp('(?<![a-zA-Z\\\\])${from}e(\\^(?:\\{[^{}]*\\}|\\w))?(?![a-zA-Z])'),
      (m) {
        final exp = m[1] ?? '';
        return '$from{e$exp}';
      },
    );
  }

  for (final (from, to) in replacements) {
    s = s.replaceAllMapped(
      RegExp('(?<![a-zA-Z\\\\])$from(?![a-zA-Z])'),
      (_) => to,
    );
  }
  return s;
}


// ─── LaTeX 表达式求值 ────────────────────────────────────────────────────────
//
// 实现已下沉到 Rust 的 latex-calc crate（air_calculator-rs/crates/latex-calc）。
// 这里原先是约 460 行 Dart：用正则把 LaTeX 一步步改写成中缀串，再交给
// math_expressions 求值。结构信息在改写过程中就丢了——`2^3^2` 的结合性、
// `-2^2` 的优先级、`|a|b|` 的断句都只能靠碰运气，且所有失败都塌成 null。
// Rust 那份走词法 → 语法 → AST → 求值，边界行为由 37 个用例钉住。

String? _evaluateExpression(String expr) => native.evalLatexOrNull(expr);

// 供测试文件调用
String? evaluateLatexForTest(String expr) => _evaluateExpression(expr);
