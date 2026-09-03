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

// ─── 自绘矢量图标集 ────────────────────────────────────────────────────────────
//
// 起因：原先手势状态、键盘光标键、相机 overlay 上的图形直接写成 emoji 字符
// （🖐 ✍️ 🎙 ✂ ↔ ☰ ◀ ▶）。这些码位在 Android 上落到系统 emoji 字体，被渲染成彩色
// 位图字形，和周围的线性图标完全不是一套视觉语言，且不同机型/系统版本长相不一致。
//
// 这里用 CustomPainter 把它们全部重画一遍：统一 24×24 网格、统一描边宽度（按尺寸
// 等比缩放）、圆头圆角，颜色随调用方传入。canvas 层（overlay）和 widget 层（键盘、
// 状态栏）共用同一份绘制代码，见 [AppIconPainter.paintOn] 与 [AppIcon]。
//
// 轮廓较复杂的手掌用 Path.combine 做并集后再描边：并集的外轮廓就是手的外形，
// 不会在掌内留下手指与掌面相交的多余线条。

import 'dart:math' as math;
import 'dart:ui' show PathOperation;

import 'package:flutter/widgets.dart';

/// 图标种类。命名对应它替换掉的那个 emoji 语义。
enum AppIconData {
  /// ✍️ 绘制中
  pen,

  /// 🖐 停止（手掌）
  handStop,

  /// 🎙 录音中
  mic,

  /// ✂ 剪刀（擦除手势光标）
  scissors,

  /// ↔ 左右滑动已激活
  swapHorizontal,

  /// ☰ 蓄力中
  menuLines,

  /// ✓ 完成
  check,

  /// ◀ 光标左移
  caretLeft,

  /// ▶ 光标右移
  caretRight,
}

/// 24×24 网格上的图标绘制。所有几何量都写成 24 网格下的常数，
/// 由 [paintOn] 统一缩放到目标尺寸。
class AppIconPainter {
  const AppIconPainter._();

  /// 设计网格边长。
  static const double grid = 24.0;

  /// 24 网格下的默认描边宽度。缩放到 size=20 时约 1.6px，和正文字重接近。
  static const double _defaultStroke = 1.9;

  /// 以 [center] 为中心、边长 [size] 绘制 [icon]。
  ///
  /// [strokeWidth] 按 24 网格给定，缺省 [_defaultStroke]；实际落到画布上的
  /// 宽度会随 size/24 一起缩放，保证不同尺寸下观感一致。
  static void paintOn(
    Canvas canvas,
    AppIconData icon, {
    required Offset center,
    required double size,
    required Color color,
    double? strokeWidth,
  }) {
    final k = size / grid;
    canvas.save();
    canvas.translate(center.dx - size / 2, center.dy - size / 2);
    canvas.scale(k);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth ?? _defaultStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    switch (icon) {
      case AppIconData.pen:
        _pen(canvas, stroke, fill);
      case AppIconData.handStop:
        _handStop(canvas, stroke);
      case AppIconData.mic:
        _mic(canvas, stroke);
      case AppIconData.scissors:
        _scissors(canvas, stroke);
      case AppIconData.swapHorizontal:
        _swapHorizontal(canvas, stroke);
      case AppIconData.menuLines:
        _menuLines(canvas, stroke);
      case AppIconData.check:
        _check(canvas, stroke);
      case AppIconData.caretLeft:
        _caret(canvas, stroke, fill, pointLeft: true);
      case AppIconData.caretRight:
        _caret(canvas, stroke, fill, pointLeft: false);
    }

    canvas.restore();
  }

  // ── 单个图标 ───────────────────────────────────────────────────────────────

