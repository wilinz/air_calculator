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

import 'package:flutter_math_fork/ast.dart';
import 'package:flutter_math_fork/src/encoder/encoder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_math_fork/src/encoder/tex/encoder.dart';

import 'recode.dart';

void main() {
  group('EquationRowEncoderResult', () {
    test('empty row', () {
      final result = EquationRowTexEncodeResult(<dynamic>[]);
      expect(result.stringify(TexEncodeConf.mathConf), '{}');
      expect(result.stringify(TexEncodeConf.mathParamConf), '');
    });

    test('normal row', () {
      final result = EquationRowTexEncodeResult(<dynamic>[
        'a',
        StaticEncodeResult('b'),
        SymbolNode(symbol: 'c'),
        EquationRowNode.empty(),
      ]);
      expect(result.stringify(TexEncodeConf.mathConf), '{abc{}}');
      expect(result.stringify(TexEncodeConf.mathParamConf), 'abc{}');
    });

    test('symbol contanetation', () {
      const testStrings = [
        'i\\pi x',
        'i\\pi\\xi',
      ];
      for (final testString in testStrings) {
        expect(recodeTex(testString), testString);
      }
    });
  });
  group('TexCommandEncoderResult', () {
    test('basic spec lookup', () {
      final result =
          TexCommandEncodeResult(command: '\\frac', args: <dynamic>[]);
      expect(result.numArgs, 2);
      expect(result.numOptionalArgs, 0);
      expect(result.argModes, [null, null]);
    });

    test('empty math param', () {
      final result = TexCommandEncodeResult(
          command: '\\frac',
          args: <dynamic>[EquationRowNode.empty(), EquationRowNode.empty()]);
      expect(result.stringify(TexEncodeConf.mathConf), '\\frac{}{}');
    });

    test('single char math param', () {
      final result =
          TexCommandEncodeResult(command: '\\frac', args: <dynamic>['1', '2']);
      expect(result.stringify(TexEncodeConf.mathConf), '\\frac{1}{2}');
    });
  });
}
