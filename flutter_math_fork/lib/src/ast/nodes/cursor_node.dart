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

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../ast.dart';
import '../../render/layout/line.dart';
import '../syntax_tree.dart';

/// Node displays vertical bar the size of [MathOptions.fontSize]
/// to replicate a text edit field cursor
class CursorNode extends LeafNode {
  @override
  BuildResult buildWidget(
      MathOptions options, List<BuildResult?> childBuildResults) {
    final baselinePart = 1 - options.fontMetrics.axisHeight / 2;
    final height = options.fontSize * baselinePart * options.sizeMultiplier;
    final baselineDistance = height * baselinePart;
    final cursor = Container(height: height, width: 1.5, color: options.color);
    return BuildResult(
        options: options,
        widget: _BaselineDistance(
          baselineDistance: baselineDistance,
          child: cursor,
        ));
  }

  @override
  AtomType get leftType => AtomType.ord;

  @override
  Mode get mode => Mode.text;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;
}

/// This render object overrides the return value of
/// [RenderProxyBox.computeDistanceToActualBaseline]
///
/// Used to align [CursorNode] properly in a [RenderLine] in respect to symbols
class _BaselineDistance extends SingleChildRenderObjectWidget {
  const _BaselineDistance({
    required this.baselineDistance,
    super.child,
  });

  final double baselineDistance;

  @override
  _BaselineDistanceBox createRenderObject(BuildContext context) =>
      _BaselineDistanceBox(baselineDistance);
}

class _BaselineDistanceBox extends RenderProxyBox {
  _BaselineDistanceBox(this.baselineDistance);

  final double baselineDistance;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      baselineDistance;
}
