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

// ─── 坐标变换 + 旋转检测 + 笔画旋转 ─────────────────────────────────
part of '../formula_editor_page.dart';

extension _RotationUtils on _FormulaEditorPageState {
  Offset _transformCoord(double nx, double ny) {
    // native 端按设备朝向更新了 buffer，landmark 已经在 display-aligned 坐标系里。
    // 直接乘屏幕尺寸即可，无需任何旋转 / 翻转。
    final lx = nx;
    final ly = ny;

    final size = _screenSize;
    // 用屏幕上实际看到的那幅画面的宽高比：横屏时纹理要补转 90 度，
    // 未旋转的 _previewW/_previewH 是躺着的，拿它算 BoxFit.cover 的裁切会反。
    final previewAspect = _shownPreviewW / _shownPreviewH;
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

  /// 方向检测：用 MediaPipe 手部 wrist→middle_mcp 向量的屏幕空间角度。
  /// 不依赖笔画统计，对单字符/短公式（如 "2/3"）依然鲁棒。
  ///
  /// 映射：手指朝上→0、朝左→1、朝下→2、朝右→3（对应需要的 90°CW 旋转次数）
  int _detectRotationCountFromHand() {
    final angle = _airHandAngle;
    if (angle == null) {
      print('[Orient] hand 不可用，rot=0');
      return 0;
    }
    // 屏幕坐标系 y 朝下：手指朝上 → angle ≈ -π/2
    // 取负方向：手指朝左→1，朝下→2，朝右→3
    var shifted = -(angle + math.pi / 2);
    while (shifted < 0) shifted += 2 * math.pi;
    while (shifted >= 2 * math.pi) shifted -= 2 * math.pi;
    final rot = ((shifted / (math.pi / 2)).round()) % 4;
    final dirNames = ['0°', '90°', '180°', '270°'];
    // ignore: avoid_print
    print(
      '[Orient] hand angle=${(angle * 180 / math.pi).toStringAsFixed(1)}° → ${dirNames[rot]}',
    );
    return rot;
  }

  List<Stroke> _rotateStrokes(
    List<Stroke> strokes,
    Size size, {
    required int rotCount,
  }) {
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
}
