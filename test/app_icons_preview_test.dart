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

// 把 AppIcons 里的每个图标离屏渲染成一张对照图，人工核对造型。
// 产物写到 build/app_icons_preview.png，不参与 CI 断言。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:air_calculator/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('渲染图标总览图', () async {
    const cell = 96.0;
    const scale = 3.0; // 放大画，便于看清描边
    final icons = AppIconData.values;
    final w = cell * icons.length;
    const h = cell;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFFFFFFFF),
    );

    for (var i = 0; i < icons.length; i++) {
      AppIconPainter.paintOn(
        canvas,
        icons[i],
        center: Offset(cell * i + cell / 2, cell / 2),
        size: 64,
        color: const Color(0xFF1A1A1A),
      );
    }

    final img = await recorder.endRecording().toImage(
      (w * scale).round(),
      (h * scale).round(),
    );
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/app_icons_preview.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('图标顺序: ${icons.map((e) => e.name).join(", ")}');
  });
}
