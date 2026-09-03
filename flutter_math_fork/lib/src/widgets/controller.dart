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
import '../ast/syntax_tree.dart';
import '../utils/text_extension.dart';

class MathController extends ChangeNotifier {
  MathController({
    SyntaxTree? ast,
    TextSelection selection = const TextSelection.collapsed(offset: -1),
  })  : _ast = ast,
        _selection = selection;

  /// Returns true after [ast] has been assigned. External callers that build
  /// a controller before the first parse can check this before using [ast].
  bool get hasAst => _ast != null;

  SyntaxTree? _ast;
  SyntaxTree get ast {
    final a = _ast;
    if (a == null) {
      throw StateError('MathController.ast accessed before assignment.');
    }
    return a;
  }

  set ast(SyntaxTree value) {
    if (_ast != value) {
      _ast = value;
      // Preserve selection across AST updates (just clamp to new range).
      _selection = sanitizeSelection(value, _selection);
      notifyListeners();
    }
  }

  TextSelection get selection => _selection;
  TextSelection _selection;
  set selection(TextSelection value) {
    if (_selection != value) {
      _selection = sanitizeSelection(_ast, value);
      notifyListeners();
    }
  }

  TextSelection sanitizeSelection(SyntaxTree? ast, TextSelection selection) {
    if (ast == null) return selection;
    if (selection.end <= 0) return selection;
    return selection.constrainedBy(ast.root.range);
  }

  List<GreenNode> get selectedNodes =>
      ast.findSelectedNodes(selection.start, selection.end);
}
