// Copyright 2026 wilinz.
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

/// LaTeX 文本拼接的公共规则。
library;

bool _isLetter(String c) {
  if (c.isEmpty) return false;
  final code = c.codeUnitAt(0);
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
}

/// [before] 后面直接接上 [after] 时，中间是否必须插一个空格。
///
/// LaTeX 的命令名是"反斜杠 + 尽可能长的一串字母"，所以 `\pi` 后面紧跟 `e`
/// 会被读成 `\pie` 这个并不存在的命令，渲染和求值一起失败。
///
/// 两个地方都要用：键盘插入（用户按 π 再按 e），以及识别结果的 token 拼接
/// （模型吐出 `\pi` 和 `e` 两个 token，首尾相接就粘上了）。
bool latexNeedsSeparator(String before, String after) {
  if (after.isEmpty || !_isLetter(after[0])) return false;
  int i = before.length - 1;
  while (i >= 0 && _isLetter(before[i])) {
    i--;
  }
  // 必须真的吃到了字母（命令名非空），且它们前面是反斜杠
  return i < before.length - 1 && i >= 0 && before[i] == '\\';
}
