import 'dart:math' as math;
import 'dart:ui';
import 'package:hand_camera/hand_camera.dart';
import '../models/gesture.dart';

/// 手势识别器
/// 根据手部关键点识别手势类型
class GestureRecognizer {
  /// 捏合阈值（相对于手掌大小的比例）
  static const double pinchStartThreshold = 0.30;
  static const double pinchStopThresholdMin = 0.35;
  static const double pinchStopThresholdMax = 0.70; // 高速时大幅放宽，吃掉抖动

  /// EMA 平滑 pinchRatio：抑制单帧抖动
  static const double _kPinchEmaAlpha = 0.45;
  double? _smoothedPinchRatio;

  /// 速度阈值（用于动态调整）
  static const double speedThresholdLow = 0.005;
  static const double speedThresholdHigh = 0.05;

  bool _isCurrentlyDrawing = false;
  double _lastX = 0;
  double _lastY = 0;
  int _drawingFrameCount = 0;
  static const int _startupProtectionFrames = 10;

  /// 释放滞回：必须连续 N 帧 ratio 高于阈值才真正判为释放，
  /// 防止快速移动时 landmark 噪声导致单帧 ratio 抖动击穿阈值断笔。
  int _releaseConfirmCount = 0;
  static const int _kReleaseConfirmFrames = 2; // EMA 已平滑，仅作小兜底


  // MediaPipe 手部关键点索引（固定顺序，0-20）
  static const int _wristIdx = 0;
  static const int _thumbTipIdx = 4;
  static const int _thumbMcpIdx = 2;
  static const int _indexTipIdx = 8;
  static const int _indexMcpIdx = 5;
  static const int _middleTipIdx = 12;
  static const int _middleMcpIdx = 9;
  static const int _ringTipIdx = 16;
  static const int _ringMcpIdx = 13;
  static const int _pinkyTipIdx = 20;
  static const int _pinkyMcpIdx = 17;

  // 食指各节点：MCP=5, PIP=6, DIP=7, tip=8
  // 中指各节点：MCP=9, PIP=10, DIP=11, tip=12
  static const _indexJoints  = [5, 6, 7, 8];
  static const _middleJoints = [9, 10, 11, 12];

  /// 食指+中指并拢阈值（从根部到指尖递增，指尖高度差容差更大）
  static const _twoFingerThresholds = [0.35, 0.37, 0.38, 0.40]; // MCP→tip

