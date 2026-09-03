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

EncodeResult _naryEncoder(GreenNode node) {
  final naryNode = node as NaryOperatorNode;
  final command = _naryOperatorMapping[naryNode.operator];
  if (command == null) {
    return NonStrictEncodeResult(
      'unknown Nary opertor',
      'Unknown Nary opertor symbol ${unicodeLiteral(naryNode.operator)} '
          'encountered during encoding.',
    );
  }
  return TransparentTexEncodeResult(<dynamic>[
    TexMultiscriptEncodeResult(
      base: naryNode.limits != null
          ? '$command\\${naryNode.limits! ? '' : 'no'}limits'
          : command,
      sub: naryNode.lowerLimit,
      sup: naryNode.upperLimit,
    ),
    naryNode.naryand,
  ]);
}

// Dart compiler bug here. Cannot set it to const
final _naryOperatorMapping = {
  ...singleCharBigOps,
  ...singleCharIntegrals,
};
