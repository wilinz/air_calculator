import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/services.dart';
import 'package:math_expressions/math_expressions.dart';

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

String? _evaluateExpression(String expr) {
  if (expr.trim().isEmpty) return null;
  try {
    final infix = _latexToInfix(expr);
    final parsed = Parser().parse(infix);
    final result = parsed.evaluate(EvaluationType.REAL, ContextModel()) as double;
    if (result.isNaN || result.isInfinite) return null;
    if (result == result.truncateToDouble()) return result.toInt().toString();
    return result.toStringAsFixed(6).replaceAll(RegExp(r'\.?0+$'), '');
  } catch (e) {
    print('[Calc] 失败: expr="$expr"  e=$e');
    return null;
  }
}

const _kFuncNames = r'(?:arcsin|arccos|arctan|sin|cos|tan|ln|sqrt|abs|sgn|floor|ceil)';

String _latexToInfix(String s) {
  s = _mergeKnownFunctions(s);
  s = s.replaceAll(' ', '');

  for (final m in [r'\left', r'\right', r'\big', r'\Big', r'\bigg', r'\Bigg']) {
    s = s.replaceAll(m, '');
  }

  s = _expandMatrixDet(s);
  s = _expandFrac(s);
  s = _expandSqrt(s);
  s = _expandBinom(s);
  s = _expandLogBase(s);
  s = _expandLog(s);
  s = _expandSup(s);
  s = _removeSub(s);

  const e = '(2.718281828459045)';

  s = _expandFunc1(s, r'\cot', (a) => '(cos($a)/sin($a))');
  s = _expandFunc1(s, r'\sec', (a) => '(1/cos($a))');
  s = _expandFunc1(s, r'\csc', (a) => '(1/sin($a))');
  s = _expandFunc1(s, r'\sinh', (a) => '(($e^($a)-$e^(-($a)))/2)');
  s = _expandFunc1(s, r'\cosh', (a) => '(($e^($a)+$e^(-($a)))/2)');
  s = _expandFunc1(s, r'\tanh', (a) => '(($e^($a)-$e^(-($a)))/($e^($a)+$e^(-($a))))');
  s = _expandFunc1(s, r'\exp', (a) => '$e^($a)');

  s = _expandAbsBar(s);
  s = _expandFactorial(s);

  s = s
      .replaceAll(r'\pi', '(3.141592653589793)')
      .replaceAll(r'\e', e)
      .replaceAll(r'\infty', '(1e308)');

  s = s
      .replaceAll(r'\arcsin', 'arcsin')
      .replaceAll(r'\arccos', 'arccos')
      .replaceAll(r'\arctan', 'arctan')
      .replaceAll(r'\sin', 'sin')
      .replaceAll(r'\cos', 'cos')
      .replaceAll(r'\tan', 'tan')
      .replaceAll(r'\ln', 'ln')
      .replaceAll(r'\log', 'ln')
      .replaceAll(r'\abs', 'abs')
      .replaceAll(r'\lfloor', 'floor(')
      .replaceAll(r'\rfloor', ')')
      .replaceAll(r'\lceil', 'ceil(')
      .replaceAll(r'\rceil', ')');

  const builtinFuncs = r'arcsin|arccos|arctan|sin|cos|tan|ln|sqrt|abs|floor|ceil';
  s = s.replaceAllMapped(
    RegExp('(' + builtinFuncs + r')(\d+(?:\.\d+)?)'),
    (m) => '${m[1]}(${m[2]})',
  );

  s = s.replaceAll('{', '(').replaceAll('}', ')');

  s = s
      .replaceAll('×', '*')
      .replaceAll(r'\times', '*')
      .replaceAll(r'\cdot', '*')
      .replaceAll('÷', '/')
      .replaceAll(r'\div', '/')
      .replaceAll('[', '(')
      .replaceAll(']', ')');

  s = s.replaceAllMapped(
    RegExp(r'(\d+(?:\.\d+)?)\s*%'),
    (m) => '(${m[1]}/100)',
  );

  s = s.replaceAllMapped(
    RegExp(r'(?<!\w)e(?!\w)'),
    (_) => '(2.718281828459045)',
  );

  s = _insertImplicitMul(s);

  return s;
}

