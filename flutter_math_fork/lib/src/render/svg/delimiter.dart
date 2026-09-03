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

import '../../ast/options.dart';
import '../../ast/size.dart';
import '../../ast/style.dart';
import '../../ast/symbols/symbols.dart';
import '../../ast/types.dart';
import '../../font/metrics/font_metrics.dart';
import '../../utils/unicode_literal.dart';

class DelimiterConf {
  final FontOptions font;
  final MathStyle style;

  const DelimiterConf(this.font, this.style);
}

const mainRegular = FontOptions(fontFamily: 'Main');
const size1Regular = FontOptions(fontFamily: 'Size1');
const size2Regular = FontOptions(fontFamily: 'Size2');
const size3Regular = FontOptions(fontFamily: 'Size3');
const size4Regular = FontOptions(fontFamily: 'Size4');

const stackNeverDelimiterSequence = [
  DelimiterConf(mainRegular, MathStyle.scriptscript),
  DelimiterConf(mainRegular, MathStyle.script),
  DelimiterConf(mainRegular, MathStyle.text),
  DelimiterConf(size1Regular, MathStyle.text),
  DelimiterConf(size2Regular, MathStyle.text),
  DelimiterConf(size3Regular, MathStyle.text),
  DelimiterConf(size4Regular, MathStyle.text),
];

const stackAlwaysDelimiterSequence = [
  DelimiterConf(mainRegular, MathStyle.scriptscript),
  DelimiterConf(mainRegular, MathStyle.script),
  DelimiterConf(mainRegular, MathStyle.text),
];

const stackLargeDelimiterSequence = [
  DelimiterConf(mainRegular, MathStyle.scriptscript),
  DelimiterConf(mainRegular, MathStyle.script),
  DelimiterConf(mainRegular, MathStyle.text),
  DelimiterConf(size1Regular, MathStyle.text),
  DelimiterConf(size2Regular, MathStyle.text),
  DelimiterConf(size3Regular, MathStyle.text),
  DelimiterConf(size4Regular, MathStyle.text),
];

double getHeightForDelim({
  required String delim,
  required String fontName,
  required MathStyle style,
  required MathOptions options,
}) {
  final char = symbolRenderConfigs[delim]?.math?.replaceChar ?? delim;
  final metrics =
      getCharacterMetrics(character: char, fontName: fontName, mode: Mode.math);
  if (metrics == null) {
    throw StateError('Illegal delimiter char $delim'
        '(${unicodeLiteral(delim)}) appeared in AST');
  }
  final fullHeight = metrics.height + metrics.depth;
  final newOptions = options.havingStyle(style);
  return fullHeight.cssEm.toLpUnder(newOptions);
}
