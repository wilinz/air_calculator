// ─── 识别流程 + 后处理 + 自动倒计时 + 还原 ─────────────────────────────
part of '../formula_editor_page.dart';

extension _RecognizeLogic on _FormulaEditorPageState {
  void _startAutoRecogCountdown() {
    if (_autoRecogTimer != null) return; // 已在倒计时中
    if (_suppressAutoRecog) return; // 刚撤销了识别，等用户重新落笔再开启
    if (_airCanvas.strokeCount == 0 || !_drawingEnabled || _airRecognizing)
      return;
    _autoRecogDeadline = DateTime.now().add(
      const Duration(milliseconds: _FormulaEditorPageState._kAutoRecogDelayMs),
    );
    _autoRecogProgressVN.value = 0.0;
    _autoRecogTimer = Timer(
      const Duration(milliseconds: _FormulaEditorPageState._kAutoRecogDelayMs),
      () {
        _cancelAutoRecog();
        _airRecognizeNow();
      },
    );
    _autoRecogUiTick = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_autoRecogDeadline == null) return;
      final remaining = _autoRecogDeadline!
          .difference(DateTime.now())
          .inMilliseconds;
      final progress =
          1.0 -
          (remaining / _FormulaEditorPageState._kAutoRecogDelayMs).clamp(
            0.0,
            1.0,
          );
      _autoRecogProgressVN.value = progress;
    });
  }

  void _cancelAutoRecog() {
    _autoRecogTimer?.cancel();
    _autoRecogTimer = null;
    _autoRecogUiTick?.cancel();
    _autoRecogUiTick = null;
    _autoRecogDeadline = null;
    _autoRecogProgressVN.value = 0.0;
  }

  Future<void> _airRecognizeNow() async {
    if (_airCanvas.strokeCount == 0 || _airRecognizing) return;
    // 主动识别 → 清除撤销后的抑制态
    _suppressAutoRecog = false;
    // 保存快照，供撤销识别使用
    _preRecogLatex = _latex.value;
    _preRecogStrokes = _airCanvas.strokes.map((s) => s.copy()).toList();
    setState(() {
      _airRecognizing = true;
      _airStatusText = () => 'recognizing_dots'.tr;
      _airStatusColor = Colors.blue;
    });

    // 让 "识别中..." 状态先渲染一帧，再开始重计算
    await Future<void>.delayed(const Duration(milliseconds: 16));

    // 1) 预处理（trimTail/smooth）。每条笔画后 yield 一次，避免一次性阻塞主线程
    // 注：等弧长重采样实测会让短笔画（+、−）退化点数过少，被模型误识为 \frac{}{}，已禁用
    for (final s in _airCanvas.strokes) {
      s.trimTail(enabled: true);
      s.smooth();
      await Future<void>.delayed(Duration.zero);
    }
    _airCanvasTickVN.value++; // 通知重绘平滑后的笔画

    // 2) 旋转检测（基于 MediaPipe 手部朝向，比笔画几何稳）
    final rawStrokes = List<Stroke>.from(_airCanvas.strokes);
    final size = _screenSize;
    final rot = _detectRotationCountFromHand();
    await Future<void>.delayed(Duration.zero);

    // 3) 旋转应用
    final strokes = rot == 0
        ? rawStrokes
        : _rotateStrokes(rawStrokes, size, rotCount: rot);
    await Future<void>.delayed(Duration.zero);

    // 4) 识别
    final raw = await _recService.recognize(strokes, size);
    final result = raw == null ? null : _postProcessMath(raw);

    if (!mounted) return;
    setState(() {
      _airRecognizing = false;
      if (result != null && result.isNotEmpty) {
        _airStatusText = () => '${'recognize_prefix'.tr}$result';
        _airStatusColor = Colors.green;
      } else {
        _airStatusText = () => 'recognize_failed'.tr;
        _airStatusColor = Colors.red;
      }
    });

    if (result != null && result.isNotEmpty) {
      _insert(result);
    } else {
      // 识别失败，清除快照（无需撤销）
      _preRecogLatex = null;
      _preRecogStrokes = null;
    }
    // 识别后清空空中画布
    setState(() {
      _airCanvas.clear();
      _airPicCache.picture = null;
      _airStrokeCount = 0;
    });
    _airCanvasTickVN.value++;
    _ptTracker.reset();
  }

  /// 识别后处理。实现是下面的顶层纯函数——它不碰 state，提出来才好测。
  String _postProcessMath(String input) => postProcessMathForTest(input);
}

