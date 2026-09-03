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

/// Utilities to manipulate Flutter Math's ASTs
///
/// See also:
///
/// * [GreenNode]
/// * [SyntaxNode]
/// * [SyntaxTree]
library;

import 'src/ast/syntax_tree.dart';

export 'src/ast/nodes/accent.dart';
export 'src/ast/nodes/accent_under.dart';
export 'src/ast/nodes/enclosure.dart' show EnclosureNode;
export 'src/ast/nodes/equation_array.dart';
export 'src/ast/nodes/frac.dart' show FracNode;
export 'src/ast/nodes/function.dart';
export 'src/ast/nodes/left_right.dart' show LeftRightNode;
export 'src/ast/nodes/matrix.dart';
export 'src/ast/nodes/multiscripts.dart';
export 'src/ast/nodes/nary_op.dart';
export 'src/ast/nodes/over.dart';
export 'src/ast/nodes/phantom.dart';
export 'src/ast/nodes/raise_box.dart';
export 'src/ast/nodes/space.dart';
export 'src/ast/nodes/sqrt.dart' show SqrtNode;
export 'src/ast/nodes/stretchy_op.dart' show StretchyOpNode;
export 'src/ast/nodes/style.dart';
export 'src/ast/nodes/symbol.dart' show SymbolNode;
export 'src/ast/nodes/under.dart';
export 'src/ast/options.dart';
export 'src/ast/size.dart';
export 'src/ast/style.dart';
export 'src/ast/syntax_tree.dart'
    hide TemporaryNode, BuildResult, PositionDependentMixin;
export 'src/ast/tex_break.dart' hide BreakResult;
export 'src/ast/types.dart';
