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

import 'size.dart';

/// Math styles for equation elements.
///
/// \displaystyle \textstyle etc.
enum MathStyle {
  display,
  displayCramped,
  text,
  textCramped,
  script,
  scriptCramped,
  scriptscript,
  scriptscriptCramped,
}

enum MathStyleDiff {
  sub,
  sup,
  fracNum,
  fracDen,
  cramp,
  text,
  uncramp,
}

MathStyle? parseMathStyle(String string) => const {
      'display': MathStyle.display,
      'displayCramped': MathStyle.displayCramped,
      'text': MathStyle.text,
      'textCramped': MathStyle.textCramped,
      'script': MathStyle.script,
      'scriptCramped': MathStyle.scriptCramped,
      'scriptscript': MathStyle.scriptscript,
      'scriptscriptCramped': MathStyle.scriptscriptCramped,
    }[string];

extension MathStyleExt on MathStyle {
  // MathStyle get pureStyle => MathStyle.values[(this.index / 2).floor()];

  bool get cramped => index.isEven;
  int get size => index ~/ 2;

  MathStyle reduce(MathStyleDiff? diff) =>
      diff == null ? this : MathStyle.values[_reduceTable[diff.index][index]];

  static const _reduceTable = [
    [4, 5, 4, 5, 6, 7, 6, 7], //sup
    [5, 5, 5, 5, 7, 7, 7, 7], //sub
    [2, 3, 4, 5, 6, 7, 6, 7], //fracNum
    [3, 3, 5, 5, 7, 7, 7, 7], //fracDen
    [1, 1, 3, 3, 5, 5, 7, 7], //cramp
    [0, 1, 2, 3, 2, 3, 2, 3], //text
    [0, 0, 2, 2, 4, 4, 6, 6], //uncramp
  ];
  MathStyle sup() => reduce(MathStyleDiff.sup);
  MathStyle sub() => reduce(MathStyleDiff.sub);
  MathStyle fracNum() => reduce(MathStyleDiff.fracNum);
  MathStyle fracDen() => reduce(MathStyleDiff.fracDen);
  MathStyle cramp() => reduce(MathStyleDiff.cramp);
  MathStyle atLeastText() => reduce(MathStyleDiff.text);
  MathStyle uncramp() => reduce(MathStyleDiff.uncramp);

  // MathStyle atLeastText() =>
  //     this.index > MathStyle.textCramped.index ? this : MathStyle.text;

  bool operator >(MathStyle other) => index < other.index;
  bool operator <(MathStyle other) => index > other.index;
  bool operator >=(MathStyle other) => index <= other.index;
  bool operator <=(MathStyle other) => index >= other.index;
  bool isTight() => size >= 2;
}

extension MathStyleExtOnInt on int {
  MathStyle toMathStyle() => MathStyle.values[(this * 2).clamp(0, 6).toInt()];
}

extension MathStyleExtOnSize on MathSize {
  /// katex/src/Options.js/sizeStyleMap
  MathSize underStyle(MathStyle style) {
    if (style >= MathStyle.textCramped) {
      return this;
    }
    return MathSize.values[_sizeStyleMap[index][style.size - 1] - 1];
  }

  static const _sizeStyleMap = [
    [1, 1, 1],
    [2, 1, 1],
    [3, 1, 1],
    [4, 2, 1],
    [5, 2, 1],
    [6, 3, 1],
    [7, 4, 2],
    [8, 6, 3],
    [9, 7, 6],
    [10, 8, 7],
    [11, 10, 9],
  ];
}
