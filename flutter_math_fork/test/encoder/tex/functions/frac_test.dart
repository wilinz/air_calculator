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

import '../recode.dart';

void main() {
  group('frac encoding test', () {
    test('base frac encoding', () {
      expect(recodeTex('\\frac{a}{b}'), '\\frac{a}{b}');
      expect(recodeTex('\\cfrac{a}{b}'), '\\cfrac{a}{b}');
      expect(recodeTex('\\genfrac{}{}{1.0pt}{}{a}{b}'),
          '\\genfrac{}{}{1.0pt}{}{a}{b}');
    });

    test('frac optimization', () {
      expect(recodeTex('\\dfrac{a}{b}'), '\\dfrac{a}{b}');
      expect(recodeTex('\\tfrac{a}{b}'), '\\tfrac{a}{b}');
      expect(recodeTex('\\binom{a}{b}'), '\\binom{a}{b}');
      expect(recodeTex('\\genfrac{(}{\\}}{0.0pt}{0}{a}{b}'),
          '\\genfrac{(}{\\}}{0.0pt}{0}{a}{b}');
      expect(recodeTex('\\genfrac{}{}{0.0pt}{0}{a}{b}'),
          '\\genfrac{}{}{0.0pt}{0}{a}{b}');
    });
  });
}
