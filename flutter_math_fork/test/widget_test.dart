// Copyright the flutter_math authors (https://github.com/znjameswu/flutter_math)
// and the flutter_math_fork maintainers (https://github.com/simpleclub/flutter_math).
// Modifications copyright 2026 wilinz.
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

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'load_fonts.dart';

void main() {
  setUpAll(loadKaTeXFonts);
  group('Flutter Math', () {
    testWidgets('Should show default error message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Math.tex(r'\Gaarbled$')),
        ),
      );
      final finder = find.byType(SelectableText);
      expect(finder, findsOneWidget);
      expect(
          (finder.evaluate().single.widget as SelectableText)
              .data!
              .startsWith('Parser Error:'),
          isTrue);
    });
    testWidgets('Should show onErrorFallback widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Math.tex(
              r'\Gaarbled$',
              onErrorFallback: (_) => SizedBox(
                width: 100,
                height: 100,
              ),
            ),
          ),
        ),
      );
      final finder = find.byType(Container);
      expect(finder, findsOneWidget);
    });
  });
}
