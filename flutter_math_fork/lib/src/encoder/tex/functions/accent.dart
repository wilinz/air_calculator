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

EncodeResult _accentEncoder(GreenNode node) {
  final accentNode = node as AccentNode;

  final commandCandidates = accentCommandMapping.entries
      .where((entry) => entry.value == accentNode.label)
      .map((entry) => entry.key)
      .toList(growable: false);

  final textCommandCandidates = commandCandidates
      .where((candidate) => functions[candidate]?.allowedInText == true);

  final mathCommandCandidates = commandCandidates
      .where((candidate) => functions[candidate]?.allowedInMath == true);

  if (commandCandidates.isEmpty) {
    return NonStrictEncodeResult(
      'unknown accent',
      'Unrecognized accent symbol encountered during TeX encoding: '
          '${unicodeLiteral(accentNode.label)}',
      encodeTex(node.children.first),
    );
  }

  bool isCommandMatched(String command) =>
      accentNode.isStretchy == !nonStretchyAccents.contains(command) &&
      accentNode.isShifty ==
          (!accentNode.isStretchy || shiftyAccents.contains(command));

  final mathCommand = mathCommandCandidates.firstWhereOrNull(isCommandMatched);

  final math = mathCommand != null
      ? TexCommandEncodeResult(command: mathCommand, args: node.children)
      : mathCommandCandidates.firstOrNull != null
          ? NonStrictEncodeResult(
              'imprecise accent',
              'No strict match for accent symbol under math mode: '
                  '${unicodeLiteral(accentNode.label)}, '
                  '${accentNode.isStretchy ? '' : 'not '}stretchy and '
                  '${accentNode.isShifty ? '' : 'not '}shifty',
              TexCommandEncodeResult(
                command: mathCommandCandidates.first,
                args: node.children,
              ),
            )
          : NonStrictEncodeResult(
              'unknown accent',
              'No strict match for accent symbol under math mode: '
                  '${unicodeLiteral(accentNode.label)}, '
                  '${accentNode.isStretchy ? '' : 'not '}stretchy and '
                  '${accentNode.isShifty ? '' : 'not '}shifty',
              TexCommandEncodeResult(
                  command: commandCandidates.first, args: node.children),
            );

  final textCommand =
      accentNode.isStretchy == false && accentNode.isShifty == true
          ? textCommandCandidates.firstOrNull
          : null;

  final text = textCommand != null
      ? TexCommandEncodeResult(command: textCommand, args: node.children)
      : textCommandCandidates.firstOrNull != null
          ? NonStrictEncodeResult(
              'imprecise accent',
              'No strict match for accent symbol under text mode: '
                  '${unicodeLiteral(accentNode.label)}, '
                  '${accentNode.isStretchy ? '' : 'not '}stretchy and '
                  '${accentNode.isShifty ? '' : 'not '}shifty',
              TexCommandEncodeResult(
                command: textCommandCandidates.first,
                args: node.children,
              ),
            )
          : NonStrictEncodeResult(
              'unknown accent',
              'No strict match for accent symbol under text mode: '
                  '${unicodeLiteral(accentNode.label)}, '
                  '${accentNode.isStretchy ? '' : 'not '}stretchy and '
                  '${accentNode.isShifty ? '' : 'not '}shifty',
              TexCommandEncodeResult(
                  command: commandCandidates.first, args: node.children),
            );

  return ModeDependentEncodeResult(
    math: math,
    text: text,
  );
}