// ── 结构展开辅助 ──────────────────────────────────────────────────────────

String _expandFrac(String s) {
  while (s.contains(r'\frac')) {
    final idx = s.indexOf(r'\frac');
    final rest = s.substring(idx + 5);
    final n = _extractBraceGroup(rest, 0);
    final d = _extractBraceGroup(rest, n.$2);
    s = '${s.substring(0, idx)}((${n.$1})/(${d.$1}))${rest.substring(d.$2)}';
  }
  return s;
}

String _expandSqrt(String s) {
  while (s.contains(r'\sqrt')) {
    final idx = s.indexOf(r'\sqrt');
    var rest = s.substring(idx + 5);
    String rep;
    if (rest.startsWith('[')) {
      final n = _extractBracketGroup(rest, 0);
      final a = _extractBraceGroup(rest, n.$2);
      rep = '((${a.$1})^(1/(${n.$1})))';
      rest = rest.substring(a.$2);
    } else {
      final a = _extractBraceGroup(rest, 0);
      rep = 'sqrt(${a.$1})';
      rest = rest.substring(a.$2);
    }
    s = s.substring(0, idx) + rep + rest;
  }
  return s;
}

String _expandLogBase(String s) {
  while (s.contains(r'\log_')) {
    final idx = s.indexOf(r'\log_');
    final after = s.substring(idx + 5);
    String base;
    int baseEnd;
    if (after.startsWith('{')) {
      final g = _extractBraceGroup(after, 0);
      base = g.$1;
      baseEnd = g.$2;
    } else if (after.isNotEmpty) {
      base = after[0];
      baseEnd = 1;
    } else
      break;

    final rest2 = after.substring(baseEnd);
    String arg;
    int argEnd;
    if (rest2.startsWith('{')) {
      final g = _extractBraceGroup(rest2, 0);
      arg = g.$1;
      argEnd = g.$2;
    } else if (rest2.startsWith('(')) {
      final g = _extractParenGroup(rest2, 0);
      arg = g.$1;
      argEnd = g.$2;
    } else {
      final numMatch = RegExp(r'^[\d.]+').firstMatch(rest2);
      if (numMatch != null) {
        arg = numMatch.group(0)!;
        argEnd = numMatch.end;
      } else if (rest2.isNotEmpty) {
        arg = rest2[0];
        argEnd = 1;
      } else {
        break;
      }
    }
    s = '${s.substring(0, idx)}(ln($arg)/ln($base))${rest2.substring(argEnd)}';
  }
  return s;
}

String _expandSup(String s) {
  final sb = StringBuffer();
  int i = 0;
  while (i < s.length) {
    if (s[i] == '^' && i + 1 < s.length && s[i + 1] == '{') {
      sb.write('^');
      final g = _extractBraceGroup(s, i + 1);
      sb.write('(${g.$1})');
      i = g.$2;
    } else {
      sb.write(s[i++]);
    }
  }
  return sb.toString();
}

String _removeSub(String s) {
  final sb = StringBuffer();
  int i = 0;
  while (i < s.length) {
    if (s[i] == '_') {
      i++;
      if (i < s.length && s[i] == '{') {
        i = _extractBraceGroup(s, i).$2;
      } else if (i < s.length) {
        i++;
      }
    } else {
      sb.write(s[i++]);
    }
  }
  return sb.toString();
}

String _expandFunc1(String s, String cmd, String Function(String) produce) {
  while (s.contains(cmd)) {
    final idx = s.indexOf(cmd);
    final after = s.substring(idx + cmd.length);
    String arg;
    int consumed;
    if (after.startsWith('{')) {
      final g = _extractBraceGroup(after, 0);
      arg = g.$1;
      consumed = g.$2;
    } else if (after.startsWith('(')) {
      final g = _extractParenGroup(after, 0);
      arg = g.$1;
      consumed = g.$2;
    } else if (after.isNotEmpty) {
      arg = after[0];
      consumed = 1;
    } else
      break;
    s = s.substring(0, idx) + produce(arg) + after.substring(consumed);
  }
  return s;
}

