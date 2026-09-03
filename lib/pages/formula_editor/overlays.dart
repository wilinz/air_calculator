// ─── 剪刀模式 overlay + 滑动手势 indicator overlay ──────────────────────────
part of '../formula_editor_page.dart';

class _ScissorOverlayState {
  const _ScissorOverlayState({
    required this.tip,
    this.targetPoints,
    this.progress = 0.0,
  });
  final Offset tip;
  final List<Offset>? targetPoints;
  final double progress;
}

class _ScissorPainter extends CustomPainter {
  const _ScissorPainter({required this.state});
  final _ScissorOverlayState state;

  @override
  void paint(Canvas canvas, Size size) {
    final tip = state.tip;

    // 高亮目标笔画
    if (state.targetPoints != null && state.targetPoints!.length >= 2) {
      final path = Path();
      path.moveTo(state.targetPoints!.first.dx, state.targetPoints!.first.dy);
      for (final p in state.targetPoints!.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.orangeAccent.withValues(alpha: 0.85)
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );

      // 进度弧（围绕食指尖）
      if (state.progress > 0) {
        canvas.drawArc(
          Rect.fromCircle(center: tip, radius: 22),
          -math.pi / 2,
          2 * math.pi * state.progress,
          false,
          Paint()
            ..color = Colors.orangeAccent
            ..strokeWidth = 3.5
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // 剪刀图标（自绘，原先用 ✂ emoji，会落到系统 emoji 字体）
    AppIconPainter.paintOn(
      canvas,
      AppIconData.scissors,
      center: tip,
      size: 26,
      color: Colors.white,
      strokeWidth: 2.2,
    );
  }

  @override
  bool shouldRepaint(_ScissorPainter old) =>
      old.state.tip != state.tip ||
      old.state.progress != state.progress ||
      old.state.targetPoints != state.targetPoints;
}

// ─── Swipe indicator overlay ──────────────────────────────────────────────────

class _SwipeIndicatorState {
  final Offset tip;
  final bool activated;
  final double progress;
  const _SwipeIndicatorState({
    required this.tip,
    required this.activated,
    this.progress = 0.0,
  });
}

class _SwipeIndicatorPainter extends CustomPainter {
  final _SwipeIndicatorState state;
  _SwipeIndicatorPainter({required this.state});

  @override
  void paint(Canvas canvas, Size size) {
    final tip = state.tip;
    const color = Color(0xFF29B6F6); // 蓝色
    const r = 22.0;

    if (state.activated) {
      // 激活态：实心圆 + 左右箭头
      canvas.drawCircle(tip, r, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(
        tip,
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      AppIconPainter.paintOn(
        canvas,
        AppIconData.swapHorizontal,
        center: tip,
        size: 24,
        color: color,
        strokeWidth: 2.2,
      );
    } else {
      // 蓄力中：进度弧
      canvas.drawCircle(
        tip,
        r,
        Paint()
          ..color = color.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawArc(
        Rect.fromCircle(center: tip, radius: r),
        -math.pi / 2,
        2 * math.pi * state.progress,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      AppIconPainter.paintOn(
        canvas,
        AppIconData.menuLines,
        center: tip,
        size: 18,
        color: color.withValues(alpha: 0.8),
        strokeWidth: 2.2,
      );
    }
  }

  @override
  bool shouldRepaint(_SwipeIndicatorPainter old) =>
      old.state.tip != state.tip ||
      old.state.activated != state.activated ||
      old.state.progress != state.progress;
}
