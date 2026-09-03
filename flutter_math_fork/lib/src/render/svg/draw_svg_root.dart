// Copyright the flutter_math authors (https://github.com/znjameswu/flutter_math)
// and the flutter_math_fork maintainers (https://github.com/simpleclub/flutter_math).
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

import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';

void drawSvgRoot(PictureInfo svgRoot, PaintingContext context, Offset offset) {
  final canvas = context.canvas;
  canvas.save();
  canvas.translate(offset.dx, offset.dy);
  canvas.scale(
    svgRoot.size.width,
    svgRoot.size.height,
  );
  canvas.clipRect(Rect.fromLTWH(
    0.0,
    0.0,
    svgRoot.size.width,
    svgRoot.size.height,
  ));
  canvas.drawPicture(svgRoot.picture);
  canvas.restore();
}
