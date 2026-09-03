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