  /// 斜置的笔：笔杆两条平行边 + 顶端封口 + 实心笔尖。
  static void _pen(Canvas canvas, Paint stroke, Paint fill) {
    final body = Path()
      ..moveTo(7.4, 14.0)
      ..lineTo(16.9, 4.5)
      ..lineTo(20.0, 7.6)
      ..lineTo(10.5, 17.1);
    canvas.drawPath(body, stroke);

    // 笔尖：笔杆末端收成一个小三角，指向左下
    final nib = Path()
      ..moveTo(7.4, 14.0)
      ..lineTo(10.5, 17.1)
      ..lineTo(4.6, 19.9)
      ..close();
    canvas.drawPath(nib, fill);
    canvas.drawPath(nib, stroke);
  }

  /// 张开的手掌。四指 + 拇指 + 掌面先取并集，再描外轮廓，
  /// 这样掌内不会留下手指根部的横线。
  static void _handStop(Canvas canvas, Paint stroke) {
    // 掌面
    var hand = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(6.4, 10.0, 11.6, 11.0),
          const Radius.circular(5.2),
        ),
      );

    // 四指：竖直胶囊，指尖高度略作错落（中指最长）
    const fingers = <({double cx, double top})>[
      (cx: 8.6, top: 6.2),
      (cx: 11.5, top: 4.4),
      (cx: 14.4, top: 5.4),
      (cx: 17.0, top: 8.0),
    ];
    for (final f in fingers) {
      hand = Path.combine(
        PathOperation.union,
        hand,
        Path()..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(f.cx - 1.35, f.top, f.cx + 1.35, 16.0),
            const Radius.circular(1.35),
          ),
        ),
      );
    }

    // 拇指：向左下斜出的胶囊，绕自身中心旋转
    const thumbCenter = Offset(6.0, 14.6);
    final thumb = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: thumbCenter, width: 2.7, height: 8.2),
          const Radius.circular(1.35),
        ),
      );
    hand = Path.combine(
      PathOperation.union,
      hand,
      thumb.transform(
        (Matrix4.identity()
              ..translate(thumbCenter.dx, thumbCenter.dy)
              ..rotateZ(-0.62)
              ..translate(-thumbCenter.dx, -thumbCenter.dy))
            .storage,
      ),
    );

    canvas.drawPath(hand, stroke);
  }

  /// 话筒：拾音头胶囊 + 下方半圆护罩 + 支架。
  static void _mic(Canvas canvas, Paint stroke) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(9.0, 2.8, 15.0, 14.2),
        const Radius.circular(3.0),
      ),
      stroke,
    );
    canvas.drawArc(
      const Rect.fromLTRB(5.6, 5.4, 18.4, 18.2),
      0,
      math.pi,
      false,
      stroke,
    );
    canvas.drawLine(const Offset(12, 18.2), const Offset(12, 21.2), stroke);
  }

  /// 剪刀：两片交叉刀刃 + 两个指环。
  static void _scissors(Canvas canvas, Paint stroke) {
    canvas.drawLine(const Offset(6.2, 3.6), const Offset(16.6, 16.4), stroke);
    canvas.drawLine(const Offset(17.8, 3.6), const Offset(7.4, 16.4), stroke);
    canvas.drawCircle(const Offset(5.9, 18.6), 2.6, stroke);
    canvas.drawCircle(const Offset(18.1, 18.6), 2.6, stroke);
  }

  /// 左右双向箭头。
  static void _swapHorizontal(Canvas canvas, Paint stroke) {
    canvas.drawLine(const Offset(4.4, 12), const Offset(19.6, 12), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(8.0, 8.4)
        ..lineTo(4.4, 12)
        ..lineTo(8.0, 15.6),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(16.0, 8.4)
        ..lineTo(19.6, 12)
        ..lineTo(16.0, 15.6),
      stroke,
    );
  }

  /// 三条横线。
  static void _menuLines(Canvas canvas, Paint stroke) {
    for (final y in const [7.2, 12.0, 16.8]) {
      canvas.drawLine(Offset(4.6, y), Offset(19.4, y), stroke);
    }
  }

  /// 对勾。
  static void _check(Canvas canvas, Paint stroke) {
    canvas.drawPath(
      Path()
        ..moveTo(4.8, 12.6)
        ..lineTo(9.6, 17.4)
        ..lineTo(19.2, 6.6),
      stroke,
    );
  }

  /// 光标移动键上的实心三角。描边用同色圆角，让尖端不至于太锐。
  static void _caret(
    Canvas canvas,
    Paint stroke,
    Paint fill, {
    required bool pointLeft,
  }) {
    final path = pointLeft
        ? (Path()
            ..moveTo(15.4, 5.4)
            ..lineTo(7.6, 12.0)
            ..lineTo(15.4, 18.6)
            ..close())
        : (Path()
            ..moveTo(8.6, 5.4)
            ..lineTo(16.4, 12.0)
            ..lineTo(8.6, 18.6)
            ..close());
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke..strokeWidth = 2.4);
  }
}