String _expandAbsBar(String s) {
  final sb = StringBuffer();
  int depth = 0;
  for (int i = 0; i < s.length; i++) {
    if (s[i] != '|') {
      sb.write(s[i]);
      continue;
    }
    final prev = i > 0 ? s[i - 1] : '';
    final code = prev.isEmpty ? -1 : prev.codeUnitAt(0);
    final isClose = depth > 0 &&
        (prev == ')' ||
            (code >= 48 && code <= 57) ||
            (code >= 65 && code <= 90) ||
            (code >= 97 && code <= 122));
    if (isClose) {
      sb.write(')');
      depth--;
    } else {
      sb.write('abs(');
      depth++;
    }
  }
  return sb.toString();
}

String _expandFactorial(String s) {
  s = s.replaceAllMapped(RegExp(r'\((\d+)\)!'), (m) {
    final n = int.parse(m[1]!);
    return n <= 20 ? _factorial(n).toString() : m[0]!;
  });
  return s.replaceAllMapped(RegExp(r'(\d+)!'), (m) {
    final n = int.parse(m[1]!);
    return n <= 20 ? _factorial(n).toString() : m[0]!;
  });
}

int _factorial(int n) => n <= 1 ? 1 : n * _factorial(n - 1);

String _expandBinom(String s) {
  while (s.contains(r'\binom')) {
    final idx = s.indexOf(r'\binom');
    final rest = s.substring(idx + 6);
    final ng = _extractBraceGroup(rest, 0);
    final kg = _extractBraceGroup(rest, ng.$2);
    final n = int.tryParse(ng.$1.trim());
    final k = int.tryParse(kg.$1.trim());
    if (n == null || k == null || n < 0 || k < 0 || k > n) break;
    s = s.substring(0, idx) + _binomial(n, k).toString() + rest.substring(kg.$2);
  }
  return s;
}

int _binomial(int n, int k) {
  if (k > n - k) k = n - k;
  int r = 1;
  for (int i = 0; i < k; i++) {
    r = r * (n - i) ~/ (i + 1);
  }
  return r;
}

String _insertImplicitMul(String s) {
  s = s.replaceAllMapped(RegExp(r'([0-9\)])\('), (m) => '${m[1]}*(');
  s = s.replaceAllMapped(RegExp(r'\)([0-9])'), (m) => ')*${m[1]}');
  s = s.replaceAllMapped(RegExp('([0-9])$_kFuncNames'), (m) => '${m[1]}*${m[2]}');
  s = s.replaceAllMapped(RegExp(r'\)' + _kFuncNames), (m) => ')*${m[1]}');
  return s;
}

// ── 括号提取辅助 ──────────────────────────────────────────────────────────

(String, int) _extractBraceGroup(String s, int start) {
  if (start >= s.length || s[start] != '{') {
    throw Exception('期望 { 得到 ${start < s.length ? s[start] : "EOF"}');
  }
  int depth = 0, i = start;
  while (i < s.length) {
    if (s[i] == '{') {
      depth++;
    } else if (s[i] == '}' && --depth == 0) return (s.substring(start + 1, i), i + 1);
    i++;
  }
  throw Exception('未闭合的大括号');
}

(String, int) _extractBracketGroup(String s, int start) {
  if (start >= s.length || s[start] != '[') throw Exception('期望 [');
  int depth = 0, i = start;
  while (i < s.length) {
    if (s[i] == '[') {
      depth++;
    } else if (s[i] == ']' && --depth == 0) return (s.substring(start + 1, i), i + 1);
    i++;
  }
  throw Exception('未闭合的方括号');
}

(String, int) _extractParenGroup(String s, int start) {
  if (start >= s.length || s[start] != '(') throw Exception('期望 (');
  int depth = 0, i = start;
  while (i < s.length) {
    if (s[i] == '(') {
      depth++;
    } else if (s[i] == ')' && --depth == 0) return (s.substring(start + 1, i), i + 1);
    i++;
  }
  throw Exception('未闭合的圆括号');
}

