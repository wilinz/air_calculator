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

part of '../functions.dart';

EncodeResult _symbolEncoder(GreenNode node) {
  final symbolNode = node as SymbolNode;
  final symbol = symbolNode.symbol;
  final mode = symbolNode.mode;
  final encodeAsBaseSymbol = _baseSymbolEncoder(
    symbol,
    mode,
    symbolNode.overrideFont,
    symbolNode.atomType,
    symbolNode.overrideAtomType,
  );
  if (encodeAsBaseSymbol != null) {
    return StaticEncodeResult(encodeAsBaseSymbol);
  }
  if (mode == Mode.math && negatedOperatorSymbols.containsKey(symbol)) {
    final encodeAsNegatedOp =
        _baseSymbolEncoder(negatedOperatorSymbols[symbol]![1], Mode.math);
    if (encodeAsNegatedOp != null) {
      return StaticEncodeResult('\\not $encodeAsNegatedOp');
    }
  }
  return NonStrictEncodeResult(
    'unknown symbol',
    'Unrecognized symbol encountered during TeX encoding: '
        '${unicodeLiteral(symbol)} with mode $mode type ${symbolNode.atomType} '
        'font ${symbolNode.overrideFont?.fontName}',
    StaticEncodeResult(symbolNode.symbol),
  );
}

String? _baseSymbolEncoder(String symbol, Mode mode,
    [FontOptions? overrideFont, AtomType? type, AtomType? overrideType]) {
  // For alpha-numeric and unescaped symbols, provide a fast track
  if (overrideFont == null && overrideType == null && symbol.length == 1) {
    if (isAlphaNumericUnit(symbol) ||
        const {
          '!', '*', '(', ')', '-', '+', '=', //
          '|', ':', ';', "'", '"', ',', '<', '.', '>', '?', '/'
        }.contains(symbol)) {
      return symbol;
    }
  }
  final candidates = <MapEntry<String, TexSymbolConfig>>[];
  if (mode != Mode.text) {
    candidates.addAll(
      texSymbolCommandConfigs[Mode.math]!
          .entries
          .where((entry) => entry.value.symbol == symbol),
    );
  }
  if (mode != Mode.math) {
    candidates.addAll(
      texSymbolCommandConfigs[Mode.text]!
          .entries
          .where((entry) => entry.value.symbol == symbol),
    );
  }
  candidates.sortBy<num>((candidate) {
    final candidFont = candidate.value.font;
    final fontScore = candidFont == overrideFont
        ? 1000
        : (candidFont?.fontFamily == overrideFont?.fontFamily ? 500 : 0) +
            (candidFont?.fontShape == overrideFont?.fontShape ? 300 : 0) +
            (candidFont?.fontWeight == overrideFont?.fontWeight ? 200 : 0);
    final typeScore = candidate.value.type == overrideType
        ? 150
        : candidate.value.type == type
            ? 100
            : 0;
    final commandConciseness = 100 ~/ candidate.key.length -
        100 *
            candidate.key.runes
                .where((point) => point > 126 || point < 32)
                .length;
    return fontScore + typeScore + commandConciseness;
  });
  return candidates.lastOrNull?.key;
}