/// 识别后处理：修正计算器场景下的常见错字
/// - 字母 x → \times（计算器里几乎不用 x 当变量）
/// - q → 9（手写 9 容易识别成 q）
/// - Greek 字母 ψ/ϕ/φ → 4，δ/σ → 6 等（不影响 \pi、\sqrt 等 LaTeX 命令）
///
/// 名字带 ForTest 是因为它同时是测试入口；`part of` 的文件里没法只对测试
/// 开放，索性明说。
String postProcessMathForTest(String input) {
  String s = input;

  // \overline{...} → 减号（手写减号常被识别为上划线）
  // 1) \overline{}（空参数） → -
  // 2) \overline{X} → X-（不太可能，X 是孤立内容）→ 仍按 - 处理避免奇怪输出
  s = s.replaceAll(RegExp(r'\\overline\s*\{[^{}]*\}'), '-');
  s = s.replaceAll(RegExp(r'\\overline\b\s*'), '-');

  // Greek/letter → digit 映射（视觉相似）
  const greekToDigit = {
    'ψ': '4',
    'ϕ': '4',
    'φ': '4',
    'δ': '6',
    'σ': '6',
    'q': '9',
    'ℓ': '1',
  };

  // 替换不在 \command 里面的孤立字符
  final buf = StringBuffer();
  int i = 0;
  while (i < s.length) {
    // 跳过 LaTeX 命令 \word（如 \pi, \times, \frac, \sqrt 等）
    if (s[i] == '\\') {
      buf.write(s[i]);
      i++;
      final cmd = StringBuffer();
      while (i < s.length && RegExp(r'[a-zA-Z]').hasMatch(s[i])) {
        cmd.write(s[i]);
        buf.write(s[i]);
        i++;
      }
      // \begin{matrix} / \end{pmatrix} 里的环境名是标识符，不是算式：
      // 底下的 x→\times、q→9、T→+ 会把 matrix 改成 matri \times，
      // 环境名一坏，渲染和求值一起失败。整组原样抄过去。
      final name = cmd.toString();
      if ((name == 'begin' || name == 'end') && i < s.length && s[i] == '{') {
        while (i < s.length) {
          buf.write(s[i]);
          final done = s[i] == '}';
          i++;
          if (done) break;
        }
      }
      continue;
    }

    final ch = s[i];

    // 字母 x → \times（裸 x，已经过滤了 \times \xi 等 LaTeX 命令）
    // 计算器场景下没有变量，统一替换
    if (ch == 'x' || ch == 'X') {
      buf.write(r' \times ');
      i++;
      continue;
    }

    // 大写 T → + （手写 + 容易被识别成 T）
    if (ch == 'T') {
      buf.write('+');
      i++;
      continue;
    }

    // 字母→数字映射
    if (greekToDigit.containsKey(ch)) {
      buf.write(greekToDigit[ch]);
      i++;
      continue;
    }

    buf.write(ch);
    i++;
  }

  // 多余空格压缩
  return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

extension _RecognizeLogicRest on _FormulaEditorPageState {
  /// 仅还原识别前的 LaTeX，笔画保留不变；快照不清除以便用户继续完整还原
  void _undoAirRecognizeLatexOnly() {
    if (_preRecogLatex == null) return;
    setState(() {
      _latex.value = _preRecogLatex!;
    });
  }

  void _undoAirRecognize() {
    if (_preRecogLatex == null || _preRecogStrokes == null) return;
    // 取消正在进行的倒计时；并抑制下一次"手离开"触发的自动识别，
    // 否则用户刚撤销就会马上又被识别覆盖
    _cancelAutoRecog();
    _suppressAutoRecog = true;
    setState(() {
      _latex.value = _preRecogLatex!;
      _airCanvas.strokes.clear();
      _airCanvas.strokes.addAll(_preRecogStrokes!.map((s) => s.copy()));
      _airCanvas.strokesVersion++;
      _airPicCache.picture = null;
      _airStrokeCount = _airCanvas.strokeCount;
      _preRecogLatex = null;
      _preRecogStrokes = null;
    });
    _airCanvasTickVN.value++;
  }
}
