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

import 'package:flutter_math_fork/src/ast/nodes/frac.dart';
import 'package:flutter_math_fork/src/ast/nodes/symbol.dart';
import 'package:flutter_math_fork/tex.dart';
import 'package:flutter_test/flutter_test.dart' hide isA, isNull;

import 'package:flutter_math_fork/src/encoder/matcher.dart';

void main() {
  group('Matcher test', () {
    test('null matcher', () {
      expect(isNull.match(null), true);
      expect(isNull.match(EquationRowNode.empty()), false);
    });

    test('node matcher', () {
      final target = TexParser('\\frac{123}{abc}', TexParserSettings())
          .parse()
          .children
          .first;
      expect(isA<FracNode>().match(target), true);
      expect(isA<EquationRowNode>().match(target), false);

      expect(
        isA(children: [
          isA<EquationRowNode>(),
          isA<EquationRowNode>(),
          isA<EquationRowNode>(),
        ]).match(target),
        false,
      );
      expect(
        isA(children: [
          isA<EquationRowNode>(),
          isNull,
        ]).match(target),
        false,
      );

      expect(isA(child: isA<EquationRowNode>()).match(target), false);

      expect(isA(firstChild: isA<FracNode>()).match(target), false);

      expect(isA(lastChild: isA<FracNode>()).match(target), false);

      expect(isA(anyChild: isA<FracNode>()).match(target), false);

      expect(
        isA(
          everyChild: isA<EquationRowNode>(
            anyChild: isA<SymbolNode>(matchSelf: (node) => node.symbol == '1'),
          ),
        ).match(target),
        false,
      );

      final completeMacher = isA<FracNode>(
        matchSelf: (node) => node.barSize == null,
        selfSpecificity: 1,
        children: [
          isA<EquationRowNode>(),
          isA<EquationRowNode>(),
        ],
        firstChild: isA<EquationRowNode>(),
        lastChild: isA<EquationRowNode>(),
        anyChild: isA<EquationRowNode>(),
        everyChild: isA<EquationRowNode>(),
      );
      expect(
        completeMacher.specificity,
        3 * isA<EquationRowNode>().specificity +
            isA<FracNode>().specificity +
            1,
      );

      expect(completeMacher.match(target), true);
    });
  });
}
