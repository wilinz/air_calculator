import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:get/get.dart';
import 'package:hand_camera/hand_camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/app_translations.dart';
import '../models/gesture.dart';
import '../services/gesture_recognizer.dart';
import '../services/point_tracker.dart';
import '../services/mathwriting_recognition_service.dart';
import '../services/voice_command_service.dart';
import '../utils/latex_speech.dart';
import '../widgets/drawing_canvas.dart';

class HistoryEntry {
  final List<String> expression;
  final String result;
  final DateTime timestamp;

  HistoryEntry({
    required this.expression,
    required this.result,
    required this.timestamp,
  });
}

/// 业务逻辑控制器（不包含相机生命周期）
class AirWritingController extends GetxController {
  // --- 由 Page 在 initCamera 后写入，供坐标变换使用 ---
  double previewW = 480.0;
  double previewH = 640.0;
  Size screenSize = const Size(360, 800);

  /// Android 前置相机传感器方向（0/90/180/270）
  int sensorOrientation = 0;

  // --- 画布 / 手势 ---
  final canvasState = CanvasState();
  final pictureCache = StrokePictureCache();
  final _gestureRecognizer = GestureRecognizer();
  final _pointTracker = PointTracker(
    minSmooth: 0.55,
    maxSmooth: 0.25,
    deadZone: 2.5,
  );

  // --- 端侧 MathWriting 识别服务（全局单例） ---
  MathWritingRecognitionService get recognitionService => MathWritingRecognitionService.instance;

  // --- TTS ---
  final _tts = FlutterTts();

