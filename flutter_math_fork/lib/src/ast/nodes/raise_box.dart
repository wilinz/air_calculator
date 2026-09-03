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

import '../../render/layout/shift_baseline.dart';
import '../options.dart';
import '../size.dart';
import '../syntax_tree.dart';

/// Raise box node which vertically displace its child.
///
/// Example: `\raisebox`
class RaiseBoxNode extends SlotableNode<EquationRowNode> {
  /// Child to raise.
  final EquationRowNode body;

  /// Vertical displacement.
  final Measurement dy;

  RaiseBoxNode({
    required this.body,
    required this.dy,
  });

  @override
  BuildResult buildWidget(
          MathOptions options, List<BuildResult?> childBuildResults) =>
      BuildResult(
        options: options,
        widget: ShiftBaseline(
          offset: dy.toLpUnder(options),
          child: childBuildResults[0]!.widget,
        ),
      );

  @override
  List<MathOptions> computeChildOptions(MathOptions options) => [options];

  @override
  List<EquationRowNode> computeChildren() => [body];

  @override
  AtomType get leftType => AtomType.ord;

  @override
  AtomType get rightType => AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  RaiseBoxNode updateChildren(List<EquationRowNode> newChildren) =>
      copyWith(body: newChildren[0]);

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'body': body.toJson(),
      'dy': dy.toString(),
    });

  RaiseBoxNode copyWith({
    EquationRowNode? body,
    Measurement? dy,
  }) =>
      RaiseBoxNode(
        body: body ?? this.body,
        dy: dy ?? this.dy,
      );
}