/// [AppIconPainter] 的 widget 包装，用法与 `Icon` 一致。
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size = 20,
    required this.color,
    this.strokeWidth,
  });

  final AppIconData icon;
  final double size;
  final Color color;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _AppIconWidgetPainter(icon, color, strokeWidth),
      isComplex: false,
    ),
  );
}

class _AppIconWidgetPainter extends CustomPainter {
  const _AppIconWidgetPainter(this.icon, this.color, this.strokeWidth);
  final AppIconData icon;
  final Color color;
  final double? strokeWidth;

  @override
  void paint(Canvas canvas, Size size) => AppIconPainter.paintOn(
    canvas,
    icon,
    center: size.center(Offset.zero),
    size: math.min(size.width, size.height),
    color: color,
    strokeWidth: strokeWidth,
  );

  @override
  bool shouldRepaint(_AppIconWidgetPainter old) =>
      old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}

// ─── 文案内嵌图标 ─────────────────────────────────────────────────────────────
//
// 状态文案在 controller / page 里是纯 String（`String Function()`、`RxString`），
// 沿途拼接、比较。为了不把这些类型改成 Widget，改用私有区哨兵字符：
// 翻译表里写 `${AppGlyph.handStop} 停止`，渲染时由 [AppGlyphText] 把哨兵换成
// 对应的自绘图标。哨兵取 Unicode 私有使用区，不会和任何真实文字冲突。

class AppGlyph {
  const AppGlyph._();

  static const String pen = '\uE000';
  static const String handStop = '\uE001';
  static const String mic = '\uE002';
  static const String check = '\uE003';

  static const Map<String, AppIconData> _map = {
    pen: AppIconData.pen,
    handStop: AppIconData.handStop,
    mic: AppIconData.mic,
    check: AppIconData.check,
  };

  static AppIconData? lookup(String ch) => _map[ch];
}

/// 渲染可能含 [AppGlyph] 哨兵的文案：哨兵位置画自绘图标，其余按普通文本走。
///
/// 图标尺寸跟随字号（约 1.05×），颜色跟随文字颜色，因此状态栏换配色时无需改动。
class AppGlyphText extends StatelessWidget {
  const AppGlyphText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final fontSize = base.fontSize ?? 14;
    final color = base.color ?? const Color(0xFF000000);
    final iconSize = fontSize * 1.05;

    final spans = <InlineSpan>[];
    final buf = StringBuffer();
    void flush() {
      if (buf.isEmpty) return;
      spans.add(TextSpan(text: buf.toString()));
      buf.clear();
    }

    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final icon = AppGlyph.lookup(ch);
      if (icon == null) {
        buf.write(ch);
        continue;
      }
      flush();
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            // 图标右侧留一点气口，视觉上和后面的中文拉开距离
            padding: EdgeInsets.only(right: fontSize * 0.12),
            child: AppIcon(icon, size: iconSize, color: color),
          ),
        ),
      );
    }
    flush();

    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}
