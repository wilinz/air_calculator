// Copyright the flutter_math authors (https://github.com/znjameswu/flutter_math)
// and the flutter_math_fork maintainers (https://github.com/simpleclub/flutter_math).
// Modifications copyright 2026 wilinz.
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

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

String svgStringFromPath(
  String path,
  Size viewPort,
  Rect viewBox,
  Color color, {
  String preserveAspectRatio = 'xMidYMid meet',
}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" '
    'width="${viewPort.width}" height="${viewPort.height}" '
    'preserveAspectRatio="$preserveAspectRatio" '
    'viewBox='
    '"${viewBox.left} ${viewBox.top} ${viewBox.width} ${viewBox.height}" '
    '>'
    '<path fill="rgb(${color.red},${color.green},${color.blue})" d="$path"></path>'
    '</svg>';

final _alignmentToString = {
  Alignment.topLeft: 'xMinYMin',
  Alignment.topCenter: 'xMidYMin',
  Alignment.topRight: 'xMaxYMin',
  Alignment.centerLeft: 'xMinYMid',
  Alignment.center: 'xMidYMid',
  Alignment.centerRight: 'xMaxYMid',
  Alignment.bottomLeft: 'xMinYMax',
  Alignment.bottomCenter: 'xMidYMax',
  Alignment.bottomRight: 'xMaxYMax',
};

Widget svgWidgetFromPath(
  String path,
  Size viewPort,
  Rect viewBox,
  Color color, {
  Alignment align = Alignment.topLeft,
  BoxFit fit = BoxFit.fill,
}) {
  final alignment = _alignmentToString[align];

  assert(fit != BoxFit.none &&
      fit != BoxFit.fitHeight &&
      fit != BoxFit.fitWidth &&
      fit != BoxFit.scaleDown);
  final meetOrSlice = fit == BoxFit.contain ? 'meet' : 'slice';

  final preserveAspectRatio =
      fit == BoxFit.fill ? 'none' : '$alignment $meetOrSlice';

  final svgString = svgStringFromPath(path, viewPort, viewBox, color,
      preserveAspectRatio: preserveAspectRatio);
  return SizedBox(
    height: viewPort.height,
    width: viewPort.width,
    child: SvgPicture.string(
      svgString,
      width: viewPort.width,
      height: viewPort.height,
      fit: fit,
      alignment: align,
    ),
  );
}
