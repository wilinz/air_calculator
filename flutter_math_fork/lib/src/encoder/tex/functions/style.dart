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

part of '../functions.dart';

EncodeResult _styleEncoder(GreenNode node) {
  final styleNode = node as StyleNode;
  return _optionsDiffEncode(styleNode.optionsDiff, styleNode.children);
}

EncodeResult _optionsDiffEncode(OptionsDiff diff, List<dynamic> children) {
  EncodeResult res = TransparentTexEncodeResult(children);

  if (diff.size != null) {
    final sizeCommand = _sizeCommands[diff.size];
    res = TexModeCommandEncodeResult(
      command: sizeCommand ?? '\\tiny',
      children: <dynamic>[res],
    );
    if (sizeCommand == null) {
      res = NonStrictEncodeResult(
        'imprecise size',
        'Non-strict MethSize encountered during TeX encoding: '
            '${diff.size}',
        res,
      );
    }
  }

  if (diff.style != null) {
    final styleCommand = _styleCommands[diff.style];
    res = TexModeCommandEncodeResult(
      command: styleCommand ?? _styleCommands[diff.style!.uncramp()]!,
      children: <dynamic>[res],
    );
    if (styleCommand == null) {
      NonStrictEncodeResult(
        'imprecise style',
        'Non-strict MathStyle encountered during TeX encoding: '
            '${diff.style}',
        res,
      );
    }
  }

  if (diff.textFontOptions != null) {
    final command = texTextFontOptions.entries
        .firstWhereOrNull((entry) => entry.value == diff.textFontOptions)
        ?.key;
    if (command == null) {
      res = NonStrictEncodeResult(
        'unknown font',
        'Unrecognized text font encountered during TeX encoding: '
            '${diff.textFontOptions}',
        res,
      );
    } else {
      res = TexCommandEncodeResult(
        command: command,
        args: <dynamic>[res],
      );
    }
  }

  if (diff.mathFontOptions != null) {
    final command = texMathFontOptions.entries
        .firstWhereOrNull((entry) => entry.value == diff.mathFontOptions)
        ?.key;
    if (command == null) {
      res = NonStrictEncodeResult(
        'unknown font',
        'Unrecognized math font encountered during TeX encoding: '
            '${diff.mathFontOptions}',
        res,
      );
    } else {
      res = TexCommandEncodeResult(
        command: command,
        args: <dynamic>[res],
      );
    }
  }
  if (diff.color != null) {
    res = TexCommandEncodeResult(
      command: '\\textcolor',
      args: <dynamic>[
        '#${diff.color!.value.toRadixString(16).padLeft(6, '0')}',
        res,
      ],
    );
  }
  return res;
}

const _styleCommands = {
  MathStyle.display: '\\displaystyle',
  MathStyle.text: '\\textstyle',
  MathStyle.script: '\\scriptstyle',
  MathStyle.scriptscript: '\\scriptscriptstyle'
};

const _sizeCommands = {
  MathSize.tiny: '\\tiny',
  MathSize.size2: '\\tiny',
  MathSize.scriptsize: '\\scriptsize',
  MathSize.footnotesize: '\\footnotesize',
  MathSize.small: '\\small',
  MathSize.normalsize: '\\normalsize',
  MathSize.large: '\\large',
  MathSize.Large: '\\Large',
  MathSize.LARGE: '\\LARGE',
  MathSize.huge: '\\huge',
  MathSize.HUGE: '\\HUGE',
};
