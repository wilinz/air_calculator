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

import 'dart:collection';
import 'dart:ui';

import 'package:collection/collection.dart';

import '../../ast/nodes/multiscripts.dart';
import '../../ast/nodes/over.dart';
import '../../ast/nodes/style.dart';
import '../../ast/nodes/symbol.dart';
import '../../ast/nodes/under.dart';
import '../../ast/options.dart';
import '../../ast/size.dart';
import '../../ast/style.dart';
import '../../ast/symbols/symbols_unicode.dart';
import '../../ast/syntax_tree.dart';
import '../../ast/types.dart';
import '../../font/metrics/unicode_scripts.dart';
import 'colors.dart';
import 'functions.dart';
import 'lexer.dart';
import 'macro_expander.dart';
import 'macros.dart';
import 'parse_error.dart';
import 'settings.dart';
import 'symbols.dart';
import 'token.dart';
import 'unicode_accents.dart';

/// Parser for TeX equations
///
/// Convert TeX string to Flutter Math's AST
class TexParser {
  TexParser(String content, this.settings)
      : leftrightDepth = 0,
        mode = Mode.math,
        macroExpander = MacroExpander(content, settings, Mode.math);

  final TexParserSettings settings;
  Mode mode;
  int leftrightDepth;

  final MacroExpander macroExpander;
  Token? nextToken;

  /// Get parse result
  EquationRowNode parse() {
    if (!settings.globalGroup) {
      macroExpander.beginGroup();
    }
    if (settings.colorIsTextColor) {
      macroExpander.macros
          .set('\\color', MacroDefinition.fromString('\\textcolor'));
    }
    final parse = parseExpression(breakOnInfix: false);

    expect('EOF');

    if (!settings.globalGroup) {
      macroExpander.endGroup();
    }
    return parse.wrapWithEquationRow();
  }

  List<GreenNode> parseExpression({
    bool breakOnInfix = false,
    String? breakOnTokenText,
    bool infixArgumentMode = false,
  }) {
    final body = <GreenNode>[];
    while (true) {
      if (mode == Mode.math) {
        consumeSpaces();
      }
      final lex = fetch();
      if (endOfExpression.contains(lex.text)) {
        break;
      }
      if (breakOnTokenText != null && lex.text == breakOnTokenText) {
        break;
      }
      // Detects a infix function
      final funcData = functions[lex.text];
      if (funcData != null && funcData.infix == true) {
        if (infixArgumentMode) {
          throw ParseException('only one infix operator per group', lex);
        }
        if (breakOnInfix) {
          break;
        }
        consume();
        _enterArgumentParsingMode(lex.text, funcData);
        try {
          // A new way to handle infix operations
          final atom = funcData.handler(
            this,
            FunctionContext(
              funcName: lex.text,
              breakOnTokenText: breakOnTokenText,
              token: lex,
              infixExistingArguments: List.of(body, growable: false),
            ),
          );
          body.clear();
          body.add(atom);
        } finally {
          _leaveArgumentParsingMode(lex.text);
        }
      } else {
        // Add a normal atom
        final atom = parseAtom(breakOnTokenText);
        if (atom == null) {
          break;
        }
        body.add(atom);
      }
    }

    return body;
    // We will NOT handle ligatures between '-' and "'", as neither did MathJax.
    // if (this.mode == Mode.text) {
    //   formLigatures(body);
    // }
    // We will not handle infix as well
    // return handleInfixNodes(body);
  }

  static const Set<String> breakTokens = {
    ']',
    '}',
    '\\endgroup',
    '\$',
    '\\)',
    '\\cr',
  };
  static const Set<String> endOfExpression = {
    '}',
    '\\endgroup',
    '\\end',
    '\\right',
    '&',
  };

  static const Map<String, String> endOfGroup = {
    '[': ']',
    '{': '}',
    '\\begingroup': '\\endgroup',
  };

  void expect(String text, {bool consume = true}) {
    if (fetch().text != text) {
      throw ParseException(
          'Expected \'$text\', got \'${fetch().text}\'', fetch());
    }
    if (consume) {
      this.consume();
    }
  }

  void consumeSpaces() {
    while (fetch().text == ' ') {
      consume();
    }
  }

