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

import 'dart:ui';

import 'package:flutter_math_fork/ast.dart';
import 'package:flutter_math_fork/src/parser/tex/font.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_math_fork/src/encoder/tex/encoder.dart';

void main() {
  group('style encoding test', () {
    test('math style handling', () {
      expect(
        StyleNode(
          optionsDiff: OptionsDiff(style: MathStyle.display),
          children: [SymbolNode(symbol: 'a')],
        ).encodeTeX(),
        '{\\displaystyle a}',
      );
    });

    test('size handling', () {
      expect(
        StyleNode(
          optionsDiff: OptionsDiff(size: MathSize.scriptsize),
          children: [SymbolNode(symbol: 'a')],
        ).encodeTeX(),
        '{\\scriptsize a}',
      );
    });

    test('font handling', () {
      expect(
        StyleNode(
          optionsDiff:
              OptionsDiff(mathFontOptions: texMathFontOptions['\\mathbf']),
          children: [SymbolNode(symbol: 'a')],
        ).encodeTeX(),
        '\\mathbf{a}',
      );
      expect(
        StyleNode(
          optionsDiff:
              OptionsDiff(textFontOptions: texTextFontOptions['\\textbf']),
          children: [SymbolNode(symbol: 'a', mode: Mode.text)],
        ).encodeTeX(),
        '\\textbf{a}',
      );
    });

    test('color handling', () {
      expect(
        StyleNode(
          optionsDiff: OptionsDiff(color: Color.fromARGB(0, 1, 2, 3)),
          children: [SymbolNode(symbol: 'a')],
        ).encodeTeX(),
        '\\textcolor{#010203}{a}',
      );
    });

    test('avoid extra brackets', () {
      expect(
        StyleNode(
          optionsDiff: OptionsDiff(
            style: MathStyle.display,
            size: MathSize.scriptsize,
            color: Color.fromARGB(0, 1, 2, 3),
          ),
          children: [SymbolNode(symbol: 'a')],
        ).encodeTeX(),
        '\\textcolor{#010203}{\\displaystyle \\scriptsize a}',
      );

      expect(
        EquationRowNode(children: [
          SymbolNode(symbol: 'z'),
          StyleNode(
            optionsDiff: OptionsDiff(
              style: MathStyle.display,
              size: MathSize.scriptsize,
            ),
            children: [SymbolNode(symbol: 'a')],
          ),
        ]).encodeTeX(),
        '{z\\displaystyle \\scriptsize a}',
      );
    });
  });
}