// ─── 行列式 ──────────────────────────────────────────────────────────────────

String _expandMatrixDet(String s) {
  s = s.replaceAllMapped(
    RegExp(r'\\det\s*\\begin\{[A-Za-z]*matrix\}(.*?)\\end\{[A-Za-z]*matrix\}', dotAll: true),
    (m) {
      final val = _evalMatrixDet(m.group(1)!);
      return val != null ? _formatNum(val) : m[0]!;
    },
  );
  s = s.replaceAllMapped(
    RegExp(r'\|\\begin\{[A-Za-z]*matrix\}(.*?)\\end\{[A-Za-z]*matrix\}\|', dotAll: true),
    (m) {
      final val = _evalMatrixDet(m.group(1)!);
      return val != null ? _formatNum(val) : m[0]!;
    },
  );
  s = s.replaceAllMapped(
    RegExp(r'\\begin\{[Vv]matrix\}(.*?)\\end\{[Vv]matrix\}', dotAll: true),
    (m) {
      final val = _evalMatrixDet(m.group(1)!);
      return val != null ? _formatNum(val) : m[0]!;
    },
  );
  return s;
}

double? _evalMatrixDet(String content) {
  final rowStrs = content.split(RegExp(r'\\\\'));
  final matrix = <List<double>>[];
  for (final row in rowStrs) {
    if (row.trim().isEmpty) continue;
    final cells = row.split('&');
    final rowVals = <double>[];
    for (final cell in cells) {
      final s = _evaluateExpression(cell.trim());
      if (s == null) return null;
      final v = double.tryParse(s);
      if (v == null) return null;
      rowVals.add(v);
    }
    matrix.add(rowVals);
  }
  if (matrix.isEmpty) return null;
  final n = matrix.length;
  if (matrix.any((r) => r.length != n)) return null;
  return _computeDet(matrix);
}

double? _computeDet(List<List<double>> mat) {
  final n = mat.length;
  if (n == 1) return mat[0][0];
  if (n == 2) return mat[0][0] * mat[1][1] - mat[0][1] * mat[1][0];
  double det = 0;
  for (int j = 0; j < n; j++) {
    final minor = <List<double>>[
      for (int i = 1; i < n; i++)
        [...mat[i].sublist(0, j), ...mat[i].sublist(j + 1)],
    ];
    final c = _computeDet(minor);
    if (c == null) return null;
    det += (j.isEven ? 1.0 : -1.0) * mat[0][j] * c;
  }
  return det;
}

String _formatNum(double v) {
  if (v.isNaN || v.isInfinite) return '0';
  if (v == v.truncateToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(6).replaceAll(RegExp(r'\.?0+$'), '');
}

String _expandLog(String s) {
  while (true) {
    final match = RegExp(r'\\log(?!_)').firstMatch(s);
    if (match == null) break;
    final idx = match.start;
    final after = s.substring(idx + 4);
    String arg;
    int consumed;
    if (after.startsWith('{')) {
      final g = _extractBraceGroup(after, 0);
      arg = g.$1;
      consumed = g.$2;
    } else if (after.startsWith('(')) {
      final g = _extractParenGroup(after, 0);
      arg = g.$1;
      consumed = g.$2;
    } else {
      final cmdMatch = RegExp(r'^\\[a-zA-Z]+').firstMatch(after);
      final numMatch = RegExp(r'^[\d.]+').firstMatch(after);
      if (cmdMatch != null) {
        arg = cmdMatch.group(0)!;
        consumed = cmdMatch.end;
      } else if (numMatch != null) {
        arg = numMatch.group(0)!;
        consumed = numMatch.end;
      } else if (after.isNotEmpty) {
        arg = after[0];
        consumed = 1;
      } else {
        break;
      }
    }
    s = '${s.substring(0, idx)}(ln($arg)/ln(10))${after.substring(consumed)}';
  }
  return s;
}

// 供测试文件调用
String? evaluateLatexForTest(String expr) => _evaluateExpression(expr);
String latexToInfixForTest(String expr) => _latexToInfix(expr);