  GreenNode? parseAtom(String? breakOnTokenText) {
    final base = parseGroup('atom',
        optional: false, greediness: null, breakOnTokenText: breakOnTokenText);

    if (mode == Mode.text) {
      return base;
    }

    final scriptsResult = parseScripts(
        allowLimits:
            base is EquationRowNode && base.overrideType == AtomType.op);

    if (!scriptsResult.empty) {
      if (scriptsResult.limits != true) {
        return MultiscriptsNode(
          base: base?.wrapWithEquationRow() ?? EquationRowNode.empty(),
          sub: scriptsResult.subscript,
          sup: scriptsResult.superscript,
        );
      } else {
        var res = scriptsResult.superscript != null
            ? OverNode(
                base: base?.wrapWithEquationRow() ?? EquationRowNode.empty(),
                above: scriptsResult.superscript!)
            : base;
        res = scriptsResult.subscript != null
            ? UnderNode(
                base: res?.wrapWithEquationRow() ?? EquationRowNode.empty(),
                below: scriptsResult.subscript!)
            : res;
        return res;
      }
    } else {
      return base;
    }
  }

  /// The following functions are separated from parseAtoms in KaTeX
  /// This function will only be invoked in math mode
  ScriptsParsingResults parseScripts({bool allowLimits = false}) {
    EquationRowNode? subscript;
    EquationRowNode? superscript;
    bool? limits;
    loop:
    while (true) {
      consumeSpaces();
      final lex = fetch();
      switch (lex.text) {
        case '\\limits':
        case '\\nolimits':
          if (!allowLimits) {
            throw ParseException(
                'Limit controls must follow a math operator', lex);
          }
          limits = lex.text == '\\limits';
          consume();
          break;
        case '^':
          if (superscript != null) {
            throw ParseException('Double superscript', lex);
          }
          superscript = _handleScript().wrapWithEquationRow();
          break;
        case '_':
          if (subscript != null) {
            throw ParseException('Double subscript', lex);
          }
          subscript = _handleScript().wrapWithEquationRow();
          break;
        case "'":
          if (superscript != null) {
            throw ParseException('Double superscript', lex);
          }
          final primeCommand = texSymbolCommandConfigs[Mode.math]!['\\prime']!;
          final superscriptList = <GreenNode>[
            SymbolNode(
              mode: mode,
              symbol: primeCommand.symbol,
              variantForm: primeCommand.variantForm,
              overrideAtomType: primeCommand.type,
              overrideFont: primeCommand.font,
            ),
          ];
          consume();
          while (fetch().text == "'") {
            superscriptList.add(
              SymbolNode(
                mode: mode,
                symbol: primeCommand.symbol,
                variantForm: primeCommand.variantForm,
                overrideAtomType: primeCommand.type,
                overrideFont: primeCommand.font,
              ),
            );
            consume();
          }
          if (fetch().text == '^') {
            superscriptList.addAll(_handleScript().expandEquationRow());
          }
          superscript = superscriptList.wrapWithEquationRow();
          break;
        default:
          break loop;
      }
    }
    return ScriptsParsingResults(
      subscript: subscript,
      superscript: superscript,
      limits: limits,
    );
  }

  GreenNode _handleScript() {
    final symbolToken = fetch();
    final symbol = symbolToken.text;
    consume();
    final group = parseGroup(
      symbol == '_' ? 'subscript' : 'superscript',
      optional: false,
      greediness: TexParser.supsubGreediness,
      consumeSpaces: true,
    );
    if (group == null) {
      throw ParseException("Expected group after '$symbol'", symbolToken);
    }
    return group;
  }

  static const supsubGreediness = 1;

  Token fetch() {
    final nextToken = this.nextToken;
    if (nextToken == null) {
      return this.nextToken = macroExpander.expandNextToken();
    }
    return nextToken;
  }

  void consume() {
    nextToken = null;
  }

