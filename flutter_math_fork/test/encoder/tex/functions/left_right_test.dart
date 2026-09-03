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
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_math_fork/src/encoder/tex/encoder.dart';

import '../recode.dart';

void main() {
  group('LeftRight encoding test', () {
    test('general encoding', () {
      final node1 = LeftRightNode(
        leftDelim: '(',
        rightDelim: '}',
        body: [
          EquationRowNode(children: [SymbolNode(symbol: 'a')])
        ],
      );
      expect(node1.encodeTeX(), '\\left(a\\right\\}');

      const testStrings = [
        '\\left.a\\middle|b\\middle.c\\right)',
      ];
      for (final testString in testStrings) {
        expect(recodeTex(testString), testString);
      }
    });
  });
}
