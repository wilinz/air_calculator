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

import 'helper.dart';
import 'load_fonts.dart';

void main() {
  setUpAll(loadKaTeXFonts);

  testTexToMatchGoldenFile(
    'Solution of quadratic equation',
    r'x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}',
    location: '../doc/img/delta.png',
    scale: 5,
  );
  testTexToMatchGoldenFile(
    'Schrodinger equation',
    r'i\hbar\frac{\partial}{\partial t}\Psi(\vec x,t) = -\frac{\hbar}{2m}\nabla^2\Psi(\vec x,t)+V(\vec x)\Psi(\vec x,t)',
    location: '../doc/img/schrodinger.png',
    scale: 5,
  );
  testTexToMatchGoldenFile(
    'Fourier transform',
    r'\hat f(\xi) = \int_{-\infty}^{+\infty}{f(x)e^{-2\pi i \xi x}\mathrm{d}x}',
    location: '../doc/img/fourier.png',
    scale: 5,
  );
}