  Future<void> _initTts() async {
    if (Platform.isIOS) {
      // iOS: playback 类别，静音键开启时仍可播放
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    }
    await _tts.setLanguage(LocaleService.isZh ? 'zh-CN' : 'en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  // --- 响应式状态 ---

  final canvasVersion = 0.obs;
  final skeleton = Rxn<List<Offset>>();
  final indicatorPoint = Rxn<Offset>();
  final isDrawingGesture = false.obs;
  final statusText = 'waiting_camera_short'.tr.obs;
  final statusColor = Colors.orange.obs;
  final fps = 0.0.obs;
  final showSkeleton = true.obs;
  final strokeCount = 0.obs;

  // --- 方向检测（基于"写字起点在左上角"先验）---
  //
  // 不再使用重力传感器；写字总是从书写区域的左上角开始。识别前看
  // 第一笔起点相对于全部笔画包围盒的位置（分四象限）：
  //
  //   起点在 BBox 的：     设备被旋转的方向：    需把笔画旋转：
  //   左上角 (T-L)         无                    不动
  //   右上角 (T-R)         设备 90° CCW          90° CW
  //   左下角 (B-L)         设备 90° CW           90° CCW
  //   右下角 (B-R)         180° (倒置)           180°
  //
  // 这里把象限判定阈值放宽到 0.5，确保起点接近边界时也能正确分类。

  // --- 已识别的 LaTeX token 列表（对应 Python 中的 expression）
  final expression = <String>[].obs;

  /// 计算结果
  final calcResult = ''.obs;

  /// 是否正在识别中
  final isRecognizing = false.obs;

  /// 计算历史
  final history = <HistoryEntry>[].obs;

  /// 演示模式（隐藏调试信息，放大显示）
  final demoMode = false.obs;

  // --- 语音指令 ---
  final voiceService = VoiceCommandService();
  final isRecordingVoice = false.obs;
  final voiceStatusText = ''.obs;

  // --- 状态锁（识别/计算结果保持可见 2s，防止手检测状态立刻覆盖）---
  bool _statusLocked = false;
  Timer? _statusLockTimer;

  void _lockStatusFor(Duration d) {
    _statusLocked = true;
    _statusLockTimer?.cancel();
    _statusLockTimer = Timer(d, () => _statusLocked = false);
  }

  // ---------------------------------------------------------------------------
  // 生命周期
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
    // Android: 试 OpenCL（GpuDelegateV2）。回退请改回 MwBackend.xnnpack 或不传
    recognitionService
        .init(backend: Platform.isAndroid ? MwBackend.gpu : MwBackend.auto)
        .then((ok) {
      if (!ok) {
        statusText.value = 'model_load_failed_short'.tr;
        statusColor.value = Colors.red;
      }
    });

    _initTts();
    _loadApiKey();
  }

  // ---------------------------------------------------------------------------
  // 手势识别结果处理
  // ---------------------------------------------------------------------------

  void onHandDetected(HandLandmarks? hand) {
    if (hand == null) {
      skeleton.value = null;
      if (!isRecognizing.value && !_statusLocked) {
        statusText.value = 'no_hand_detected'.tr;
        statusColor.value = Colors.red;
      }
      return;
    }

    skeleton.value = hand.landmarks
        .map((l) => transformCoordinate(l.x, l.y))
        .toList();

    final gesture = _gestureRecognizer.recognize(
      hand,
      screenSize,
      mirrorX: false,
    );

    if (gesture.drawingPoint != null) {
      final raw = transformCoordinate(
        gesture.drawingPoint!.dx,
        gesture.drawingPoint!.dy,
      );
      indicatorPoint.value = raw;
      final smoothed = _pointTracker.update(raw);

      if (gesture.isDrawing) {
        if (canvasState.currentStroke == null) {
          canvasState.startStroke();
        }
        canvasState.addPoint(smoothed, pinchRatio: gesture.pinchRatio);
        canvasVersion.value++;
      } else {
        if (canvasState.currentStroke != null) {
          canvasState.currentStroke!.trimTail(enabled: true);
          canvasState.currentStroke!.smooth();
          canvasState.endStroke();
          strokeCount.value = canvasState.strokeCount;
          canvasVersion.value++;
        }
      }
    } else {
      indicatorPoint.value = null;
    }

    isDrawingGesture.value = gesture.isDrawing;
    if (!isRecognizing.value && !_statusLocked) {
      statusText.value = gesture.isDrawing
          ? '${'drawing_with_ratio'.tr}${gesture.pinchRatio.toStringAsFixed(2)})'
          : '${'stopped_with_ratio'.tr}${gesture.pinchRatio.toStringAsFixed(2)})';
      statusColor.value = gesture.isDrawing ? Colors.green : Colors.orange;
    }
  }

  // ---------------------------------------------------------------------------
  // 识别流程（对应 Python _trigger_recognize / _do_recognize）
  // ---------------------------------------------------------------------------

  void recognizeNow() {
    if (canvasState.strokeCount > 0) {
      _doRecognize();
    }
  }

  Future<void> _doRecognize() async {
    if (canvasState.strokeCount == 0) return;
    if (isRecognizing.value) return;

    isRecognizing.value = true;
    statusText.value = 'recognizing_dots'.tr;
    statusColor.value = Colors.blue;

    final rawStrokes = List<Stroke>.from(canvasState.strokes);
    final size = screenSize;
    // 由笔画轨迹综合打分判断设备朝向，旋转后送模型
    final rot = _detectRotationCount(rawStrokes); // 0/1/2/3 (×90° CW)
    final strokes = rot == 0
        ? rawStrokes
        : _rotateStrokes(rawStrokes, size, rotCount: rot);

    final result = await recognitionService.recognize(strokes, size);

    if (result != null && result.isNotEmpty) {
      expression.add(result);
      calcResult.value = '';
      statusText.value = '${'recognize_result_prefix'.tr}$result';
      statusColor.value = Colors.green;
    } else {
      statusText.value = 'recognize_failed'.tr;
      statusColor.value = Colors.red;
    }

    isRecognizing.value = false;
    _lockStatusFor(const Duration(seconds: 2));
    // 识别后清空画布（同 Python _clear_canvas after _do_recognize）
    clearCanvas();
  }

  // ---------------------------------------------------------------------------
  // 表达式操作（对应 Python _calculate / _delete_last / _clear_expr）
  // ---------------------------------------------------------------------------

  Future<void> calculate() async {
    if (expression.isEmpty) {
      statusText.value = 'recognize_first'.tr;
      statusColor.value = Colors.orange;
      _lockStatusFor(const Duration(seconds: 2));
      return;
    }
    isRecognizing.value = true;
    statusText.value = 'calculating'.tr;
    statusColor.value = Colors.blue;

    final result = await recognitionService.calculate(expression.toList());

    if (result != null) {
      final expr = expression.toList();
      calcResult.value = '= $result';
      statusText.value = '= $result';
      statusColor.value = Colors.green;
      history.insert(
        0,
        HistoryEntry(
          expression: expr,
          result: result,
          timestamp: DateTime.now(),
        ),
      );
      if (history.length > 50) history.removeRange(50, history.length);
      final speech = buildSpeechText(expr, '= $result');
      expression.clear();
      await _tts.stop(); // 打断上一次未播完的
      await _tts.speak(speech);
    } else {
      statusText.value = 'calc_failed'.tr;
      statusColor.value = Colors.red;
    }
    isRecognizing.value = false;
    _lockStatusFor(const Duration(seconds: 2));
  }

  void deleteLastToken() {
    if (expression.isNotEmpty) {
      expression.removeLast();
      calcResult.value = '';
    }
  }

  void clearExpression() {
    expression.clear();
    calcResult.value = '';
  }

  void restoreFromHistory(HistoryEntry entry) {
    expression.assignAll(entry.expression);
    calcResult.value = '= ${entry.result}';
  }

  void clearHistory() => history.clear();

  void toggleDemoMode() => demoMode.toggle();

  // ---------------------------------------------------------------------------
  // Token 编辑
  // ---------------------------------------------------------------------------

  void replaceToken(int index, String newToken) {
    if (index < 0 || index >= expression.length) return;
    expression[index] = newToken;
    calcResult.value = '';
  }

  void insertToken(int index, String token) {
    expression.insert(index, token);
    calcResult.value = '';
  }

  // ---------------------------------------------------------------------------
  // 语音指令
  // ---------------------------------------------------------------------------

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('openai_api_key') ?? '';
    if (key.isNotEmpty) voiceService.setApiKey(key);
    final url = prefs.getString('openai_base_url') ?? '';
    if (url.isNotEmpty) voiceService.setBaseUrl(url);
  }

