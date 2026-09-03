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

import 'package:flutter/widgets.dart';

import '../../render/layout/layout_builder_baseline.dart';
import '../../render/layout/shift_baseline.dart';
import '../../render/layout/vlist.dart';
import '../../render/svg/stretchy.dart';
import '../../utils/unicode_literal.dart';
import '../options.dart';
import '../size.dart';
import '../style.dart';
import '../syntax_tree.dart';

/// Stretchy operator node.
///
/// Example: `\xleftarrow`
class StretchyOpNode extends SlotableNode<EquationRowNode?> {
  /// Unicode symbol for the operator.
  final String symbol;

  /// Arguments above the operator.
  final EquationRowNode? above;

  /// Arguments below the operator.
  final EquationRowNode? below;

  StretchyOpNode({
    required this.above,
    required this.below,
    required this.symbol,
  }) : assert(above != null || below != null);

  @override
  BuildResult buildWidget(
      MathOptions options, List<BuildResult?> childBuildResults) {
    final verticalPadding = 2.0.mu.toLpUnder(options);
    return BuildResult(
      options: options,
      italic: 0.0,
      widget: VList(
        baselineReferenceWidgetIndex: above != null ? 1 : 0,
        children: <Widget>[
          if (above != null)
            Padding(
              padding: EdgeInsets.only(bottom: verticalPadding),
              child: childBuildResults[0]!.widget,
            ),
          VListElement(
            // From katex.less/x-arrow-pad
            customCrossSize: (width) =>
                BoxConstraints(minWidth: width + 1.0.cssEm.toLpUnder(options)),
            child: LayoutBuilderPreserveBaseline(
              builder: (context, constraints) => ShiftBaseline(
                relativePos: 0.5,
                offset: options.fontMetrics.xHeight.cssEm.toLpUnder(options),
                child: strechySvgSpan(
                  stretchyOpMapping[symbol] ?? symbol,
                  constraints.minWidth,
                  options,
                ),
              ),
            ),
          ),
          if (below != null)
            Padding(
              padding: EdgeInsets.only(top: verticalPadding),
              child: childBuildResults[1]!.widget,
            )
        ],
      ),
    );
  }

  @override
  List<MathOptions> computeChildOptions(MathOptions options) => [
        options.havingStyle(options.style.sup()),
        options.havingStyle(options.style.sub()),
      ];

  @override
  List<EquationRowNode?> computeChildren() => [above, below];

  @override
  AtomType get leftType => AtomType.rel;

  @override
  AtomType get rightType => AtomType.rel;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      oldOptions.sizeMultiplier != newOptions.sizeMultiplier;

  @override
  StretchyOpNode updateChildren(List<EquationRowNode> newChildren) =>
      StretchyOpNode(
        above: newChildren[0],
        below: newChildren[1],
        symbol: symbol,
      );

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'symbol': unicodeLiteral(symbol),
      if (above != null) 'above': above!.toJson(),
      if (below != null) 'below': below!.toJson(),
    });
}

const stretchyOpMapping = {
  '\u2190': 'xleftarrow',
  '\u2192': 'xrightarrow',
  '\u2194': 'xleftrightarrow',

  '\u21d0': 'xLeftarrow',
  '\u21d2': 'xRightarrow',
  '\u21d4': 'xLeftrightarrow',

  '\u21a9': 'xhookleftarrow',
  '\u21aa': 'xhookrightarrow',

  '\u21a6': 'xmapsto',

  '\u21c1': 'xrightharpoondown',
  '\u21c0': 'xrightharpoonup',
  '\u21bd': 'xleftharpoondown',
  '\u21bc': 'xleftharpoonup',
  '\u21cc': 'xrightleftharpoons',
  '\u21cb': 'xleftrightharpoons',

  '=': 'xlongequal',

  '\u219e': 'xtwoheadleftarrow',
  '\u21a0': 'xtwoheadrightarrow',

  // '\u21c4': '\\xtofrom',
  '\u21c4': 'xrightleftarrows',
  // '\\xrightequilibrium': '\u21cc', // Not a perfect match.
  // '\\xleftequilibrium': '\u21cb', // None better available.
};
