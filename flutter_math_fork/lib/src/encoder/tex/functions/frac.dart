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

EncodeResult _fracEncoder(GreenNode node) {
  final fracNode = node as FracNode;
  if (fracNode.barSize == null) {
    if (fracNode.continued) {
      return TexCommandEncodeResult(
        command: '\\cfrac',
        args: fracNode.children,
      );
    } else {
      return TexCommandEncodeResult(
        command: '\\frac',
        args: fracNode.children,
      );
    }
  } else {
    return TexCommandEncodeResult(
      command: '\\genfrac',
      args: <dynamic>[
        null,
        null,
        fracNode.barSize,
        null,
        ...fracNode.children,
      ],
    );
  }
}

final _fracOptimizationEntries = [
  // \dfrac \tfrac
  OptimizationEntry(
    matcher: isA<StyleNode>(
      matchSelf: (node) {
        final style = node.optionsDiff.style;
        return style == MathStyle.display || style == MathStyle.text;
      },
      child: isA<FracNode>(
        matchSelf: (node) => node.barSize == null,
        selfSpecificity: 110,
      ),
    ),
    optimize: (node) {
      final style = (node as StyleNode).optionsDiff.style;
      final continued = (node.children.first as FracNode).continued;
      if (style == MathStyle.text && continued) return;

      final res = TexCommandEncodeResult(
        command: style == MathStyle.display
            ? (continued ? '\\cfrac' : '\\dfrac')
            : '\\tfrac',
        args: node.children.first.children,
      );
      final remainingOptions = node.optionsDiff.removeStyle();
      texEncodingCache[node] = remainingOptions.isEmpty
          ? res
          : _optionsDiffEncode(remainingOptions, <dynamic>[res]);
    },
  ),

  // \binom
  OptimizationEntry(
    matcher: isA<LeftRightNode>(
      matchSelf: (node) => (node.leftDelim == '(' && node.rightDelim == ')'),
      child: isA<EquationRowNode>(
        child: isA<FracNode>(
          matchSelf: (node) =>
              node.continued == false && node.barSize?.value == 0,
        ),
      ),
    ),
    optimize: (node) {
      texEncodingCache[node] = TexCommandEncodeResult(
        command: '\\binom',
        args: node.children.first!.children.first!.children,
      );
    },
  ),

  // \tbinom \dbinom

  // \genfrac
  OptimizationEntry(
    matcher: isA<StyleNode>(
      matchSelf: (node) => node.optionsDiff.style != null,
      child: isA<LeftRightNode>(
        child: isA<EquationRowNode>(
          child: isA<FracNode>(
            matchSelf: (node) => node.continued == false,
          ),
        ),
      ),
    ),
    optimize: (node) {
      final leftRight = node.children.first as LeftRightNode;
      final frac = leftRight.children.first.children.first as FracNode;
      final res = TexCommandEncodeResult(
        command: '\\genfrac',
        args: <dynamic>[
          // TODO
          leftRight.leftDelim == null
              ? null
              : SymbolNode(symbol: leftRight.leftDelim!),
          leftRight.rightDelim == null
              ? null
              : SymbolNode(symbol: leftRight.rightDelim!),
          frac.barSize,
          (node as StyleNode).optionsDiff.style?.size,
          ...frac.children,
        ],
      );
      final remainingOptions = node.optionsDiff.removeStyle();
      texEncodingCache[node] = remainingOptions.isEmpty
          ? res
          : _optionsDiffEncode(remainingOptions, <dynamic>[res]);
    },
  ),
  OptimizationEntry(
    matcher: isA<StyleNode>(
      matchSelf: (node) => node.optionsDiff.style != null,
      child: isA<FracNode>(
        matchSelf: (node) => node.continued == false,
      ),
    ),
    optimize: (node) {
      final frac = node.children.first as FracNode;
      final res = TexCommandEncodeResult(
        command: '\\genfrac',
        args: <dynamic>[
          null,
          null,
          frac.barSize,
          (node as StyleNode).optionsDiff.style?.size,
          ...frac.children,
        ],
      );
      final remainingOptions = node.optionsDiff.removeStyle();
      texEncodingCache[node] = remainingOptions.isEmpty
          ? res
          : _optionsDiffEncode(remainingOptions, <dynamic>[res]);
    },
  ),
];
