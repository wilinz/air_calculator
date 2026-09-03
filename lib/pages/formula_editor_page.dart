library formula_editor_page;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:get/get.dart';
import 'package:hand_camera/hand_camera.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts/flutter_tts.dart';

import '../i18n/app_translations.dart';
import 'benchmark_page.dart';
import '../models/gesture.dart';
import '../utils/latex_text.dart';
import '../services/gesture_recognizer.dart';
import '../services/mathwriting_recognition_service.dart';
import '../services/point_tracker.dart';
import '../services/voice_command_service.dart';
import '../utils/latex_speech.dart';
import '../widgets/air_click.dart';
import '../widgets/app_icons.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/touch_handwriting_pad.dart';

part 'formula_editor/theme.dart';
part 'formula_editor/atoms.dart';
part 'formula_editor/keyboard_data.dart';
part 'formula_editor/blinking_cursor.dart';
part 'formula_editor/overlays.dart';
part 'formula_editor/preview_render.dart';
part 'formula_editor/air_render.dart';
part 'formula_editor/keyboard_render.dart';
part 'formula_editor/camera_logic.dart';
part 'formula_editor/gesture_logic.dart';
part 'formula_editor/recognize_logic.dart';
part 'formula_editor/rotation_utils.dart';

// ─── Entry point ─────────────────────────────────────────────────────────────

/// 打开公式编辑器页面，返回用户输入的 LaTeX，取消返回 null。
/// [allowCamera] 为 false 时隐藏空中手写摄像头按钮（避免与父页面摄像头冲突）。
Future<String?> openFormulaEditor(
  BuildContext context, {
  String initial = '',
  bool allowCamera = true,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          FormulaEditorPage(initial: initial, allowCamera: allowCamera),
    ),
  );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class FormulaEditorPage extends StatefulWidget {
  final String initial;
  final bool allowCamera;

  /// 作为主页面独立运行（无"取消/确定"，有历史记录）
  final bool isStandalone;
  const FormulaEditorPage({
    super.key,
    this.initial = '',
    this.allowCamera = true,
    this.isStandalone = false,
  });

  @override
  State<FormulaEditorPage> createState() => _FormulaEditorPageState();
}

class _HistoryEntry {
  final String expr;
  final String result;
  final DateTime time;
  _HistoryEntry(this.expr, this.result, this.time);
}

