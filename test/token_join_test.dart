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

// 识别结果的 token 拼接。
//
// 模型逐 token 输出，直接首尾相接的话 `\pi` + `e` 会粘成 `\pie`——LaTeX
// 里没有这个命令，渲染和求值一起失败。键盘插入走的是同一条规则。

import 'package:flutter_test/flutter_test.dart';
import 'package:air_calculator/services/mwh_core_engine.dart';
import 'package:air_calculator/utils/latex_text.dart';

void main() {
  // 前 3 个是 special token，id 从 3 起才是真词表
  const specialN = 3;
  const vocab = ['<pad>', '<bos>', '<eos>', r'\pi', 'e', '2', '+', r'\times', 'x', r'\sin'];
  int id(String tok) => vocab.indexOf(tok);

  String join(List<String> toks) => EngineInferenceResult(
    // 首个 token 是 BOS，toRawString 会跳过
    tokenIds: [1, ...toks.map(id)],
    encMs: 0,
    prefillMs: 0,
    decMs: 0,
  ).toRawString(vocab, specialN);

  group('token 拼接', () {
    test(r'\pi + e 之间补空格', () {
      expect(join([r'\pi', 'e']), r'\pi e');
    });
    test(r'\times + x 之间补空格', () {
      expect(join([r'\times', 'x']), r'\times x');
    });
    test(r'\sin + x 之间补空格', () {
      expect(join([r'\sin', 'x']), r'\sin x');
    });
    test(r'\pi + 数字不补', () {
      expect(join([r'\pi', '2']), r'\pi2');
    });
    test(r'\pi + 运算符不补', () {
      expect(join([r'\pi', '+']), r'\pi+');
    });
    test('两个字母之间不补', () {
      expect(join(['e', 'x']), 'ex');
    });
    test(r'\pi + \sin 不补（后者以反斜杠开头）', () {
      expect(join([r'\pi', r'\sin']), r'\pi\sin');
    });
    test('单 token 原样', () {
      expect(join([r'\pi']), r'\pi');
    });
    test('空序列', () {
      expect(join([]), '');
    });
  });

  group('规则本身', () {
    test('命令名非空才算', () {
      expect(latexNeedsSeparator('\\', 'e'), isFalse);
    });
    test('已有空格时不重复补', () {
      expect(latexNeedsSeparator(r'\pi ', 'e'), isFalse);
    });
  });
}
