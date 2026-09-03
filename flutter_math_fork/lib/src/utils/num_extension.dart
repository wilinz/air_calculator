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

import 'dart:math' as math;

extension IntExt on int {
  int clampInt(int lowerLimit, int upperLimit) {
    assert(upperLimit >= lowerLimit);
    if (this < lowerLimit) return lowerLimit;
    if (this > upperLimit) return upperLimit;
    return this;
  }
}

@pragma('dart2js:tryInline')
@pragma('vm:prefer-inline')
T max3<T extends num>(T a, T b, T c) => math.max(math.max(a, b), c);
