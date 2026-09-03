import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 手势类型枚举
enum GestureType {
  /// 无手势
  none,

  /// 捏合手势（拇指和食指捏在一起）- 用于绘制
  pinch,

  /// 张开手掌
  openPalm,
}

/// 手势识别结果
class GestureResult {
  /// 识别的手势类型
  final GestureType type;

  /// 绘制位置（拇指和食指的中点）
  final Offset? drawingPoint;

  /// 是否正在绘制
  final bool isDrawing;

  /// 捏合比例（用于调试）
  final double pinchRatio;

  /// 食指与中指指尖是否并拢（用于触发滑动模式）
  final bool isTwoFingerPinch;

  /// 五指完全张开
  final bool isFullyOpen;

  /// 只有食指伸出、其余手指握拳（用于空中点击）
  final bool isIndexPointing;

  /// 食指指尖归一化坐标
  final Offset? indexTip;

  const GestureResult({
    required this.type,
    this.drawingPoint,
    this.isDrawing = false,
    this.pinchRatio = 0.0,
    this.isTwoFingerPinch = false,
    this.isFullyOpen = false,
    this.isIndexPointing = false,
    this.indexTip,
  });

  /// 默认空结果
  static const GestureResult none = GestureResult(
    type: GestureType.none,
    isDrawing: false,
  );
}

/// 笔画数据
class Stroke {
  /// 笔画中的所有点
  final List<Offset> points;

  /// 每个点对应的时间戳（微秒）
  final List<int> timestamps;

  /// 每个点对应的捏合比例（0=完全捏合，1=张开）
  final List<double> pinchRatios;

  /// 线条粗细
  final double thickness;

  /// 线条颜色
  final Color color;

  Stroke({
    List<Offset>? points,
    List<int>? timestamps,
    List<double>? pinchRatios,
    this.thickness = 8.0,
    this.color = const Color(0xFFFFFFFF),
  }) : points = points ?? [],
       timestamps = timestamps ?? [],
       pinchRatios = pinchRatios ?? [];

  /// 添加点（自动记录时间戳）
  void addPoint(Offset point, {double pinchRatio = 0.0}) {
    points.add(point);
    timestamps.add(DateTime.now().microsecondsSinceEpoch);
    pinchRatios.add(pinchRatio);
  }

  double _tailSpeedPxPerSec({double windowMs = 200.0}) {
    final n = points.length;
    if (n < 2) return 0.0;
    final endTs = timestamps.last;
    final cutoff = endTs - (windowMs * 1000).round();
    int start = n - 1;
    while (start > 0 && timestamps[start - 1] >= cutoff) {
      start--;
    }
    final pts = points.sublist(start);
    final tss = timestamps.sublist(start);
    if (pts.length < 2) return 0.0;
    double totalDist = 0.0;
    for (int i = 1; i < pts.length; i++) {
      totalDist += (pts[i] - pts[i - 1]).distance;
    }
    final totalTimeSec = (tss.last - tss.first) / 1e6;
    if (totalTimeSec <= 0) return 0.0;
    return totalDist / totalTimeSec;
  }