  /// 识别手势
  /// [mirrorX] 是否镜像X坐标（前置相机需要）
  GestureResult recognize(
    HandLandmarks hand,
    Size canvasSize, {
    bool mirrorX = false,
  }) {
    if (hand.landmarks.length < 21) return GestureResult.none;

    // NormalizedLandmark 坐标已归一化为 0-1
    final wrist = hand.landmarks[_wristIdx];
    final thumbTip = hand.landmarks[_thumbTipIdx];
    final indexTip = hand.landmarks[_indexTipIdx];
    final middleTip = hand.landmarks[_middleTipIdx];
    final middleMcp = hand.landmarks[_middleMcpIdx];

    final palmSize = _dist(wrist.x, wrist.y, middleMcp.x, middleMcp.y);
    if (palmSize <= 0) return GestureResult.none;

    final pinchDistance = _dist(thumbTip.x, thumbTip.y, indexTip.x, indexTip.y);
    final rawPinchRatio = pinchDistance / palmSize;
    // EMA 平滑：消除单帧抖动，让阈值判断稳定
    _smoothedPinchRatio = _smoothedPinchRatio == null
        ? rawPinchRatio
        : _kPinchEmaAlpha * rawPinchRatio + (1 - _kPinchEmaAlpha) * _smoothedPinchRatio!;
    final pinchRatio = _smoothedPinchRatio!;

    // 各手指伸直判断：tip 离手腕距离 > MCP 离手腕距离
    bool _fingerExtended(int tipIdx, int mcpIdx) {
      final tip = hand.landmarks[tipIdx];
      final mcp = hand.landmarks[mcpIdx];
      return _dist(tip.x, tip.y, wrist.x, wrist.y) >
          _dist(mcp.x, mcp.y, wrist.x, wrist.y);
    }

    final indexMcp = hand.landmarks[_indexJoints[0]]; // landmark 5
    final indexExtended = _fingerExtended(_indexTipIdx, _indexMcpIdx);
    final middleExtended = _fingerExtended(_middleTipIdx, _middleMcpIdx);
    final ringExtended   = _fingerExtended(_ringTipIdx,   _ringMcpIdx);
    final pinkyExtended  = _fingerExtended(_pinkyTipIdx,  _pinkyMcpIdx);
    final thumbExtended  = _fingerExtended(_thumbTipIdx,  _thumbMcpIdx);

    // 五指完全张开：四根手指全部伸直 + 拇指伸直 + 未捏合
    final isFullyOpen = indexExtended && middleExtended && ringExtended &&
        pinkyExtended && thumbExtended && pinchRatio > pinchStopThresholdMax;

    // 2) 每个关节对的距离均需小于递增阈值。
    // 用 2D 欧氏距离而非仅 x 差：原 x-axis 公式依赖"手指在画面里竖直"的隐含
    // 假设；横屏 + iOS 强制 .portrait videoOrientation 时，MediaPipe 收到的仍是
    // 竖向 texture，手指躺成水平，x 差≈0 会导致误判。欧氏距离方向无关，竖屏
    // 下与原公式等价（dy≈0），横屏也成立。
    bool isTwoFingerPinch = indexExtended && middleExtended;
    if (isTwoFingerPinch) {
      for (int i = 0; i < _indexJoints.length; i++) {
        final ij = hand.landmarks[_indexJoints[i]];
        final mj = hand.landmarks[_middleJoints[i]];
        final d = _dist(ij.x, ij.y, mj.x, mj.y);
        if ((d / palmSize) >= _twoFingerThresholds[i]) {
          isTwoFingerPinch = false;
          break;
        }
      }
    }

    final dx = indexTip.x - _lastX;
    final dy = indexTip.y - _lastY;
    final speed = dx * dx + dy * dy;
    _lastX = indexTip.x;
    _lastY = indexTip.y;

    double stopThreshold;
    if (speed <= speedThresholdLow * speedThresholdLow) {
      stopThreshold = pinchStopThresholdMin;
    } else if (speed >= speedThresholdHigh * speedThresholdHigh) {
      stopThreshold = pinchStopThresholdMax;
    } else {
      final t =
          (speed - speedThresholdLow * speedThresholdLow) /
          (speedThresholdHigh * speedThresholdHigh -
              speedThresholdLow * speedThresholdLow);
      stopThreshold =
          pinchStopThresholdMin +
          t * (pinchStopThresholdMax - pinchStopThresholdMin);
    }

    if (_isCurrentlyDrawing && _drawingFrameCount < _startupProtectionFrames) {
      stopThreshold = pinchStopThresholdMax;
      _drawingFrameCount++;
    }

    bool isPinching;
    if (_isCurrentlyDrawing) {
      if (pinchRatio < stopThreshold) {
        isPinching = true;
        _releaseConfirmCount = 0;
      } else {
        // 速度自适应滞回：慢速立即抬笔（拉丝最少），高速容忍 N 帧
        // speedThresholdLow→0 帧, speedThresholdHigh→满帧
        int tolFrames;
        if (speed <= speedThresholdLow * speedThresholdLow) {
          tolFrames = 0;
        } else if (speed >= speedThresholdHigh * speedThresholdHigh) {
          tolFrames = _kReleaseConfirmFrames;
        } else {
          final t = (speed - speedThresholdLow * speedThresholdLow) /
              (speedThresholdHigh * speedThresholdHigh -
                  speedThresholdLow * speedThresholdLow);
          tolFrames = (t * _kReleaseConfirmFrames).round();
        }
        _releaseConfirmCount++;
        isPinching = _releaseConfirmCount < tolFrames;
        if (!isPinching) _releaseConfirmCount = 0;
      }
    } else {
      isPinching = pinchRatio < pinchStartThreshold;
      _releaseConfirmCount = 0;
    }

    if (isPinching && !_isCurrentlyDrawing) _drawingFrameCount = 0;
    _isCurrentlyDrawing = isPinching;

    // 只有食指伸出、其余握拳：用于空中点击
    final isIndexPointing = indexExtended && !middleExtended &&
        !ringExtended && !pinkyExtended && !isPinching;

    var pointX = (thumbTip.x + indexTip.x) / 2;
    var pointY = (thumbTip.y + indexTip.y) / 2;
    var indexX = indexTip.x;
    if (mirrorX) {
      pointX = 1.0 - pointX;
      indexX = 1.0 - indexX;
    }

    return GestureResult(
      type: isPinching ? GestureType.pinch : GestureType.openPalm,
      drawingPoint: Offset(pointX, pointY),
      isDrawing: isPinching,
      pinchRatio: pinchRatio,
      isTwoFingerPinch: isTwoFingerPinch,
      isFullyOpen: isFullyOpen,
      isIndexPointing: isIndexPointing,
      indexTip: Offset(indexX, indexTip.y),
    );
  }

  static double _dist(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    return math.sqrt(dx * dx + dy * dy);
  }
}