  /// [parseGroup] Return a row if encounters \[\] or {}. Returns single function
  /// node or a single symbol otherwise.
  ///
  ///
  /// If `optional` is false or absent, this parses an ordinary group,
  /// which is either a single nucleus (like "x") or an expression
  /// in braces (like "{x+y}") or an implicit group, a group that starts
  /// at the current position, and ends right before a higher explicit
  /// group ends, or at EOF.
  /// If `optional` is true, it parses either a bracket-delimited expression
  /// (like "[x+y]") or returns null to indicate the absence of a
  /// bracket-enclosed group.
  /// If `mode` is present, switches to that mode while parsing the group,
  /// and switches back after.
  GreenNode? parseGroup(
    String name, {
    required bool optional,
    int? greediness,
    String? breakOnTokenText,
    Mode? mode,
    bool consumeSpaces = false,
  }) {
    // Save current mode and restore after completion
    final outerMode = this.mode;
    if (mode != null) {
      switchMode(mode);
    }
    // Consume spaces if requested, crucially *after* we switch modes,
    // so that the next non-space token is parsed in the correct mode.
    if (consumeSpaces == true) {
      this.consumeSpaces();
    }
    // Get first token
    final firstToken = fetch();
    final text = firstToken.text;
    GreenNode? result;
    // Try to parse an open brace or \begingroup
    if (optional ? text == '[' : text == '{' || text == '\\begingroup') {
      consume();
      final groupEnd = endOfGroup[text]!;
      // Start a new group namespace
      macroExpander.beginGroup();
      // If we get a brace, parse an expression
      final expression =
          parseExpression(breakOnInfix: false, breakOnTokenText: groupEnd);
      // final lastToken = this.fetch();
      // Check that we got a matching closing brace
      expect(groupEnd);
      macroExpander.endGroup();
      result = expression.wrapWithEquationRow();
    } else if (optional) {
      // Return nothing for an optional group
      result = null;
    } else {
      // If there exists a function with this name, parse the function.
      // Otherwise, just return a nucleus
      result =
          parseFunction(breakOnTokenText, name, greediness) ?? _parseSymbol();
      if (result == null &&
          text[0] == '\\' &&
          !implicitCommands.contains(text)) {
        if (settings.throwOnError) {
          throw ParseException('Undefined control sequence: $text', firstToken);
        }
        result = _formatUnsuppotedCmd(text);
        consume();
      }
    }
    if (mode != null) {
      switchMode(outerMode);
    }
    return result;
  }

  ///Parses an entire function, including its base and all of its arguments.

  GreenNode? parseFunction(
      String? breakOnTokenText, String? name, int? greediness) {
    final token = fetch();
    final func = token.text;
    final funcData = functions[func];
    if (funcData == null) {
      return null;
    }
    consume();

    if (greediness != null &&
        // funcData.greediness != null &&
        funcData.greediness <= greediness) {
      throw ParseException(
          '''Got function '$func' with no arguments ${name != null ? ' as $name' : ''}''',
          token);
    } else if (mode == Mode.text && !funcData.allowedInText) {
      throw ParseException(
          '''Can't use function '$func' in text mode''', token);
    } else if (mode == Mode.math && funcData.allowedInMath == false) {
      throw ParseException(
          '''Can't use function '$func' in math mode''', token);
    }

    // final funcArgs = parseArgument(func, funcData);

    final context = FunctionContext(
      funcName: func,
      token: token,
      breakOnTokenText: breakOnTokenText,
    );

    // if (funcData.handler != null) {
    _enterArgumentParsingMode(func, funcData);
    try {
      return funcData.handler(this, context);
    } finally {
      _leaveArgumentParsingMode(func);
    }
    // } else {
    //   throw ParseException('''No function handler for $name''');
    // }
    // return this.callFunction(func, token, breakOnTokenText);
  }

  final argParsingContexts = Queue<ArgumentParsingContext>();

  ArgumentParsingContext get currArgParsingContext => argParsingContexts.last;

  void _enterArgumentParsingMode(String name, FunctionSpec funcData) {
    argParsingContexts
        .addLast(ArgumentParsingContext(funcName: name, funcData: funcData));
  }

  void _leaveArgumentParsingMode(String name) {
    assert(currArgParsingContext.funcName == name);
    argParsingContexts.removeLast();
  }

  void _assertOptionalBeforeReturn(dynamic value, {required bool optional}) {
    if (!optional && value == null) {
      throw ParseException(
          'Expected group after ${currArgParsingContext.funcName}', fetch());
    }
  }

