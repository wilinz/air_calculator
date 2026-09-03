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

import '../options.dart';
import '../syntax_tree.dart';

/// Node to denote all kinds of style changes.
class StyleNode extends TransparentNode {
  @override
  final List<GreenNode> children;

  /// The difference of [MathOptions].
  final OptionsDiff optionsDiff;

  StyleNode({
    required this.children,
    required this.optionsDiff,
  });

  @override
  List<MathOptions> computeChildOptions(MathOptions options) =>
      List.filled(children.length, options.merge(optionsDiff), growable: false);

  @override
  bool shouldRebuildWidget(MathOptions oldOptions, MathOptions newOptions) =>
      false;

  @override
  ParentableNode<GreenNode> updateChildren(List<GreenNode> newChildren) =>
      copyWith(children: newChildren);

  @override
  Map<String, Object?> toJson() => super.toJson()
    ..addAll({
      'children': children.map((e) => e.toJson()).toList(growable: false),
      'optionsDiff': optionsDiff.toString(),
    });

  StyleNode copyWith({
    List<GreenNode>? children,
    OptionsDiff? optionsDiff,
  }) =>
      StyleNode(
        children: children ?? this.children,
        optionsDiff: optionsDiff ?? this.optionsDiff,
      );
}
