// ─── Blinking cursor bar (Symbolab-style) ────────────────────────────────────
part of '../formula_editor_page.dart';

class _BlinkingCursor extends StatefulWidget {
  final bool active;
  final Color color;
  final double width;
  final double height;
  const _BlinkingCursor({
    required this.active,
    required this.color,
    this.width = 2,
    this.height = 36,
  });

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(_BlinkingCursor old) {
    super.didUpdateWidget(old);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl
        ..value = 0
        ..repeat();
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return SizedBox(width: widget.width + 2, height: widget.height);
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final visible = _ctrl.value < 0.5;
        return Container(
          width: widget.width,
          height: widget.height,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: visible ? widget.color : Colors.transparent,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      },
    );
  }
}