  Future<void> saveApiSettings({
    required String key,
    required String baseUrl,
  }) async {
    voiceService.setApiKey(key);
    voiceService.setBaseUrl(baseUrl);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('openai_api_key', key);
    await prefs.setString('openai_base_url', baseUrl);
  }

  Future<void> startVoiceRecording() async {
    if (!voiceService.hasApiKey) {
      voiceStatusText.value = 'set_api_key_first'.tr;
      return;
    }
    final hasPerm = await voiceService.hasPermission();
    if (!hasPerm) {
      voiceStatusText.value = 'no_mic_perm'.tr;
      return;
    }
    await voiceService.startRecording();
    isRecordingVoice.value = true;
    voiceStatusText.value = 'recording_dots'.tr;
  }

  Future<void> stopVoiceRecordingAndProcess() async {
    if (!isRecordingVoice.value) return;
    isRecordingVoice.value = false;
    voiceStatusText.value = 'recognizing_dots'.tr;

    try {
      final json = await voiceService.stopRecordingAndRecognize(
        expression.toList(),
      );
      if (json == null) {
        voiceStatusText.value = 'voice_recognize_failed'.tr;
        return;
      }
      final action = VoiceCommandService.parseAction(json, expression.toList());
      if (action.isCalculate) {
        voiceStatusText.value = 'executing_calc'.tr;
        await calculate();
        return;
      }
      switch (action.type) {
        case VoiceActionType.append:
          expression.add(action.token!);
          calcResult.value = '';
        case VoiceActionType.replace:
          final i = action.index!;
          if (i >= 0 && i < expression.length) {
            expression[i] = action.token!;
            calcResult.value = '';
          }
        case VoiceActionType.delete:
          final i = action.index!;
          if (i >= 0 && i < expression.length) {
            expression.removeAt(i);
            calcResult.value = '';
          }
        case VoiceActionType.clear:
          expression.clear();
          calcResult.value = '';
        case VoiceActionType.calculate:
          break; // handled above
      }
      voiceStatusText.value = 'completed'.tr;
    } on VoiceActionException catch (e) {
      voiceStatusText.value = '${'cannot_understand_prefix'.tr}$e';
    } catch (e) {
      voiceStatusText.value = '${'error_prefix'.tr}$e';
    }

    _lockStatusFor(const Duration(seconds: 2));
  }