  static final _parseColorRegex1 =
      RegExp(r'^#([a-f0-9])([a-f0-9])([a-f0-9])$', caseSensitive: false);
  static final _parseColorRegex2 = RegExp(
      r'^#?([a-f0-9]{2})([a-f0-9]{2})([a-f0-9]{2})$',
      caseSensitive: false);
  static final _parseColorRegex3 = RegExp(r'^([a-z]+)$', caseSensitive: false);

  // static final _parseColorRegex =
  //     RegExp(r'^(#[a-f0-9]{3}|#?[a-f0-9]{6}|[a-z]+)$', caseSensitive: false);
  // static final _matchColorRegex =
  //     RegExp(r'[0-9a-f]{6}', caseSensitive: false);
  Color? parseArgColor({required bool optional}) {
    currArgParsingContext.newArgument(optional: optional);
    final i = currArgParsingContext.currArgNum;
    final consumeSpaces =
        (i > 0 && !optional) || (i == 0 && !optional && mode == Mode.math);
    if (consumeSpaces) {
      this.consumeSpaces();
    }
    // final res = this.parseColorGroup(optional: optional);
    final res = _parseStringGroup('color', optional: optional);
    if (res == null) {
      _assertOptionalBeforeReturn(null, optional: optional);
      return null;
    }

    final match3 = _parseColorRegex3.firstMatch(res.text);

    if (match3 != null) {
      final color = colorByName[match3[0]!.toLowerCase()];
      if (color != null) {
        return color;
      }
    }

    final match2 = _parseColorRegex2.firstMatch(res.text);
    if (match2 != null) {
      return Color.fromARGB(
        0xff,
        int.parse(match2[1]!, radix: 16),
        int.parse(match2[2]!, radix: 16),
        int.parse(match2[3]!, radix: 16),
      );
    }

    final match1 = _parseColorRegex1.firstMatch(res.text);
    if (match1 != null) {
      return Color.fromARGB(
        0xff,
        int.parse(match1[1]! * 2, radix: 16),
        int.parse(match1[2]! * 2, radix: 16),
        int.parse(match1[3]! * 2, radix: 16),
      );
    }
    throw ParseException("Invalid color: '${res.text}'");
  }

  static final _parseSizeRegex =
      RegExp(r'^[-+]? *(?:$|\d+|\d+\.\d*|\.\d*) *[a-z]{0,2} *$');
  static final _parseMeasurementRegex =
      RegExp(r'([-+]?) *(\d+(?:\.\d*)?|\.\d+) *([a-z]{2})');

  Measurement? parseArgSize({required bool optional}) {
    currArgParsingContext.newArgument(optional: optional);
    final i = currArgParsingContext.currArgNum;
    final consumeSpaces =
        (i > 0 && !optional) || (i == 0 && !optional && mode == Mode.math);
    if (consumeSpaces) {
      this.consumeSpaces();
    }

    // final res = this.parseSizeGroup(optional: optional);
    Token? res;
    if (!optional && fetch().text != '{') {
      res = _parseRegexGroup(_parseSizeRegex, 'size');
    } else {
      res = _parseStringGroup('size', optional: optional);
    }
    if (res == null) {
      _assertOptionalBeforeReturn(null, optional: optional);
      return null;
    }
    if (!optional && res.text.isEmpty) {
      // res.text = '0pt';
      // This means default width for genfrac, and 0pt for above
      return null;
    }
    final match = _parseMeasurementRegex.firstMatch(res.text);
    if (match == null) {
      throw ParseException("Invalid size: '${res.text}'", res);
    }

    final unit = match[3]!.parseUnit();
    if (unit == null) {
      throw ParseException("Invalid unit: '${match[3]}'", res);
    }
    final size =
        Measurement(value: double.parse(match[1]! + match[2]!), unit: unit);
    return size;
  }

  String parseArgUrl({required bool optional}) {
    currArgParsingContext.newArgument(optional: optional);
    // final i = currArgParsingContext.currArgNum;
    // final consumeSpaces =
    //  (i > 0 && !optional) || (i == 0 && !optional && this.mode == Mode.math);
    // if (consumeSpaces) {
    //   this.consumeSpaces();
    // }
    // final res = this.parseUrlGroup(optional: optional);
    throw UnimplementedError();
  }