class _FormulaEditorPageState extends State<FormulaEditorPage>
    with TickerProviderStateMixin {
  StreamSubscription<HandCameraPreviewSize>? _previewSizeSub;
  late final TextEditingController _latex;
  late TabController _tab;
  final ScrollController _previewScroll = ScrollController();
  int _lastTextLen = 0;
  bool _showRaw = false;

  // 触屏手写识别
  final _hwCanvas = CanvasState();
  MathWritingRecognitionService get _recService =>
      MathWritingRecognitionService.instance;
  bool _modelReady = false;
  bool _busy = false;
  // 存为闭包，build 时再调用，保证语言切换后立刻反映在 UI 上
  String Function() _hwStatus = () => 'loading_hw_model'.tr;
  // 顶部计算结果（点击 = 后显示）
  String _calcResult = '';

  // 语音播报
  final _tts = FlutterTts();
  bool _ttsEnabled = false;

  // 计算历史（仅 standalone 模式使用）
  final _history = <_HistoryEntry>[];

  /// 算式编辑撤销栈：每次 _latex 的**文本**真正变化时，把变化前的值压进来。
  /// 挂在 controller 的 listener 上，所以键盘、退格、清空、识别几条路径都自动
  /// 覆盖，不用逐个改写那些分散的赋值点（_backspace 里有若干分支只移光标不改
  /// 文本，按文本比较正好把它们排除掉）。
  final _latexUndo = <TextEditingValue>[];
  static const _kMaxUndo = 50;
  TextEditingValue _lastLatexValue = TextEditingValue.empty;
  bool _restoringUndo = false;
  final bool _showHistory = false;

  // ── 空中手写 / 摄像头 ─────────────────────────────────────────────────────
  bool _airMode = false;
  // 横屏 + air mode 三栏布局 flag。build 里更新；_buildAirActionRow / _buildAirTabBar
  // 据此跳过原来的 72% 单手区约束（因为外层 Row 已经分好列了）。
  bool _isLandscapeAir = false;
  int? _textureId;
  bool _cameraReady = false;
  bool _permGranted = false;
  double _previewW = 480;
  double _previewH = 640;

  /// 纹理要补转的 90 度次数（逆时针）。见 HandCameraPreviewSize.quarterTurns。
  int _previewTurns = 0;

  /// 屏幕上实际看到的那幅画面的尺寸：奇数次旋转时宽高对调。
  /// 坐标变换和预览布局都得用它，不能用未旋转的 _previewW/_previewH。
  double get _shownPreviewW => _previewTurns.isEven ? _previewW : _previewH;
  double get _shownPreviewH => _previewTurns.isEven ? _previewH : _previewW;
  int _sensorOrientation = 0;
  StreamSubscription<List<HandLandmarks>>? _landmarkSub;
  Size _screenSize = const Size(360, 800);

  // 帧率统计
  final ValueNotifier<int> _fpsVN = ValueNotifier(0);
  final List<int> _frameTimestamps = [];
  static const _kFpsWindow = 30; // 用最近 30 帧计算

  final _airCanvas = CanvasState();
  final _airPicCache = StrokePictureCache();
  final _gestureRec = GestureRecognizer();
  final _ptTracker = PointTracker(
    minSmooth: 0.55,
    maxSmooth: 0.25,
    deadZone: 2.5,
  );

  // 边沿/低频 UI 状态（进入 setState）
  bool _isAirDrawing = false;
  int _airStrokeCount = 0;
  String Function() _airStatusText = () => 'waiting_camera'.tr;
  Color _airStatusColor = Colors.orange;
  bool _airRecognizing = false;
  // 识别前快照，用于撤销识别
  TextEditingValue? _preRecogLatex;
  List<Stroke>? _preRecogStrokes;
  bool _showSkeleton = false;
  bool _handDetected = false;

  // 手离开后自动识别倒计时
  Timer? _autoRecogTimer;
  DateTime? _autoRecogDeadline;
  static const _kAutoRecogDelayMs = 1500;
  // 用于倒计时 UI 刷新
  Timer? _autoRecogUiTick;
  final ValueNotifier<double> _autoRecogProgressVN = ValueNotifier(0.0);
  // 撤销识别后抑制自动识别，直到用户开始新一笔
  bool _suppressAutoRecog = false;

  // 手部朝向角度（屏幕空间下 wrist→middle_mcp 向量的 atan2），用于方向纠正
  double? _airHandAngle;

  // 空中滑动公式滚动：捏合长按激活，横向拖拽滚动
  bool _airSwipeMode = false;
  DateTime? _airSwipeDwellStart; // 并拢开始时间
  double? _airSwipeLastX; // 上一帧 X（屏幕坐标），用于计算 delta
  double? _airSwipeActivatedY; // 激活时的 Y，用于垂直越界判断
  int _airSwipeLostFrames = 0; // 检测丢失容错帧计数
  int _drawLostFrames = 0; // 绘制 isDrawing 短暂丢失容错（防快速移动断笔）
  static const int _kDrawLostFramesTol =
      2; // 约 70ms @ 30Hz（recognizer 已做速度自适应滞回）
  static const int _kSwipeLostFramesTol = 6; // 允许丢失帧数（~200ms@30Hz）
  // 滑动 UI 状态：null=无, progress∈[0,1)=蓄力中, 1=已激活
  final ValueNotifier<_SwipeIndicatorState?> _airSwipeVN = ValueNotifier(null);
  static const int _kSwipeDwellMs = 500;
  static const double _kSwipeDeadZone = 4.0;
  static const double _kSwipeVerticalCancel = 100.0;

  // 空中悬停点击控制器
  final _airClick = AirClickController();
  // 高风险按钮（模式切换）用更长 dwell，避免误触
  final _airClickSafe = AirClickController(
    dwellDuration: const Duration(milliseconds: 3000),
  );
  final _previewKey = GlobalKey(); // 用于获取公式预览区屏幕坐标，判断滑动手势有效区域

  // 轨迹绘制开关（关闭时捏合手势不绘制，只做悬停点击）
  bool _drawingEnabled = true;

  /// 拖动累计像素数；每 _kPxPerStep 像素移动一个停靠点。
  double _dragAccum = 0;
  static const double _kPxPerStep = 18.0;

  bool _cameraBusy = false;

  // 剪刀模式
  bool _scissorMode = false;
  int? _scissorTargetIdx;
  DateTime? _scissorDwellStart;
  static const _scissorDwellMs = 800;
  final _scissorVN = ValueNotifier<_ScissorOverlayState?>(null);

  // 唯一 id 计数器（每次 build 自增，给匿名按钮分发稳定 id）
  int _airIdSeq = 0;
  String _nextAirId(String prefix) => '$prefix#${_airIdSeq++}';

  /// 在空中模式时把任意 widget 包装成可悬停点击；其他模式直接返回原 widget。
  /// 紧凑型顶栏图标按钮：去掉 IconButton 的 48dp 默认尺寸，节省空间
  Widget _topIcon(
    String id, {
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return _air(
      id,
      onTap,
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }

  /// 把算式回退到上一次的样子。选区一并恢复，光标停在当时的位置。
  void _undoLatex() {
    if (_latexUndo.isEmpty) return;
    final prev = _latexUndo.removeLast();
    _restoringUndo = true;
    _latex.value = prev;
    _lastLatexValue = prev;
    _lastTextLen = prev.text.length;
    _restoringUndo = false;
    setState(() => _calcResult = '');
  }

  /// 底部安全区高度（home indicator / 屏幕圆角）。软键盘弹出时 padding.bottom
  /// 归 0，由 viewInsets 接管，正是想要的：那时底边被键盘盖住，不用再让。
  double get _safeBottom => MediaQuery.of(context).padding.bottom;

  Widget _air(String id, VoidCallback? onTap, Widget child) {
    if (!_airMode || onTap == null) return child;
    return AirClickable(
      id: id,
      controller: _airClick,
      onTap: onTap,
      child: child,
    );
  }

  // 语音指令
  final _voiceService = VoiceCommandService();
  bool _voiceRecording = false;
  String Function() _voiceStatus = () => '';
  Timer? _voiceStatusClear;

  // 高频帧状态（每帧 30Hz 更新；用 ValueNotifier 局部刷新，绕开 widget 树重建）
  final ValueNotifier<Offset?> _airIndicatorVN = ValueNotifier(null);
  final ValueNotifier<List<Offset>?> _airSkeletonVN = ValueNotifier(null);
  final ValueNotifier<int> _airCanvasTickVN = ValueNotifier(0);
  final ValueNotifier<bool> _isAirDrawingVN = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    // native 端推送预览画面尺寸与界面朝向（旋转时会重新推）。
    // Android 上纹理里的画面只相对设备自然朝向摆正，尺寸恒定，屏幕转了多少
    // 由 quarterTurns 交给 RotatedBox 补；iOS 的 quarterTurns 恒为 0。
    _previewSizeSub = HandCamera.previewSizeStream.listen((s) {
      if (!mounted) return;
      if (_previewW == s.width.toDouble() &&
          _previewH == s.height.toDouble() &&
          _previewTurns == s.quarterTurns) {
        return;
      }
      setState(() {
        _previewW = s.width.toDouble();
        _previewH = s.height.toDouble();
        _previewTurns = s.quarterTurns;
      });
    });
    _latex = TextEditingController(text: widget.initial);
    _lastTextLen = widget.initial.length;
    _lastLatexValue = _latex.value;
    _latex.addListener(() {
      final newLen = _latex.text.length;
      final lengthChanged = newLen != _lastTextLen;
      _lastTextLen = newLen;
      // 文本变了才记一步；纯光标移动不记，否则撤销会空走几下。
      // _restoringUndo 期间跳过，避免撤销自己把恢复前的值又压回栈里。
      if (!_restoringUndo && _latex.text != _lastLatexValue.text) {
        _latexUndo.add(_lastLatexValue);
        if (_latexUndo.length > _kMaxUndo) _latexUndo.removeAt(0);
      }
      _lastLatexValue = _latex.value;
      setState(() {});
      // 仅在文本变化（插入/退格）时自动滚动；纯光标移动不滚（防止把光标滚出屏幕）
      if (lengthChanged) _scheduleScrollToCursor();
    });
    // 非空中模式：[手写] + 6 类键盘 = 7 个 tab
    _tab = TabController(length: _kCategories.length + 1, vsync: this);
    _tab.addListener(_onTabAnimationEnd);
    _initRecognition();
    _loadVoiceApiKey();
    _initTts();
    // air mode 下 preview 横向滚动时刷新 AirClickable 的 cursor stop 坐标
    _previewScroll.addListener(() {
      if (_airMode && mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setSrcCursor(_latex.text.length);
    });
  }

  Future<void> _loadVoiceApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('openai_api_key') ?? '';
    final url = prefs.getString('openai_base_url') ?? '';
    if (key.isNotEmpty) _voiceService.setApiKey(key);
    if (url.isNotEmpty) _voiceService.setBaseUrl(url);
  }

  Future<void> _saveVoiceApiSettings({
    required String key,
    required String baseUrl,
  }) async {
    _voiceService.setApiKey(key);
    _voiceService.setBaseUrl(baseUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('openai_api_key', key);
    await prefs.setString('openai_base_url', baseUrl);
  }

  Future<void> _initRecognition() async {
    final ok = await _recService.init(
      backend: Platform.isAndroid ? MwBackend.gpu : MwBackend.auto,
    );
    if (!mounted) return;
    setState(() {
      _modelReady = ok;
      _hwStatus = ok
          ? () => 'write_then_recognize'.tr
          : () => 'model_load_failed'.tr;
    });
  }

  /// 切换空中模式时重建 TabController，让 tab 数量与可见 panel 一致：
  /// - 空中模式：[Air, 手写, ...类别] = _kCategories.length + 2
  /// - 非空中：  [手写, ...类别]      = _kCategories.length + 1
  void _rebuildTabController({required bool airMode, int initialIndex = 0}) {
    _tab.removeListener(_onTabAnimationEnd);
    _tab.dispose();
    final len = airMode ? _kCategories.length + 2 : _kCategories.length + 1;
    _tab = TabController(
      length: len,
      vsync: this,
      initialIndex: initialIndex.clamp(0, len - 1),
    );
    _tab.addListener(_onTabAnimationEnd);
  }

  void _onTabAnimationEnd() {
    if (!_tab.indexIsChanging && _airMode && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _previewSizeSub?.cancel();
    _tab.removeListener(_onTabAnimationEnd);
    _landmarkSub?.cancel();
    // widget dispose 不能 async，unawaited 保证 native 侧最终释放
    if (_cameraReady) unawaited(HandCamera.dispose());
    // _recService 为全局单例，不在此 dispose
    _previewScroll.dispose();
    _latex.dispose();
    _tab.dispose();
    _airIndicatorVN.dispose();
    _airSkeletonVN.dispose();
    _airCanvasTickVN.dispose();
    _isAirDrawingVN.dispose();
    _tts.stop();
    _airClick.dispose();
    _airClickSafe.dispose();
    _scissorVN.dispose();
    _airSwipeVN.dispose();
    _autoRecogTimer?.cancel();
    _autoRecogUiTick?.cancel();
    _autoRecogProgressVN.dispose();
    _fpsVN.dispose();
    _voiceStatusClear?.cancel();
    unawaited(_voiceService.dispose());
    super.dispose();
  }

  // ── Editing helpers ──────────────────────────────────────────────────────

  void _insert(String text, {int? cursorAfter}) {
    final v = _latex.value;
    final s = v.selection;
    final start = s.isValid ? s.start : v.text.length;
    final end = s.isValid ? s.end : v.text.length;
    // 别让插入的字母粘到左边的命令名上（\pi + e = \pie）
    if (needsSpaceBeforeInsert(v.text, start, text)) {
      text = ' $text';
      if (cursorAfter != null) cursorAfter += 1;
    }
    final newText = v.text.replaceRange(start, end, text);
    final pos =
        (cursorAfter != null ? start + cursorAfter : start + text.length).clamp(
          0,
          newText.length,
        );
    _latex.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos),
    );
  }

  void _backspace() {
    final v = _latex.value;
    final s = v.selection;
    if (!s.isValid) return;
    if (s.start != s.end) {
      _insert('');
      return;
    }
    final pos = s.start;
    if (pos == 0) return;

    final tree = _parseAtoms(v.text, 0, v.text.length);
    final hit = _findEnclosingSlot(tree, pos);

    if (hit != null) {
      // 槽起点：不删字符，只移动光标——退到同结构的前一个槽末尾，
      // 没有前一个槽才跳出整个结构。全空则整体删掉。
      if (pos == hit.slot.contentStart) {
        final target = _backspaceAtSlotStart(hit.atom, hit.slot);
        if (target == null) {
          _latex.value = TextEditingValue(
            text: v.text.replaceRange(hit.atom.srcStart, hit.atom.srcEnd, ''),
            selection: TextSelection.collapsed(offset: hit.atom.srcStart),
          );
        } else {
          _latex.value = v.copyWith(
            selection: TextSelection.collapsed(offset: target),
          );
        }
        return;
      }
      // 槽中间：与顶层同一套判断，命令叶子整体删除而不是削掉一个字母
      final r = _backspaceInSiblings(hit.slot.children, pos);
      _latex.value = TextEditingValue(
        text: v.text.replaceRange(r.start, r.end, ''),
        selection: TextSelection.collapsed(offset: r.caret),
      );
      return;
    }

    // 顶层：同一套判断
    final r = _backspaceInSiblings(tree, pos);
    _latex.value = TextEditingValue(
      text: v.text.replaceRange(r.start, r.end, ''),
      selection: TextSelection.collapsed(offset: r.caret),
    );
  }

  // ── 解析树辅助 ────────────────────────────────────────────────────────


  /// 在顶层 atoms 中找以 pos 结束的 atom（不递归）
  void _moveCursor(int dir) {
    final v = _latex.value;
    final s = v.selection;
    if (!s.isValid) return;
    final pos = (s.start + dir).clamp(0, v.text.length);
    _latex.value = v.copyWith(selection: TextSelection.collapsed(offset: pos));
  }

  void _onKey(_MathKey key) {
    if (key.isBack) {
      _backspace();
      return;
    }
    if (key.isCursorMove) {
      _moveCursor(key.moveDir);
      return;
    }
    _insert(key.insert, cursorAfter: key.cursor);
  }

  // ── Cursor helpers ──────────────────────────────────────────

  void _setSrcCursor(int pos) {
    final p = pos.clamp(0, _latex.text.length);
    _latex.selection = TextSelection.collapsed(offset: p);
  }

  /// 编辑或光标变更后，下一帧把预览滚动条对齐到光标位置。
  /// 简单策略：光标在末尾 → 滚到右端；其它 → 按比例估算。
  void _scheduleScrollToCursor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_previewScroll.hasClients) return;
      final pos = _latex.selection.isValid
          ? _latex.selection.start
          : _latex.text.length;
      final maxScroll = _previewScroll.position.maxScrollExtent;
      if (maxScroll <= 0) return;
      // 光标在末尾 → 直接到右端；否则按字符位置粗略对齐
      final target = pos >= _latex.text.length
          ? maxScroll
          : (maxScroll * pos / _latex.text.length).clamp(0.0, maxScroll);
      _previewScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  // ── 手写识别 / 计算 ─────────────────────────────────────────

  Future<void> _recognizeHandwriting(Size size) async {
    if (!_modelReady || _busy) return;
    if (_hwCanvas.strokes.isEmpty) {
      setState(() => _hwStatus = () => 'write_first'.tr);
      return;
    }
    setState(() {
      _busy = true;
      _hwStatus = () => 'recognizing_dots'.tr;
    });
    final raw = await _recService.recognize(List.of(_hwCanvas.strokes), size);
    final result = raw == null ? null : _postProcessMath(raw);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == null || result.isEmpty) {
      setState(() => _hwStatus = () => 'recognize_failed'.tr);
      return;
    }
    // 把识别结果插入到当前光标位置
    _insert(result);
    _hwCanvas.clear();
    setState(() => _hwStatus = () => '${'recognize_prefix'.tr}$result');
  }

  void _setVoiceStatus(String Function() s, {Duration? autoClear}) {
    setState(() => _voiceStatus = s);
    _voiceStatusClear?.cancel();
    if (autoClear != null) {
      _voiceStatusClear = Timer(autoClear, () {
        if (!mounted) return;
        setState(() => _voiceStatus = () => '');
      });
    }
  }

  Future<void> _voiceStart() async {
    if (_voiceRecording) return;
    if (!_voiceService.hasApiKey) {
      _setVoiceStatus(
        () => 'set_api_key_in_corner'.tr,
        autoClear: const Duration(seconds: 3),
      );
      return;
    }
    if (!await _voiceService.hasPermission()) {
      _setVoiceStatus(
        () => 'no_mic_perm'.tr,
        autoClear: const Duration(seconds: 3),
      );
      return;
    }
    await _voiceService.startRecording();
    setState(() {
      _voiceRecording = true;
      _voiceStatus = () => 'recording_release_to_send'.tr;
    });
  }

  Future<void> _voiceStopAndProcess() async {
    if (!_voiceRecording) return;
    setState(() {
      _voiceRecording = false;
      _voiceStatus = () => 'recognizing_voice'.tr;
    });
    try {
      final r = await _voiceService.stopRecordingAndEditLatex(_latex.text);
      if (!mounted) return;
      if (r.newLatex == null) {
        _setVoiceStatus(
          () => 'could_not_recognize'.tr,
          autoClear: const Duration(seconds: 2),
        );
        return;
      }
      _latex.value = TextEditingValue(
        text: r.newLatex!,
        selection: TextSelection.collapsed(offset: r.newLatex!.length),
      );
      // 语音流程：总是自动计算（用户口语很少说"计算"）+ 总是播报（语音交互期望语音反馈）
      _setVoiceStatus(
        () => 'updated_auto_calc'.tr,
        autoClear: const Duration(seconds: 2),
      );
      await _calculateForceSpeak();
    } catch (e) {
      if (!mounted) return;
      _setVoiceStatus(
        () => '${'error_prefix'.tr}$e',
        autoClear: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _showVoiceApiKeyDialog() async {
    final keyCtrl = TextEditingController(text: _voiceService.apiKey ?? '');
    final urlCtrl = TextEditingController(text: _voiceService.baseUrl);
    String chatModel = _voiceService.chatModel;
    String audioModel = _voiceService.audioModel;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('ai_settings'.tr),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    hintText: 'sk-...',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.openai.com',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: kChatModelOptions.contains(chatModel)
                      ? chatModel
                      : null,
                  decoration: InputDecoration(labelText: 'chat_model'.tr),
                  items: kChatModelOptions
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setLocal(() => chatModel = v);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: kAudioModelOptions.contains(audioModel)
                      ? audioModel
                      : null,
                  decoration: InputDecoration(labelText: 'audio_model'.tr),
                  items: kAudioModelOptions
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setLocal(() => audioModel = v);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'gateway_hint'.tr,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(height: 24),
                // 语言切换
                Row(
                  children: [
                    const Icon(Icons.language, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text('language'.tr)),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'zh', label: Text('中文')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {LocaleService.isZh ? 'zh' : 'en'},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) {
                        // 切换 locale 后让 GetX 自己驱动整树重建；
                        // 不能在 onSelectionChanged 同步里再 setState/setLocal，
                        // 否则会造成 InheritedElement._dependents 断言失败。
                        final next = s.first == 'zh'
                            ? const Locale('zh', 'CN')
                            : const Locale('en', 'US');
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          LocaleService.setLocale(next);
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 骨架显示开关
                Row(
                  children: [
                    Icon(
                      _showSkeleton ? Icons.visibility : Icons.visibility_off,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('skeleton'.tr)),
                    Switch(
                      value: _showSkeleton,
                      onChanged: (v) {
                        setLocal(() {});
                        setState(() => _showSkeleton = v);
                      },
                    ),
                  ],
                ),
                const Divider(height: 24),
                ListTile(
                  leading: const Icon(Icons.speed),
                  title: Text('bench_entry'.tr),
                  trailing: const Icon(Icons.chevron_right),
                  contentPadding: EdgeInsets.zero,
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BenchmarkPage(service: _recService),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('cancel'.tr),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('save'.tr),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      _voiceService.setChatModel(chatModel);
      _voiceService.setAudioModel(audioModel);
      await _saveVoiceApiSettings(key: keyCtrl.text, baseUrl: urlCtrl.text);
      if (mounted) setState(() {});
    }
  }

  Future<void> _initTts() async {
    if (Platform.isIOS) {
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ], IosTextToSpeechAudioMode.defaultMode);
    }
    await _tts.setLanguage(LocaleService.isZh ? 'zh-CN' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  void _speakResult(String latex, String result) {
    if (!_ttsEnabled) return;
    final expr = latexToSpeech(latex);
    final res = result.startsWith('= ') ? result.substring(2) : result;
    _tts.speak('$expr ${'equals_word'.tr} $res');
  }

  /// 强制播报版本：忽略 _ttsEnabled，用于语音交互场景下的反馈
  Future<void> _calculateForceSpeak() async {
    final src = _latex.text.trim();
    if (src.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _calcResult = '...';
    });
    final result = await _recService.calculate([src]);
    if (!mounted) return;
    final resultStr = result == null ? 'calc_failed'.tr : '= $result';
    setState(() {
      _busy = false;
      _calcResult = resultStr;
      if (widget.isStandalone && result != null) {
        _history.insert(0, _HistoryEntry(src, result, DateTime.now()));
        if (_history.length > 50) _history.removeRange(50, _history.length);
      }
    });
    // 强制播报（不看 _ttsEnabled）
    if (result != null) {
      final expr = latexToSpeech(src);
      _tts.speak('$expr ${'equals_word'.tr} $result');
    } else {
      _tts.speak('calc_failed'.tr);
    }
  }

  Future<void> _calculateNow() async {
    final src = _latex.text.trim();
    if (src.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _calcResult = '...';
    });
    final result = await _recService.calculate([src]);
    if (!mounted) return;
    final resultStr = result == null ? 'calc_failed'.tr : '= $result';
    setState(() {
      _busy = false;
      _calcResult = resultStr;
      if (widget.isStandalone && result != null) {
        _history.insert(0, _HistoryEntry(src, result, DateTime.now()));
        if (_history.length > 50) _history.removeRange(50, _history.length);
      }
    });
    if (result != null) _speakResult(src, resultStr);
  }

  // ── 空中手写：摄像头生命周期 ──────────────────────────────────────────────

  // ── 坐标变换（与 AirWritingController 一致） ─────────────────────────────

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = mq.viewInsets.bottom;
    _airIdSeq = 0; // 每次 build 重置，让 _nextAirId 给出稳定序列

    // 在 air mode 下更新 screenSize 供坐标变换使用。
    //
    // 这里必须是**整个 FlutterView 的尺寸**，不能扣系统栏：air mode 的相机预览和
    // 各层 overlay 都是 Stack(fit: expand) 里的 Positioned.fill，铺满全屏（含状态栏
    // 与导航栏区域，应用是 edge-to-edge 的）。_transformCoord 把归一化 landmark
    // 乘上这个尺寸得到 overlay 的绘制坐标，两者必须同一个坐标系。
    //
    // 之前 Android 分支减掉了 padding.top + padding.bottom，纵向比例就小了一截：
    // y=0 处仍然重合，越往下误差越大（约 y × 系统栏总高），表现为手越往下点越飘。
    if (_airMode) {
      _screenSize = mq.size;
    }

    _isLandscapeAir = _airMode && mq.orientation == Orientation.landscape;

    final editorScaffold = Scaffold(
      backgroundColor: _airMode ? Colors.transparent : _Pal.scaffold,
      // air mode 不让 Scaffold 自动避让，避免和外层 Material/Stack 双重收缩；
      // 我们自己用 SizedBox(bottom) 在 Column 末尾加 padding
      resizeToAvoidBottomInset: !_airMode,
      // 横屏 air mode 把顶栏图标移到左侧蓝栏，AppBar 隐藏
      appBar: _isLandscapeAir ? null : _buildAppBar(context),
      body: _isLandscapeAir
          ? _buildLandscapeAirBody(mq, bottom)
          : Column(
              children: [
                _buildPreview(),
                _buildCursorDragBar(),
                _buildRawRow(),
                const Divider(color: _Pal.divider, height: 1),
                _buildQuickToolbar(),
                // air mode 专用横向 actions 行（替代左侧 rail，保持单手区）
                if (_airMode) _buildAirActionRow(),
                const Divider(color: _Pal.divider, height: 1),
                _buildTabBar(),
                Expanded(
                  child: _airMode
                      ? TabBarView(
                          controller: _tab,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            // [0] 空中提示面板：全宽背景 + 一行提示
                            Stack(
                              children: [
                                Positioned.fill(
                                  child: ColoredBox(
                                    color: _airBg(_Pal.scaffold),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.topLeft,
                                  child: SizedBox(
                                    width: _screenSize.width * 0.72,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      child: Text(
                                        'air_draw_hint'.tr,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // [1] 触摸手写面板：全宽，背景沿用 _airBg(_Pal.scaffold)
                            _buildHandwritingPanel(),
                            // [2..] 键盘分类面板：全宽背景 + 72% 内容
                            ..._kCategories.map(
                              (cat) => Stack(
                                children: [
                                  Positioned.fill(
                                    child: ColoredBox(
                                      color: _airBg(_Pal.scaffold),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.topLeft,
                                    child: SizedBox(
                                      width: _screenSize.width * 0.72,
                                      child: _buildGrid(cat),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : TabBarView(
                          controller: _tab,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _buildHandwritingPanel(),
                            ..._kCategories.map(_buildGrid),
                          ],
                        ),
                ),
                // 只处理软键盘。底部安全区不在这里加：这一层加 SizedBox 是没有
                // 背景的空白，会漏出后面的相机预览。安全区由各面板自己在**背景
                // 内部**让出（同 _buildAirControlBar 的做法），背景仍铺到屏幕底边。
                if (bottom > 0) SizedBox(height: bottom),
              ],
            ),
    );

    if (!_airMode) return editorScaffold;

    // ── 空中手写模式（单手模式）──────────────────────────────────────
    // 整个 UI 限制在屏幕左侧 ~72% 宽度内，右侧空出来给手部活动 / 识别
    //（避免任何可点击控件出现在屏幕右边——手伸到右边会出镜头）。
    // air actions 不再走左侧 rail，而是作为横向一行集成到 editorScaffold
    // 顶部（在 _buildAirActionRow 里渲染）。
    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 相机预览（铺满全屏）
          if (_cameraReady && _textureId != null)
            Positioned.fill(child: _buildCameraPreview()),
          if (!_cameraReady)
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // 编辑器 UI——铺满全宽（背景延伸到右侧），内容区在各 build 方法内用 SizedBox(uiWidth) 限制
          // 有笔画或正在绘制时降低前景透明度，让用户专注画布
          ValueListenableBuilder<bool>(
            valueListenable: _isAirDrawingVN,
            builder: (_, drawing, __) => AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: (drawing || _airStrokeCount > 0) ? 0.6 : 1.0,
              child: editorScaffold,
            ),
          ),

          // 笔迹 overlay
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: _airCanvasTickVN,
                  builder: (_, __, ___) => ValueListenableBuilder<Offset?>(
                    valueListenable: _airIndicatorVN,
                    builder: (_, indicator, ___) =>
                        ValueListenableBuilder<bool>(
                          valueListenable: _isAirDrawingVN,
                          builder: (_, drawing, ___) => DrawingCanvas(
                            canvasState: _airCanvas,
                            pictureCache: _airPicCache,
                            currentPoint: indicator,
                            isDrawing: drawing,
                            lineColor: const Color(0xFF39FF14),
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),

          if (_showSkeleton)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: ValueListenableBuilder<List<Offset>?>(
                    valueListenable: _airSkeletonVN,
                    builder: (_, sk, ___) => sk == null
                        ? const SizedBox.shrink()
                        : CustomPaint(
                            painter: HandSkeletonPainter(
                              landmarks: sk,
                              visible: true,
                              useRawCoordinates: true,
                            ),
                          ),
                  ),
                ),
              ),
            ),

          // hover 进度环
          Positioned.fill(
            child: RepaintBoundary(
              child: AirClickOverlay(controller: _airClick),
            ),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: AirClickOverlay(controller: _airClickSafe),
            ),
          ),

          // 剪刀模式 overlay（最顶层）
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: ValueListenableBuilder<_ScissorOverlayState?>(
                  valueListenable: _scissorVN,
                  builder: (_, state, __) {
                    if (state == null) return const SizedBox.shrink();
                    return CustomPaint(
                      painter: _ScissorPainter(state: state),
                      size: Size.infinite,
                    );
                  },
                ),
              ),
            ),
          ),
          // 滑动模式 overlay
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: ValueListenableBuilder<_SwipeIndicatorState?>(
                  valueListenable: _airSwipeVN,
                  builder: (_, state, __) {
                    if (state == null) return const SizedBox.shrink();
                    return CustomPaint(
                      painter: _SwipeIndicatorPainter(state: state),
                      size: Size.infinite,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 空中模式：横向 actions 行（单手模式，集成在 editorScaffold 顶部）──

  /// air mode 下用深色半透明替代白色系背景，普通模式返回原色。
  Color _airBg(Color c, {double alpha = 0.4}) =>
      _airMode ? Colors.black.withValues(alpha: alpha) : c;

  // air mode 文字色计算属性
  Color get _fgText => _airMode ? Colors.white : _Pal.text;
  Color get _fgMuted => _airMode ? Colors.white70 : _Pal.textMuted;
  Color get _fgWeak => _airMode ? Colors.white38 : _Pal.textWeak;
  Color get _fgFormula => _airMode ? Colors.white : _Pal.formulaText;
  Color get _fgFracBar => _airMode ? Colors.white70 : _Pal.fracBar;
  Color get _fgPH => _airMode ? Colors.white30 : _Pal.placeholder;
}