  void copyResultToClipboard() {
    if (calcResult.value.isEmpty) return;
    final text = calcResult.value.replaceFirst(RegExp(r'^=\s*'), '');
    Clipboard.setData(ClipboardData(text: text));
  }

  // ---------------------------------------------------------------------------
  // 坐标变换
  // ---------------------------------------------------------------------------

  Offset transformCoordinate(double nx, double ny) {
    // 相机自然输出方向：
    //   iOS    — AVFoundation 强制 .portrait → 纵向
    //   Android sensor=90/270 → 横向；sensor=0/180 → 纵向
    // 设备方向：screenSize 宽 > 高 即横屏。
    // 仅当二者不一致时需要把 (nx,ny) 做 90° 维度对调；同时按 sensor 方向做翻转。
    final cameraLandscape =
        Platform.isAndroid && (sensorOrientation == 90 || sensorOrientation == 270);
    final deviceLandscape = screenSize.width > screenSize.height;
    final needSwap = cameraLandscape != deviceLandscape;

    double lx, ly;
    if (needSwap) {
      switch (sensorOrientation) {
        case 270:
          lx = 1.0 - ny;
          ly = 1.0 - nx;
        case 90:
        default:
          lx = ny;
          ly = nx;
      }
    } else {
      switch (sensorOrientation) {
        case 180:
          lx = 1.0 - nx;
          ly = 1.0 - ny;
        default:
          lx = nx;
          ly = ny;
      }
    }

    final size = screenSize;
    // previewW/H 在 init 时按竖屏取向写入；横屏对调一下用作 aspect 计算。
    final previewAspect =
        deviceLandscape ? previewH / previewW : previewW / previewH;
    final screenAspect = size.width / size.height;

    double x, y;
    if (previewAspect > screenAspect) {
      final visibleW = screenAspect / previewAspect;
      x = (lx - (1.0 - visibleW) / 2) / visibleW;
      y = ly;
    } else {
      final visibleH = previewAspect / screenAspect;
      x = lx;
      y = (ly - (1.0 - visibleH) / 2) / visibleH;
    }
    return Offset(x * size.width, y * size.height);
  }

  // ---------------------------------------------------------------------------
  // 用户操作
  // ---------------------------------------------------------------------------

  void clearCanvas() {
    canvasState.clear();
    _pointTracker.reset();
    strokeCount.value = 0;
    canvasVersion.value++;
  }

  /// 综合多信号检测设备相对"正向"的旋转量。返回 0/1/2/3 个 90° CW。
  ///
  /// 写字普遍规律（用于评分每个候选旋转）：
  ///   1. 第一笔起点 → 包围盒左上区
  ///   2. 最后一笔终点 → 包围盒右侧
  ///   3. 每一笔的"起点比终点更靠左" → 单笔从左向右
  ///   4. 后续笔画的起点 x 坐标整体递增 → 多字从左向右排列
  ///   5. 整体重心垂直分布偏中（不偏极端）
  ///
  /// 对四种旋转候选分别打分，取最高。
  int _detectRotationCount(List<Stroke> strokes) {
    if (strokes.isEmpty || strokes.first.points.isEmpty) return 0;
    int totalPts = 0;
    for (final s in strokes) {
      totalPts += s.points.length;
    }
    if (totalPts < 4) return 0;

    int bestRot = 0;
    double bestScore = -double.infinity;
    for (int rot = 0; rot < 4; rot++) {
      final score = _scoreOrientation(strokes, rot);
      if (score > bestScore) {
        bestScore = score;
        bestRot = rot;
      }
    }
    return bestRot;
  }

