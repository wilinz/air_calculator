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

final _code0 = '0'.codeUnitAt(0);

final _code9 = '9'.codeUnitAt(0);

final _codeA = 'A'.codeUnitAt(0);

final _codeZ = 'Z'.codeUnitAt(0);

final _codea = 'a'.codeUnitAt(0);

final _codez = 'z'.codeUnitAt(0);

bool isAlphaNumericUnit(String symbol) {
  assert(symbol.length == 1);
  final code = symbol.codeUnitAt(0);
  return (code >= _code0 && code <= _code9) ||
      (code >= _codeA && code <= _codeZ) ||
      (code >= _codea && code <= _codez);
}
