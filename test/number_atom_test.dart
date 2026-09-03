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

// 数字必须逐字符成 atom。
//
// 光标停靠点是按 atom 之间生成的（_buildSlotRow 里每个 atom 后面挂一个
// _airCursorStop），所以把 300 合成一个 atom 就只剩首尾两个停靠点，
// 中间插不进光标。小数点显示成点乘那个问题不能靠合并数字来解决，
// 改在渲染层给 `.` 撑一个和数字等高的盒子并底对齐。

import 'package:flutter_test/flutter_test.dart';
import 'package:air_calculator/pages/formula_editor_page.dart';

void main() {
  group('逐位成 atom', () {
    test('300', () {
      expect(atomShapeForTest('300'), [
        ('leaf', '3'),
        ('leaf', '0'),
        ('leaf', '0'),
      ]);
    });
    test('466', () {
      expect(atomShapeForTest('466').length, 3);
    });
    test('小数', () {
      expect(atomShapeForTest('3.14'), [
        ('leaf', '3'),
        ('leaf', '.'),
        ('leaf', '1'),
        ('leaf', '4'),
      ]);
    });
    test('矩阵单元格里同样逐位', () {
      expect(matrixCellsForTest(r'\begin{vmatrix}300&2\end{vmatrix}'), [
        ['300', '2'],
      ]);
      // 单元格的槽内部仍然是三个 atom
      expect(atomShapeForTest('300').length, 3);
    });
  });

  group('删除', () {
    test('300 退一次剩 30', () {
      expect(backspaceApplyForTest('300', 3).text, '30');
    });
    test('3.14 退一次剩 3.1', () {
      expect(backspaceApplyForTest('3.14', 4).text, '3.1');
    });
    test('数字中间退格删左边那位', () {
      expect(backspaceApplyForTest('1234', 2).text, '134');
    });
    test('命令仍整体删', () {
      expect(backspaceApplyForTest(r'\pi', 3).text, '');
    });
    test('花括号组整体删', () {
      expect(backspaceApplyForTest('{12}', 4).text, '');
    });
  });
}