  /// 把所有笔画按 rot 个 90° CW 旋转后（虚拟变换、只算坐标），
  /// 评估"正向书写"的吻合度。
  double _scoreOrientation(List<Stroke> strokes, int rot) {
    // 1) 在虚拟旋转坐标系下重新计算 bbox
    double xMin = double.infinity, xMax = double.negativeInfinity;
    double yMin = double.infinity, yMax = double.negativeInfinity;
    Offset r(Offset p) {
      double x = p.dx, y = p.dy;
      // 90° CW: (x,y) -> (-y, x)（这里只关心相对形状，原点不重要）
      for (int i = 0; i < (rot % 4); i++) {
        final nx = -y;
        final ny = x;
        x = nx;
        y = ny;
      }
      return Offset(x, y);
    }

    final transformed = <List<Offset>>[];
    for (final s in strokes) {
      final pts = s.points.map(r).toList(growable: false);
      transformed.add(pts);
      for (final p in pts) {
        if (p.dx < xMin) xMin = p.dx;
        if (p.dx > xMax) xMax = p.dx;
        if (p.dy < yMin) yMin = p.dy;
        if (p.dy > yMax) yMax = p.dy;
      }
    }
    final w = xMax - xMin;
    final h = yMax - yMin;
    if (w < 1 || h < 1) return 0;

    double n01(double v, double lo, double range) =>
        ((v - lo) / range).clamp(0.0, 1.0);

    // 取每笔的首/尾若干点平均
    Offset headOf(List<Offset> pts) {
      final n = pts.length < 5 ? pts.length : 5;
      double sx = 0, sy = 0;
      for (int i = 0; i < n; i++) {
        sx += pts[i].dx;
        sy += pts[i].dy;
      }
      return Offset(sx / n, sy / n);
    }

    Offset tailOf(List<Offset> pts) {
      final n = pts.length < 5 ? pts.length : 5;
      double sx = 0, sy = 0;
      for (int i = pts.length - n; i < pts.length; i++) {
        sx += pts[i].dx;
        sy += pts[i].dy;
      }
      return Offset(sx / n, sy / n);
    }

    double score = 0;

    // ── 信号 A：首笔起点应在左上区域
    final h0 = headOf(transformed.first);
    final h0nx = n01(h0.dx, xMin, w);
    final h0ny = n01(h0.dy, yMin, h);
    score += (1.0 - h0nx) * 1.5; // 越靠左越好（权重大）
    score += (1.0 - h0ny) * 1.5; // 越靠上越好

    // ── 信号 B：末笔终点应靠右
    final tn = tailOf(transformed.last);
    final tnnx = n01(tn.dx, xMin, w);
    score += tnnx * 1.0;

    // ── 信号 C：每笔的起点都应该比终点更靠左（左→右书写）
    int leftToRightStrokes = 0;
    for (final pts in transformed) {
      if (pts.length < 2) continue;
      final hp = headOf(pts);
      final tp = tailOf(pts);
      if (tp.dx > hp.dx) leftToRightStrokes++;
    }
    score += leftToRightStrokes / transformed.length * 1.5;

    // ── 信号 D：多笔之间起点 x 单调递增（多字符左→右排列）
    if (transformed.length >= 2) {
      int monotonic = 0;
      double prevX = -double.infinity;
      for (final pts in transformed) {
        final hx = headOf(pts).dx;
        if (hx > prevX) monotonic++;
        prevX = hx;
      }
      score += monotonic / transformed.length * 1.0;
    }

    return score;
  }

  /// 把笔画顺时针旋转 (rotCount × 90°)。
  /// 因为特征提取器会对笔画做包围盒归一化，绝对坐标不影响结果，
  /// 这里只需保证形状朝向正确即可（不必精确对齐画布）。
  List<Stroke> _rotateStrokes(
    List<Stroke> strokes,
    Size size, {
    required int rotCount,
  }) {
    final W = size.width;
    final H = size.height;

    Offset rotate90Cw(Offset p) => Offset(H - p.dy, p.dx);
    Offset apply(Offset p) {
      Offset q = p;
      for (int i = 0; i < (rotCount % 4); i++) {
        q = rotate90Cw(q);
      }
      return q;
    }

    return strokes
        .map(
          (s) => Stroke(
            points: s.points.map(apply).toList(),
            timestamps: List.from(s.timestamps),
            pinchRatios: List.from(s.pinchRatios),
            thickness: s.thickness,
            color: s.color,
          ),
        )
        .toList();
  }

  void toggleSkeleton() => showSkeleton.toggle();

  @override
  void onClose() {
    _statusLockTimer?.cancel();
    // recognitionService 为全局单例，不在此 dispose
    voiceService.dispose();
    _tts.stop();
    super.onClose();
  }
}
