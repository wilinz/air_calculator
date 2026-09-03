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

import 'package:flutter/material.dart';

import '../models/gesture.dart';

/// 触屏手写输入面板：用手指/笔在画布上写字，把笔画累加到 [canvasState]。
/// 调用方负责调用识别服务并清空画布。
class TouchHandwritingPad extends StatefulWidget {
  final CanvasState canvasState;

  /// 笔画粗细
  final double strokeWidth;

  /// 笔画颜色
  final Color strokeColor;

  /// 背景色（浅色主题用 #FAFBFC，深色主题用近黑）
  final Color background;

  /// 网格线颜色（淡背景格）
  final Color gridColor;

  /// 画布高度
  final double height;

  /// 笔画发生变化时回调（增删改任何）
  final VoidCallback? onChanged;

  const TouchHandwritingPad({
    super.key,
    required this.canvasState,
    this.strokeWidth = 3.0,
    this.strokeColor = const Color(0xFF1976D2),
    this.background = const Color(0xFFFAFBFC),
    this.gridColor = const Color(0xFFE3E5E8),
    this.height = 180,
    this.onChanged,
  });

  @override
  State<TouchHandwritingPad> createState() => _TouchHandwritingPadState();
}

class _TouchHandwritingPadState extends State<TouchHandwritingPad> {
  /// 空间死区：移动不足此像素不收点。
  static const double _deadZonePx = 2.5;

  /// 时间闸门：距上一个被采纳的点不足这么久就不收点。
  ///
  /// 只有空间死区是不够的——手指划得快时 2.5 px 可以在半毫秒内跨过，实测这台
  /// 设备的采样间隔中位只有 3.8 ms、P1 低到 0.10 ms（MIUI 会把历史点批量塞进
  /// 同一个事件），而训练数据是 8.0 ms / P1 2.0 ms。间隔一塌，speed = dist/dt
  /// 就炸到裁剪上限 20：实测 11.3% 的点落在 speed>10，训练分布里这个比例只有
  /// 0.98%，模型没见过这种输入。
  ///
  /// 拿抓到的 23 条真实手写「30」离线验证（PyTorch fp32，与平台无关）：
  ///   不节流  7/23 正确，speed>10 占 11.33%
  ///   6 ms   15/23
  ///   10 ms  18/23，speed>10 占 1.01%
  ///   16 ms  18/23
  /// 取 10 ms（约 100 Hz），最接近训练数据的 88 Hz，且不影响落笔手感。
  static const int _minIntervalUs = 10000;

  Offset? _lastAcceptedPt;
  int? _lastAcceptedUs;

  void _onPanStart(DragStartDetails d) {
    widget.canvasState.startStroke(
      thickness: widget.strokeWidth,
      color: widget.strokeColor,
    );
    widget.canvasState.addPoint(d.localPosition);
    _lastAcceptedPt = d.localPosition;
    _lastAcceptedUs = DateTime.now().microsecondsSinceEpoch;
    setState(() {});
    widget.onChanged?.call();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final p = d.localPosition;
    final now = DateTime.now().microsecondsSinceEpoch;
    final last = _lastAcceptedPt;
    final lastUs = _lastAcceptedUs;
    // 空间和时间两个条件都要满足才收点。
    if (last != null && (p - last).distance < _deadZonePx) return;
    if (lastUs != null && now - lastUs < _minIntervalUs) return;
    widget.canvasState.addPoint(p);
    _lastAcceptedPt = p;
    _lastAcceptedUs = now;
    setState(() {});
  }

  void _onPanEnd(DragEndDetails d) {
    // 与空中手写一致：结束前做一次平滑，让笔画特征更接近训练分布
    widget.canvasState.currentStroke?.smooth();
    widget.canvasState.endStroke();
    _lastAcceptedPt = null;
    _lastAcceptedUs = null;
    setState(() {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: CustomPaint(
          painter: _HandwritingPainter(
            state: widget.canvasState,
            background: widget.background,
            gridColor: widget.gridColor,
          ),
          child: Container(),
        ),
      ),
    );
  }
}

class _HandwritingPainter extends CustomPainter {
  final CanvasState state;
  final Color background;
  final Color gridColor;

  _HandwritingPainter({
    required this.state,
    required this.background,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = background,
    );
    // 中线
    final mid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      mid,
    );

    // 已完成笔画
    for (final stroke in state.strokes) {
      _drawStroke(canvas, stroke);
    }
    // 当前笔画
    final cur = state.currentStroke;
    if (cur != null) _drawStroke(canvas, cur);
  }

  void _drawStroke(Canvas canvas, Stroke s) {
    if (s.points.isEmpty) return;
    final paint = Paint()
      ..color = s.color
      ..strokeWidth = s.thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (s.points.length == 1) {
      canvas.drawCircle(
        s.points.first,
        s.thickness / 2,
        Paint()..color = s.color,
      );
      return;
    }
    final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
    for (int i = 1; i < s.points.length; i++) {
      path.lineTo(s.points[i].dx, s.points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HandwritingPainter old) =>
      old.state.strokesVersion != state.strokesVersion ||
      old.state.currentStroke != state.currentStroke;
}
