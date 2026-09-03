// The MIT License (MIT)
//
// Copyright (c) 2013-2019 Khan Academy and other contributors
// Copyright (c) 2020 znjameswu <znjameswu@gmail.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import '../../ast/types.dart';
import 'functions.dart';
import 'lexer.dart';
import 'macros.dart';
import 'namespace.dart';
import 'parse_error.dart';
import 'settings.dart';
import 'symbols.dart';
import 'token.dart';

// List of commands that act like macros but aren't defined as a macro,
// function, or symbol.  Used in `isDefined`.
const implicitCommands = {
  '\\relax', // MacroExpander.js
  '^', // Parser.js
  '_', // Parser.js
  '\\limits', // Parser.js
  '\\nolimits', // Parser.js
};

class MacroExpander implements MacroContext {
  MacroExpander(this.input, this.settings, this.mode)
      : macros = Namespace(builtinMacros, settings.macros),
        lexer = Lexer(input, settings);

  String input;
  TexParserSettings settings;
  @override
  Mode mode;
  int expansionCount = 0;
  var stack = <Token>[];
  Lexer lexer;
  @override
  Namespace<MacroDefinition> macros;

  @override
  Token expandAfterFuture() {
    expandOnce();
    return future();
  }

  @override
  Token expandNextToken() {
    while (true) {
      final expanded = expandOnce();
      if (expanded != null) {
        if (expanded.text == r'\relax') {
          stack.removeLast();
        } else {
          return stack.removeLast();
        }
      }
    }
  }

  // switchMode is replaced by a plain setter

  void beginGroup() {
    macros.beginGroup();
  }

  void endGroup() {
    macros.endGroup();
  }

  @override
  Token? expandOnce([bool expandableOnly = false]) {
    final topToken = popToken();
    final name = topToken.text;
    final expansion = !topToken.noexpand ? _getExpansion(name) : null;
    if (expansion == null || (expandableOnly && expansion.unexpandable)) {
      if (expandableOnly &&
          expansion == null &&
          name[0] == '\\' &&
          isDefined(name)) {
        throw ParseException('Undefined control sequence: $name');
      }
      pushToken(topToken);
      return topToken;
    }
    expansionCount += 1;
    if (expansionCount > settings.maxExpand) {
      throw ParseException('Too many expansions: infinite loop or '
          'need to increase maxExpand setting');
    }
    var tokens = expansion.tokens;
    if (expansion.numArgs != 0) {
      final args = consumeArgs(expansion.numArgs);
      // Make a copy to avoid modify to be sure.
      // Actually not needed with current implementation.
      // But who knows for the future?
      tokens = tokens.toList();
      for (var i = tokens.length - 1; i >= 0; --i) {
        var tok = tokens[i];
        if (tok.text == '#') {
          if (i == 0) {
            throw ParseException(
                'Incomplete placeholder at end of macro body', tok);
          }
          --i;
          tok = tokens[i];
          if (tok.text == '#') {
            tokens.removeAt(i + 1);
          } else {
            try {
              tokens.replaceRange(i, i + 2, args[int.parse(tok.text) - 1]);
            } on FormatException {
              throw ParseException('Not a valid argument number', tok);
            }
          }
        }
      }
    }
    pushTokens(tokens);
    return null;
  }

  void pushToken(Token token) {
    stack.add(token);
  }

  void pushTokens(List<Token> tokens) {
    stack.addAll(tokens);
  }

  @override
  Token popToken() {
    future();
    return stack.removeLast();
  }

  @override
  Token future() {
    if (stack.isEmpty) {
      stack.add(lexer.lex());
    }
    return stack.last;
  }

  MacroExpansion? _getExpansion(String name) {
    final definition = macros.get(name);
    if (definition == null) {
      return null;
    }
    return definition.expand(this);
  }

  @override
  List<List<Token>> consumeArgs(int numArgs) {
    final args = List<List<Token>>.generate(numArgs, (i) {
      consumeSpaces();
      final startOfArg = popToken();
      if (startOfArg.text == '{') {
        final arg = <Token>[];
        var depth = 1;
        while (depth != 0) {
          final tok = popToken();
          arg.add(tok);
          switch (tok.text) {
            case '{':
              ++depth;
              break;
            case '}':
              --depth;
              break;
            case 'EOF':
              throw ParseException(
                  'End of input in macro argument', startOfArg);
          }
        }
        arg.removeLast();
        return arg.reversed.toList();
      } else if (startOfArg.text == 'EOF') {
        throw ParseException('End of input expecting macro argument');
      } else {
        return [startOfArg];
      }
    });
    return args;
  }

  @override
  void consumeSpaces() {
    while (true) {
      final token = future();
      if (token.text == ' ') {
        stack.removeLast();
      } else {
        break;
      }
    }
  }

  @override
  bool isDefined(String name) =>
      macros.has(name) ||
      texSymbolCommandConfigs[Mode.math]!.containsKey(name) ||
      texSymbolCommandConfigs[Mode.text]!.containsKey(name) ||
      functions.containsKey(name) ||
      implicitCommands.contains(name);

  @override
  bool isExpandable(String name) {
    final macro = macros.get(name);
    return macro?.expandable ?? functions.containsKey(name);
  }

  @override
  Lexer getNewLexer(String input) => Lexer(input, settings);

  String? expandMacroAsText(String name) {
    final tokens = expandMacro(name);
    if (tokens != null) {
      return tokens.map((token) => token.text).join('');
    }
    return null;
  }

  List<Token>? expandMacro(String name) {
    if (macros.get(name) == null) {
      return null;
    }
    final output = <Token>[];
    final oldStackLength = stack.length;
    pushToken(Token(name));
    while (stack.length > oldStackLength) {
      final expanded = expandOnce();
      // expandOnce returns Token if and only if it's fully expanded.
      if (expanded != null) {
        output.add(stack.removeLast());
      }
    }
    return output;
  }
}

abstract class MacroContext {
  Mode get mode;
  Namespace<MacroDefinition> get macros;
  Token future();
  Token popToken();
  void consumeSpaces();
//  Token expandAfterFuture();
  // ignore: avoid_positional_boolean_parameters
  Token? expandOnce([bool expandableOnly]);
  Token expandAfterFuture();
  Token expandNextToken();
//
  List<List<Token>> consumeArgs(int numArgs);
  bool isDefined(String name);
  bool isExpandable(String name);

  Lexer getNewLexer(String input);
}
