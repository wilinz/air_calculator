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

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_math_fork/src/ast/nodes/symbol.dart';
import 'package:flutter_math_fork/src/ast/syntax_tree.dart';
import 'package:flutter_math_fork/src/ast/types.dart';
import 'package:flutter_math_fork/src/encoder/tex/encoder.dart';
import 'package:flutter_math_fork/src/parser/tex/parser.dart';
import 'package:flutter_math_fork/src/parser/tex/settings.dart';

String recodeTexSymbol(String tex, [Mode mode = Mode.math]) {
  if (mode == Mode.text) {
    tex = '\\text{$tex}';
  }
  var node = TexParser(tex, const TexParserSettings()).parse().children.first;
  while (node is ParentableNode) {
    node = node.children.first!;
  }
  assert(node is SymbolNode);
  return node.encodeTeX(
    conf: mode == Mode.math ? TexEncodeConf.mathConf : TexEncodeConf.textConf,
  );
}

void main() {
  group('symbol encoding test', () {
    test('base math symbols', () {
      expect(recodeTexSymbol('a'), 'a');
      expect(recodeTexSymbol('0'), '0');
      expect(recodeTexSymbol('\\pm'), '\\pm');
    });

    test('base text symbols', () {
      expect(recodeTexSymbol('a', Mode.text), 'a');
      expect(recodeTexSymbol('0', Mode.text), '0');
      expect(recodeTexSymbol('\\dag', Mode.text), '\\dag');
    });

    test('escaped math symbols', () {
      expect(recodeTexSymbol('\\{'), '\\{');
      expect(recodeTexSymbol('\\}'), '\\}');
      expect(recodeTexSymbol('\\&'), '\\&');
      expect(recodeTexSymbol('\\#'), '\\#');
      expect(recodeTexSymbol('\\_'), '\\_');
    });
  });
}