  GreenNode? parseArgNode({required Mode? mode, required bool optional}) {
    currArgParsingContext.newArgument(optional: optional);
    final i = currArgParsingContext.currArgNum;
    final consumeSpaces =
        (i > 0 && !optional) || (i == 0 && !optional && this.mode == Mode.math);
    // if (consumeSpaces) {
    //   this.consumeSpaces();
    // }
    final res = parseGroup(
      currArgParsingContext.name,
      optional: optional,
      greediness: currArgParsingContext.funcData.greediness,
      mode: mode,
      consumeSpaces: consumeSpaces,
    );
    _assertOptionalBeforeReturn(res, optional: optional);
    return res;
  }

  GreenNode parseArgHbox({required bool optional}) {
    final res = parseArgNode(mode: Mode.text, optional: optional);
    if (res is EquationRowNode) {
      return EquationRowNode(children: [
        StyleNode(
          optionsDiff: OptionsDiff(style: MathStyle.text),
          children: res.children,
        )
      ]);
    } else {
      return StyleNode(
        optionsDiff: OptionsDiff(style: MathStyle.text),
        children: res?.children.whereNotNull().toList(growable: false) ?? [],
      );
    }
  }

  String? parseArgRaw({required bool optional}) {
    currArgParsingContext.newArgument(optional: optional);
    final i = currArgParsingContext.currArgNum;
    final consumeSpaces =
        (i > 0 && !optional) || (i == 0 && !optional && mode == Mode.math);
    if (consumeSpaces) {
      this.consumeSpaces();
    }
    if (optional && fetch().text == '{') {
      return null;
    }
    final token = _parseStringGroup('raw', optional: optional);
    if (token != null) {
      return token.text;
    } else {
      throw ParseException('Expected raw group', fetch());
    }
  }

  static final _parseStringGroupRegex = RegExp('''[^{}[]]''');

  Token? _parseStringGroup(String modeName,
      {required bool optional, bool raw = false}) {
    final groupBegin = optional ? '[' : '{';
    final groupEnd = optional ? ']' : '}';
    final beginToken = fetch();
    if (beginToken.text != groupBegin) {
      if (optional) {
        return null;
      } else if (raw &&
          beginToken.text != 'EOF' &&
          _parseStringGroupRegex.hasMatch(beginToken.text)) {
        consume();
        return beginToken;
      }
    }
    final outerMode = mode;
    mode = Mode.text;
    expect(groupBegin);

    var str = '';
    final firstToken = fetch();
    var nested = 0;
    var lastToken = firstToken;
    Token nextToken;
    while ((nextToken = fetch()).text != groupEnd || (raw && nested > 0)) {
      if (nextToken.text == 'EOF') {
        throw ParseException('Unexpected end of input in $modeName',
            Token.range(firstToken, lastToken, str));
      } else if (nextToken.text == groupBegin) {
        nested++;
      } else if (nextToken.text == groupEnd) {
        nested--;
      }
      lastToken = nextToken;
      str += lastToken.text;
      consume();
    }
    expect(groupEnd);
    mode = outerMode;
    return Token.range(firstToken, lastToken, str);
  }

  Token _parseRegexGroup(RegExp regex, String modeName) {
    final outerMode = mode;
    mode = Mode.text;
    final firstToken = fetch();
    var lastToken = firstToken;
    var str = '';
    Token nextToken;
    while ((nextToken = fetch()).text != 'EOF' &&
        regex.hasMatch(str + nextToken.text)) {
      lastToken = nextToken;
      str += lastToken.text;
      consume();
    }
    if (str.isEmpty) {
      throw ParseException(
          "Invalid $modeName: '${firstToken.text}'", firstToken);
    }
    mode = outerMode;
    return Token.range(firstToken, lastToken, str);
  }

  static final _parseVerbRegex = RegExp(r'^\\verb[^a-zA-Z]');

