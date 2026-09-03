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

EncodeResult _leftRightEncoder(GreenNode node) {
  final leftRightNode = node as LeftRightNode;
  final left = _delimEncoder(leftRightNode.leftDelim);
  final right = _delimEncoder(leftRightNode.rightDelim);
  final middles =
      leftRightNode.middle.map(_delimEncoder).toList(growable: false);
  return TransparentTexEncodeResult(<dynamic>[
    '\\left',
    left,
    ...leftRightNode.body.first.children,
    for (var i = 1; i < leftRightNode.body.length; i++) ...[
      '\\middle',
      middles[i - 1],
      ...leftRightNode.body[i].children,
    ],
    '\\right',
    right,
  ]);
}

EncodeResult _delimEncoder(String? delim) {
  if (delim == null) return StaticEncodeResult('.');
  final result = _baseSymbolEncoder(delim, Mode.math);
  return result != null
      ? delimiterCommands.contains(result)
          ? StaticEncodeResult(result)
          : NonStrictEncodeResult.string(
              'illegal delimiter',
              'Non-delimiter symbol ${unicodeLiteral(delim)} '
                  'occured as delimiter',
              result,
            )
      : NonStrictEncodeResult.string(
          'unknown symbol',
          'Unrecognized symbol encountered during TeX encoding: '
              '${unicodeLiteral(delim)} with mode Math',
          '.',
        );
}
