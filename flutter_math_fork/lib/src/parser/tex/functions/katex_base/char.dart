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

part of '../katex_base.dart';

const _charEntries = {
  ['\\@char']:
      FunctionSpec(numArgs: 1, allowedInText: true, handler: _charHandler),
};
GreenNode _charHandler(TexParser parser, FunctionContext context) {
  final arg = assertNodeType<EquationRowNode>(
      parser.parseArgNode(mode: null, optional: false));
  final number = arg.children
      .map((child) => assertNodeType<SymbolNode>(child).symbol)
      .join('');
  final code = int.tryParse(number);
  if (code == null) {
    throw ParseException('\\@char has non-numeric argument $number');
  }
  return SymbolNode(
    symbol: String.fromCharCode(code),
    mode: parser.mode,
    overrideAtomType: AtomType.ord,
  );
}