  GreenNode? _parseSymbol() {
    final nucleus = fetch();
    var text = nucleus.text;
    if (_parseVerbRegex.hasMatch(text)) {
      consume();
      var arg = text.substring(5);
      final star = (arg[0] == '*'); //?
      if (star) {
        arg = arg.substring(1);
      }
      // Lexer's tokenRegex is constructed to always have matching
      // first/last characters.

      if (arg.length < 2 || arg[0] != arg[arg.length - 1]) {
        throw ParseException('''\\verb assertion failed --
                    please report what input caused this bug''');
      }
      arg = arg.substring(1, arg.length - 1);
      return EquationRowNode(
        children: arg
            .split('')
            .map((char) => SymbolNode(
                  symbol: char,
                  overrideFont: const FontOptions(fontFamily: 'Typewriter'),
                  mode: Mode.text,
                ))
            .toList(growable: false),
      );
    }
    // At this point, we should have a symbol, possibly with accents.
    // First expand any accented base symbol according to unicodeSymbols.
    if (unicodeSymbols.containsKey(text[0]) &&
        !texSymbolCommandConfigs[mode]!.containsKey(text[0])) {
      if (mode == Mode.math) {
        settings.reportNonstrict(
            'unicodeTextInMathMode',
            'Accented Unicode text character "${text[0]}" used in math mode',
            nucleus);
      }
      // text = unicodeSymbols[text[0]] + text.substring(1);
    }
    // Strip off any combining characters
    final match = combiningDiacriticalMarksEndRegex.firstMatch(text);
    var combiningMarks = '';
    if (match != null) {
      text = text.substring(0, match.start);
      for (var i = 0; i < match[0]!.length; i++) {
        final accent = match[0]![i];
        if (!unicodeAccents.containsKey(accent)) {
          throw ParseException("Unknown accent ' $accent'", nucleus);
        }
        final command = unicodeAccents[accent]![mode];
        if (command == null) {
          throw ParseException(
              'Accent $accent unsupported in $mode mode', nucleus);
        }
      }
      combiningMarks = match[0]!;
    }
    // Recognize base symbol
    GreenNode symbol;
    final symbolCommandConfig = texSymbolCommandConfigs[mode]![text];
    if (symbolCommandConfig != null) {
      if (mode == Mode.math && extraLatin.contains(text)) {
        settings.reportNonstrict(
            'unicodeTextInMathMode',
            'Latin-1/Unicode text character "${text[0]}" used in math mode',
            nucleus);
      }
      // final loc = SourceLocation.range(nucleus);
      symbol = SymbolNode(
        mode: mode,
        symbol: symbolCommandConfig.symbol + combiningMarks,
        variantForm: symbolCommandConfig.variantForm,
        overrideAtomType: symbolCommandConfig.type,
        overrideFont: symbolCommandConfig.font,
      );
    } else if (text.isNotEmpty && text.codeUnitAt(0) >= 0x80) {
      if (!supportedCodepoint(text.codeUnitAt(0))) {
        settings.reportNonstrict(
            'unknownSymbol',
            'Unrecognized Unicode character "${text[0]}" '
                '(${text.codeUnitAt(0)})',
            nucleus);
      } else if (mode == Mode.math) {
        settings.reportNonstrict('unicodeTextInMathMode',
            'Unicode text character "${text[0]} used in math mode"', nucleus);
      }
      symbol = SymbolNode(
          symbol: text + combiningMarks,
          overrideAtomType: AtomType.ord,
          mode: mode);
    } else {
      return null;
    }
    consume();
    return symbol;
  }

  void switchMode(Mode newMode) {
    mode = newMode;
    macroExpander.mode = newMode;
  }

  GreenNode _formatUnsuppotedCmd(String text) {
    //TODO
    throw UnimplementedError();
  }
}

class ArgumentParsingContext {
  final String funcName;
  int currArgNum;
  final FunctionSpec funcData;

  bool get optional => _optional;
  bool _optional;

  set optional(bool value) {
    assert(_optional || !value);
    _optional = value;
  }

  String get name => 'argument to $funcName';

  ArgumentParsingContext({
    required this.funcData,
    required this.funcName,
    this.currArgNum = -1,
    bool optional = true,
  }) : _optional = optional;

  void newArgument({required bool optional}) {
    currArgNum++;
    this.optional = optional;
  }
}

class ScriptsParsingResults {
  final EquationRowNode? subscript;
  final EquationRowNode? superscript;
  final bool? limits;

  const ScriptsParsingResults({
    required this.subscript,
    required this.superscript,
    this.limits,
  });

  bool get empty => subscript == null && superscript == null;
}

T assertNodeType<T extends GreenNode?>(GreenNode? node) {
  if (node is T) {
    return node;
  }
  throw ParseException(
      'Expected node of type $T, but got node of type ${node.runtimeType}');
}
