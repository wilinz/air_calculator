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

EncodeResult _accentUnderEncoder(GreenNode node) {
  final accentNode = node as AccentUnderNode;
  final label = accentNode.label;
  final command = accentUnderMapping.entries
      .firstWhereOrNull((entry) => entry.value == label)
      ?.key;
  return command == null
      ? NonStrictEncodeResult(
          'unknown accent_under',
          'No strict match for accent_under symbol under math mode: '
              '${unicodeLiteral(accentNode.label)}',
        )
      : TexCommandEncodeResult(
          command: command,
          args: accentNode.children,
        );
}
