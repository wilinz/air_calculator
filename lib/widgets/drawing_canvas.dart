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

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../models/gesture.dart';

/// 已完成笔画的 Picture 缓存，存在 State 中跨帧复用
class StrokePictureCache {
  ui.Picture? picture;
  int cachedVersion = -1;
  Size? cachedSize;
}

/// 绘图画布组件
class DrawingCanvas extends StatelessWidget {
  final CanvasState canvasState;
  final StrokePictureCache pictureCache;
  final Offset? currentPoint;
  final bool isDrawing;
  final double lineThickness;
  final Color lineColor;
  final Color drawingIndicatorColor;
  final Color stoppedIndicatorColor;

  const DrawingCanvas({
    super.key,
    required this.canvasState,
    required this.pictureCache,
    this.currentPoint,
    this.isDrawing = false,
    this.lineThickness = 8.0,
    this.lineColor = Colors.white,
    this.drawingIndicatorColor = Colors.green,
    this.stoppedIndicatorColor = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DrawingPainter(
        canvasState: canvasState,
        pictureCache: pictureCache,
        currentPoint: currentPoint,
        isDrawing: isDrawing,
        lineThickness: lineThickness,
        lineColor: lineColor,
        drawingIndicatorColor: drawingIndicatorColor,
        stoppedIndicatorColor: stoppedIndicatorColor,
      ),
      size: Size.infinite,
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final CanvasState canvasState;
  final StrokePictureCache pictureCache;
  final Offset? currentPoint;
  final bool isDrawing;
  final double lineThickness;
  final Color lineColor;
  final Color drawingIndicatorColor;
  final Color stoppedIndicatorColor;

  // 构造时对 mutable state 的字段做 snapshot；shouldRepaint 比较快照差异，
  // 否则两个 painter 引用同一个 canvasState 会读到相同的当前值，永远等于自己。
  final int _versionSnapshot;
  final int _currentStrokeLen;

  _DrawingPainter({
    required this.canvasState,
    required this.pictureCache,
    this.currentPoint,
    required this.isDrawing,
    required this.lineThickness,
    required this.lineColor,
    required this.drawingIndicatorColor,
    required this.stoppedIndicatorColor,
  }) : _versionSnapshot = canvasState.strokesVersion,
       _currentStrokeLen = canvasState.currentStroke?.points.length ?? 0;

  @override
  void paint(Canvas canvas, Size size) {
    // 已完成笔画：只在版本变化时重建 Picture 缓存
    if (canvasState.strokesVersion != pictureCache.cachedVersion ||
        pictureCache.cachedSize != size) {
      final recorder = ui.PictureRecorder();
      final offscreenCanvas = Canvas(recorder);
      for (final stroke in canvasState.strokes) {
        _drawStroke(offscreenCanvas, stroke);
      }
      pictureCache.picture = recorder.endRecording();
      pictureCache.cachedVersion = canvasState.strokesVersion;
      pictureCache.cachedSize = size;
    }

    if (pictureCache.picture != null) {
      canvas.drawPicture(pictureCache.picture!);
    }

    // 当前正在绘制的笔画（每帧追加新点，每帧重绘）
    if (canvasState.currentStroke != null) {
      _drawStroke(canvas, canvasState.currentStroke!);
    }

    // 位置指示器
    if (currentPoint != null) {
      _drawIndicator(canvas, currentPoint!);
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.length < 2) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  void _drawIndicator(Canvas canvas, Offset point) {
    final color = isDrawing ? drawingIndicatorColor : stoppedIndicatorColor;
    final radius = isDrawing ? lineThickness : lineThickness * 0.8;

    if (isDrawing) {
      canvas.drawCircle(
        point,
        radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    } else {
      canvas.drawCircle(
        point,
        radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) {
    return _versionSnapshot != oldDelegate._versionSnapshot ||
        _currentStrokeLen != oldDelegate._currentStrokeLen ||
        currentPoint != oldDelegate.currentPoint ||
        isDrawing != oldDelegate.isDrawing;
  }
}

/// 手部骨架绘制组件
class HandSkeletonPainter extends CustomPainter {
  final List<Offset>? landmarks;
  final bool visible;
  final Color skeletonColor;
  final Color landmarkColor;
  final bool useRawCoordinates;

  HandSkeletonPainter({
    this.landmarks,
    this.visible = true,
    this.skeletonColor = Colors.green,
    this.landmarkColor = Colors.red,
    this.useRawCoordinates = false,
  });

  static const List<List<int>> connections = [
    [0, 1],
    [1, 2],
    [2, 3],
    [3, 4],
    [0, 5],
    [5, 6],
    [6, 7],
    [7, 8],
    [0, 9],
    [9, 10],
    [10, 11],
    [11, 12],
    [0, 13],
    [13, 14],
    [14, 15],
    [15, 16],
    [0, 17],
    [17, 18],
    [18, 19],
    [19, 20],
    [5, 9],
    [9, 13],
    [13, 17],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible || landmarks == null || landmarks!.length < 21) return;

    final points = useRawCoordinates
        ? landmarks!
        : landmarks!
              .map((p) => Offset(p.dx * size.width, p.dy * size.height))
              .toList();

    final linePaint = Paint()
      ..color = skeletonColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (final conn in connections) {
      canvas.drawLine(points[conn[0]], points[conn[1]], linePaint);
    }

    final pointPaint = Paint()
      ..color = landmarkColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < points.length; i++) {
      final radius = [4, 8, 12, 16, 20].contains(i) ? 6.0 : 4.0;
      canvas.drawCircle(points[i], radius, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant HandSkeletonPainter old) {
    return landmarks != old.landmarks || visible != old.visible;
  }
}