  /// 从末尾删除捏合释放期间的拖尾点，默认关闭（[enabled]=false）。
  ///
  /// **方法1 — 捏合梯度（优先）**：
  /// 从末尾向前扫描，[pinchRatios] 连续上升（超过 [pinchNoise] 容差）的点
  /// 判定为拖尾；遇到 ratio 不再上升时停止。
  /// ratio 开始升高的那一刻 = 手指开始松开 = 书写意图结束。
  ///
  /// **方法2 — 时间戳+速度自适应（备用）**：
  /// 快写 → 短截断；慢写 → 长截断。
  ///
  /// 两种方法均至少保留 3 个点防止笔画变空。
  void trimTail({
    bool enabled = false,
    double releaseDelta = 0.10,         // 尾点 ratio 高出本地基线此值即视为释放
    int maxTrimAbs = 6,                 // 最多裁掉的绝对帧数（约 200ms）
    int maxTrimRatio = 4,               // 同时不能超过 1/N 长度
    double minCutoffMs = 60.0,
    double maxCutoffMs = 200.0,
    double speedSlow = 200.0,
    double speedFast = 1000.0,
  }) {
    if (!enabled) return;

    // ── 方法1：本地基线 + 末尾连续高位 ─────────────────
    // 思路：用候选裁剪区紧前面那一小段（5 帧）的中位数当"本地基线"，
    // 而不是全笔画中位数（避免被早期值绑架）。
    // 末尾凡是 ratio > baseline + releaseDelta 的连续点视为释放拉丝。
    // 严格限制：最多裁 maxTrimAbs 帧（~200ms），且不超过 1/maxTrimRatio。
    if (pinchRatios.length >= 8) {
      final n = pinchRatios.length;
      final maxCut = math.min(maxTrimAbs, math.max(2, n ~/ maxTrimRatio));
      // 本地基线：候选区前 5 帧的中位数
      final baseStart = math.max(0, n - maxCut - 5);
      final baseEnd = n - maxCut;
      final basePart = pinchRatios.sublist(baseStart, baseEnd);
      final sorted = List<double>.from(basePart)..sort();
      final baseline = sorted[sorted.length ~/ 2];
      final cutThreshold = baseline + releaseDelta;
      // 从末尾向前扫描：连续 ratio > cutThreshold 的点全裁
      int keep = n;
      while (keep > n - maxCut && keep > 3) {
        if (pinchRatios[keep - 1] > cutThreshold) {
          keep--;
        } else {
          break;
        }
      }
      if (keep < points.length) {
        points.removeRange(keep, points.length);
        timestamps.removeRange(keep, timestamps.length);
        pinchRatios.removeRange(keep, pinchRatios.length);
      }
      return;
    }

    // ── 方法2：时间戳+速度自适应（备用） ─────────────────────────
    if (timestamps.length < 4) return;
    final speed = _tailSpeedPxPerSec();
    final t = ((speed - speedSlow) / (speedFast - speedSlow)).clamp(0.0, 1.0);
    final cutoffMs = maxCutoffMs - t * (maxCutoffMs - minCutoffMs);
    final endTs = timestamps.last;
    final cutoff = endTs - (cutoffMs * 1000).round();
    int keep = timestamps.length;
    while (keep > 3 && timestamps[keep - 1] >= cutoff) {
      keep--;
    }
    if (keep < points.length) {
      points.removeRange(keep, points.length);
      timestamps.removeRange(keep, timestamps.length);
      pinchRatios.removeRange(keep, pinchRatios.length);
    }
  }

  /// 笔画平滑：滑动窗口均值，消除高频抖动（不影响整体形状）
  /// [passes] 连续平滑次数，默认 2 次
  void smooth({int windowSize = 3, int passes = 2}) {
    if (points.length < 3) return;
    final half = windowSize ~/ 2;
    for (int p = 0; p < passes; p++) {
      final smoothed = List<Offset>.generate(points.length, (i) {
        double dx = 0, dy = 0;
        int count = 0;
        for (int j = i - half; j <= i + half; j++) {
          if (j >= 0 && j < points.length) {
            dx += points[j].dx;
            dy += points[j].dy;
            count++;
          }
        }
        return Offset(dx / count, dy / count);
      });
      points
        ..clear()
        ..addAll(smoothed);
    }
  }

