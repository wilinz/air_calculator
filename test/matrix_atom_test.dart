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

// 矩阵 atom 的单元格切分。
//
// 整块当叶子时渲染是对的，但光标进不去单元格。切成槽之后，切分必须只在
// 顶层发生——单元格里放分式或子矩阵，里面的 & 和 \\ 不能被当成分隔符。

import 'package:flutter_test/flutter_test.dart';
import 'package:air_calculator/pages/formula_editor_page.dart';

void main() {
  test('2×2', () {
    expect(
      matrixCellsForTest(r'\begin{vmatrix}1&2\\3&4\end{vmatrix}'),
      [
        ['1', '2'],
        ['3', '4'],
      ],
    );
  });

  test('3×3', () {
    expect(
      matrixCellsForTest(r'\begin{vmatrix}1&2&3\\4&5&6\\7&8&9\end{vmatrix}'),
      [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ],
    );
  });

  test('空模板：每格都是空槽', () {
    expect(
      matrixCellsForTest(r'\begin{vmatrix}&\\&\end{vmatrix}'),
      [
        ['', ''],
        ['', ''],
      ],
    );
  });

  test('单元格里的分式不被切碎', () {
    expect(
      matrixCellsForTest(r'\begin{vmatrix}\frac{1}{2}&2\\3&4\end{vmatrix}'),
      [
        [r'\frac{1}{2}', '2'],
        ['3', '4'],
      ],
    );
  });

  test('嵌套矩阵的分隔符不影响外层', () {
    const src =
        r'\begin{pmatrix}\begin{vmatrix}1&2\\3&4\end{vmatrix}&9\end{pmatrix}';
    expect(matrixCellsForTest(src), [
      [r'\begin{vmatrix}1&2\\3&4\end{vmatrix}', '9'],
    ]);
  });

  test('单行矩阵', () {
    expect(matrixCellsForTest(r'\begin{vmatrix}5\end{vmatrix}'), [
      ['5'],
    ]);
  });

  test('单元格槽有对应的源位置', () {
    const src = r'\begin{vmatrix}12&34\end{vmatrix}';
    final atoms = parseAtomsForTest(src);
    expect(atoms.length, 1);
    // \begin{vmatrix} 占 15 个字符，第一格从这里开始
    expect(src.substring(15, 17), '12');
  });
}
