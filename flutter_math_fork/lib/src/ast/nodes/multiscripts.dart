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

import '../../render/layout/multiscripts.dart';
import '../options.dart';
import '../style.dart';
import '../syntax_tree.dart';
import 'symbol.dart';

/// Node for postscripts and prescripts
///
/// Examples:
///
/// - Word:   _     ^
/// - Latex:  _     ^
/// - MathML: msub  msup  mmultiscripts
class MultiscriptsNode extends SlotableNode<EquationRowNode?> {
  /// Whether to align the subscript to the superscript.
  ///
  /// Mimics MathML's mmultiscripts.
  final bool alignPostscripts;

  /// Base where scripts are applied upon.
  final EquationRowNode base;

  /// Subscript.
  final EquationRowNode? sub;

  /// Superscript.
  final EquationRowNode? sup;

  /// Presubscript.
  final EquationRowNode? presub;

  /// Presuperscript.
  final EquationRowNode? presup;

  MultiscriptsNode({
    this.alignPostscripts = false,
    required this.base,
    this.sub,
    this.sup,
    this.presub,
    this.presup,
  });

  @override
  BuildResult buildWidget(
          MathOptions options, List<BuildResult?> childBuildResults) =>
      BuildResult(
        options: options,
        widget: Multiscripts(
          alignPostscripts: alignPostscripts,
          isBaseCharacterBox: base.flattenedChildList.length == 1 &&
              base.flattenedChildList[0] is SymbolNode,
          baseResult: childBuildResults[0]!,
          subResult: childBuildResults[1],
          supResult: childBuildResults[2],
          presubResult: childBuildResults[3],
          presupResult: childBuildResults[4],
        ),
      );

  @override
  List<MathOptions> computeChildOptions(MathOptions options) {
    final subOptions = options.havingStyle(options.style.sub());
    final supOptions = options.havingStyle(options.style.sup());
    return [options, subOptions, supOptions, subOptions, supOptions];
  }

  @override
  List<EquationRowNode?> computeChildren() => [base, sub, sup, presub, presup];

  @override
  AtomType get leftType =>
      presub == null && presup == null ? base.leftType : AtomType.ord;

  @override
  AtomType get rightType =>
      sub == null && sup == null ? base.rightType : AtomType.ord;

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  MultiscriptsNode updateChildren(List<EquationRowNode?> newChildren) =>
      MultiscriptsNode(
        alignPostscripts: alignPostscripts,
        base: newChildren[0]!,
        sub: newChildren[1],
        sup: newChildren[2],
        presub: newChildren[3],
        presup: newChildren[4],
      );

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'base': base.toJson(),
      if (sub != null) 'sub': sub?.toJson(),
      if (sup != null) 'sup': sup?.toJson(),
      if (presub != null) 'presub': presub?.toJson(),
      if (presup != null) 'presup': presup?.toJson(),
    });
}