  /// 等弧长重采样：沿原折线按固定 [spacing] 像素插值，生成均匀分布的点列。
  ///
  /// 解决两个问题：
  /// 1) 快写采样稀疏 → 折线化，模型看到的形状失真
  /// 2) 慢写采样过密 → 模型输入过长，且抖动放大
  ///
  /// 重采样后 timestamps/pinchRatios 同步线性插值，方便后续仍能调用 trimTail。
  void resample({double spacing = 6.0}) {
    if (points.length < 2) return;
    // 累计弧长
    final cum = <double>[0.0];
    for (int i = 1; i < points.length; i++) {
      cum.add(cum.last + (points[i] - points[i - 1]).distance);
    }
    final totalLen = cum.last;
    if (totalLen < spacing) return; // 太短不重采样

    final n = (totalLen / spacing).floor() + 1;
    final newPoints = <Offset>[];
    final newTs = <int>[];
    final newRatios = <double>[];

    int seg = 0;
    for (int k = 0; k < n; k++) {
      final target = k * spacing;
      while (seg + 1 < cum.length && cum[seg + 1] < target) {
        seg++;
      }
      if (seg + 1 >= cum.length) {
        // 走到末尾，直接取最后一点
        newPoints.add(points.last);
        newTs.add(timestamps.last);
        newRatios.add(pinchRatios.isNotEmpty ? pinchRatios.last : 0.0);
        continue;
      }
      final segLen = cum[seg + 1] - cum[seg];
      final t = segLen <= 0 ? 0.0 : (target - cum[seg]) / segLen;
      newPoints.add(Offset.lerp(points[seg], points[seg + 1], t)!);
      // 时间戳线性插值
      final ts0 = timestamps[seg];
      final ts1 = timestamps[seg + 1];
      newTs.add((ts0 + (ts1 - ts0) * t).round());
      // pinchRatio 线性插值
      if (pinchRatios.length > seg + 1) {
        final r0 = pinchRatios[seg];
        final r1 = pinchRatios[seg + 1];
        newRatios.add(r0 + (r1 - r0) * t);
      } else {
        newRatios.add(0.0);
      }
    }
    // 末点保留（确保收笔形状不丢）
    if (newPoints.last != points.last) {
      newPoints.add(points.last);
      newTs.add(timestamps.last);
      newRatios.add(pinchRatios.isNotEmpty ? pinchRatios.last : 0.0);
    }

    points
      ..clear()
      ..addAll(newPoints);
    timestamps
      ..clear()
      ..addAll(newTs);
    pinchRatios
      ..clear()
      ..addAll(newRatios);
  }

  /// 是否为空笔画
  bool get isEmpty => points.isEmpty;

  /// 笔画点数
  int get length => points.length;

  /// 复制笔画
  Stroke copy() {
    return Stroke(
      points: List.from(points),
      timestamps: List.from(timestamps),
      pinchRatios: List.from(pinchRatios),
      thickness: thickness,
      color: color,
    );
  }
}

/// 画布状态
class CanvasState {
  /// 所有已完成的笔画
  final List<Stroke> strokes;

  /// 当前正在绘制的笔画
  Stroke? currentStroke;

  /// 已完成笔画的版本号，每次笔画列表发生变化时递增
  /// 供 CustomPainter 决定是否重建图片缓存
  int strokesVersion = 0;

  CanvasState({List<Stroke>? strokes, this.currentStroke})
    : strokes = strokes ?? [];

  /// 开始新笔画
  /// 注意：不递增 strokesVersion——`strokes` 列表未变，picture 缓存无需重建。
  void startStroke({double thickness = 8.0, Color? color}) {
    currentStroke = Stroke(thickness: thickness, color: color ?? Colors.blue);
  }

  /// 添加点到当前笔画
  void addPoint(Offset point, {double pinchRatio = 0.0}) {
    currentStroke?.addPoint(point, pinchRatio: pinchRatio);
  }

  /// 结束当前笔画
  void endStroke() {
    if (currentStroke != null && currentStroke!.length > 1) {
      strokes.add(currentStroke!.copy());
      _redoStack.clear(); // 新笔画使 redo 历史失效
    }
    currentStroke = null;
    strokesVersion++;
  }

  final List<Stroke> _redoStack = [];

  bool get canRedo => _redoStack.isNotEmpty;

  /// 撤销最后一个笔画
  /// [minPoints] 跳过点数少于此值的短笔画（误触）
  bool undoLastStroke({int minPoints = 10}) {
    if (strokes.isEmpty) return false;

    while (strokes.isNotEmpty && strokes.last.length < minPoints) {
      strokes.removeLast();
    }

    if (strokes.isNotEmpty) {
      _redoStack.add(strokes.removeLast());
      strokesVersion++;
      return true;
    }
    return false;
  }

  /// 按索引删除笔画（剪刀模式用），删除的笔画进 redo 栈
  bool removeStrokeAt(int index) {
    if (index < 0 || index >= strokes.length) return false;
    _redoStack.add(strokes.removeAt(index));
    strokesVersion++;
    return true;
  }

  /// 重做上一次撤销的笔画
  bool redoLastStroke() {
    if (_redoStack.isEmpty) return false;
    strokes.add(_redoStack.removeLast());
    strokesVersion++;
    return true;
  }

  /// 清空画布
  void clear() {
    strokes.clear();
    _redoStack.clear();
    currentStroke = null;
    strokesVersion++;
  }

  /// 笔画数量
  int get strokeCount => strokes.length;
}
