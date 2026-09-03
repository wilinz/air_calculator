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

void main() {
  group('accent encoding test', () {
    test('general encoding math', () {
      final bar = AccentUnderNode(
        base: EquationRowNode.empty(),
        label: '\u00AF',
      );
      expect(bar.encodeTeX(), '\\underline{}');
    });
  });
}
