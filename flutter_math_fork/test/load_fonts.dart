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

import 'dart:io';

import 'package:flutter/services.dart';

Future<void> loadKaTeXFonts() async {
  //https://github.com/flutter/flutter/issues/20907
  if (Directory.current.path.endsWith('/test') ||
      Directory.current.path.endsWith('\\test')) {
    Directory.current = Directory.current.parent;
  }

  final katexMainLoader = FontLoader('packages/flutter_math_fork/KaTeX_Main')
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Main-Regular.ttf'))
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Main-Italic.ttf'))
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Main-Bold.ttf'))
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Main-BoldItalic.ttf'));

  final katexMathLoader = FontLoader('packages/flutter_math_fork/KaTeX_Math')
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Math-Italic.ttf'))
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Math-BoldItalic.ttf'));

  final katexAMSLoader = FontLoader('packages/flutter_math_fork/KaTeX_AMS')
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_AMS-Regular.ttf'));

  final katexCaligraphicLoader = FontLoader(
      'packages/flutter_math_fork/KaTeX_Caligraphic')
    ..addFont(
        getFontData('lib/katex_fonts/fonts/KaTeX_Caligraphic-Regular.ttf'))
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Caligraphic-Bold.ttf'));

  final katexFrakturLoader = FontLoader(
      'packages/flutter_math_fork/KaTeX_Fraktur')
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Fraktur-Regular.ttf'))
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Fraktur-Bold.ttf'));

  final katexSansSerifLoader = FontLoader(
      'packages/flutter_math_fork/KaTeX_SansSerif')
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_SansSerif-Regular.ttf'))
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_SansSerif-Bold.ttf'))
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_SansSerif-Italic.ttf'));

  final katexScriptLoader = FontLoader(
      'packages/flutter_math_fork/KaTeX_Script')
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Script-Regular.ttf'));

  final katexTypewriterLoader =
      FontLoader('packages/flutter_math_fork/KaTeX_Typewriter')
        ..addFont(
            getFontData('lib/katex_fonts/fonts/KaTeX_Typewriter-Regular.ttf'));

  final katexSize1Loader = FontLoader('packages/flutter_math_fork/KaTeX_Size1')
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Size1-Regular.ttf'));

  final katexSize2Loader = FontLoader('packages/flutter_math_fork/KaTeX_Size2')
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Size2-Regular.ttf'));

  final katexSize3Loader = FontLoader('packages/flutter_math_fork/KaTeX_Size3')
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Size3-Regular.ttf'));

  final katexSize4Loader = FontLoader('packages/flutter_math_fork/KaTeX_Size4')
    ..addFont(getFontData('lib/katex_fonts/fonts/KaTeX_Size4-Regular.ttf'));

  await Future.wait([
    katexMainLoader.load(),
    katexMathLoader.load(),
    katexAMSLoader.load(),
    katexCaligraphicLoader.load(),
    katexFrakturLoader.load(),
    katexSansSerifLoader.load(),
    katexScriptLoader.load(),
    katexTypewriterLoader.load(),
    katexSize1Loader.load(),
    katexSize2Loader.load(),
    katexSize3Loader.load(),
    katexSize4Loader.load(),
  ]);
}

Future<ByteData> getFontData(String name) => File(name)
    .readAsBytes()
    .then((bytes) => ByteData.view(Uint8List.fromList(bytes).buffer));
