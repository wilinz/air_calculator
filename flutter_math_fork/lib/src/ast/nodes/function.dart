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

import '../../render/layout/line.dart';
import '../options.dart';
import '../spacing.dart';
import '../syntax_tree.dart';

/// Function node
///
/// Examples: `\sin`, `\lim`, `\operatorname`
class FunctionNode extends SlotableNode<EquationRowNode> {
  /// Name of the function.
  final EquationRowNode functionName;

  /// Argument of the function.
  final EquationRowNode argument;

  FunctionNode({
    required this.functionName,
    required this.argument,
  });

  @override
  BuildResult buildWidget(
          MathOptions options, List<BuildResult?> childBuildResults) =>
      BuildResult(
        options: options,
        widget: Line(children: [
          LineElement(
            trailingMargin:
                getSpacingSize(AtomType.op, argument.leftType, options.style)
                    .toLpUnder(options),
            child: childBuildResults[0]!.widget,
          ),
          LineElement(
            trailingMargin: 0.0,
            child: childBuildResults[1]!.widget,
          ),
        ]),
      );

  @override
  List<MathOptions> computeChildOptions(MathOptions options) =>
      List.filled(2, options, growable: false);

  @override
  List<EquationRowNode> computeChildren() => [functionName, argument];

  @override
  AtomType get leftType => AtomType.op;

  @override
  AtomType get rightType => argument.rightType;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  FunctionNode updateChildren(List<EquationRowNode> newChildren) =>
      copyWith(functionName: newChildren[0], argument: newChildren[1]);

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'functionName': functionName.toJson(),
      'argument': argument.toJson(),
    });

  FunctionNode copyWith({
    EquationRowNode? functionName,
    EquationRowNode? argument,
  }) =>
      FunctionNode(
        functionName: functionName ?? this.functionName,
        argument: argument ?? this.argument,
      );
}
