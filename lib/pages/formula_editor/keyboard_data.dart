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

// ─── Math 键盘按钮模型 + 各分类按钮表 ────────────────────────────────────────
part of '../formula_editor_page.dart';

class _MathKey {
  final String label; // what to render on the button
  final String insert; // text to insert
  final int? cursor; // offset from insert-start for cursor; null = after
  final bool isLatex;
  final bool isBack;
  final bool isCursorMove;
  final int moveDir;

  const _MathKey(this.label, this.insert, {this.cursor})
    : isLatex = false,
      isBack = false,
      isCursorMove = false,
      moveDir = 0;

  const _MathKey.tex(this.label, this.insert, {this.cursor})
    : isLatex = true,
      isBack = false,
      isCursorMove = false,
      moveDir = 0;

  const _MathKey.back()
    : label = '⌫',
      insert = '',
      cursor = null,
      isLatex = false,
      isBack = true,
      isCursorMove = false,
      moveDir = 0;

  const _MathKey.left()
    : label = '◀',
      insert = '',
      cursor = null,
      isLatex = false,
      isBack = false,
      isCursorMove = true,
      moveDir = -1;

  const _MathKey.right()
    : label = '▶',
      insert = '',
      cursor = null,
      isLatex = false,
      isBack = false,
      isCursorMove = true,
      moveDir = 1;
}

class _Category {
  final String name;
  final IconData icon;
  final List<_MathKey> keys;
  final int cols;
  const _Category(this.name, this.icon, this.keys, {this.cols = 5});
}

// ─── Button definitions ───────────────────────────────────────────────────────

const _kBasic = [
  _MathKey('7', '7'),
  _MathKey('8', '8'),
  _MathKey('9', '9'),
  _MathKey('÷', r'\div '),
  _MathKey.back(),

  _MathKey('4', '4'),
  _MathKey('5', '5'),
  _MathKey('6', '6'),
  _MathKey('×', r'\times '),
  _MathKey('(', '('),

  _MathKey('1', '1'),
  _MathKey('2', '2'),
  _MathKey('3', '3'),
  _MathKey('−', '-'),
  _MathKey(')', ')'),

  _MathKey('0', '0'),
  _MathKey('.', '.'),
  _MathKey('+', '+'),
  _MathKey.left(),
  _MathKey.right(),
];

const _kPowerRoot = [
  _MathKey.tex(r'x^{2}', '^{2}'),
  _MathKey.tex(r'x^{3}', '^{3}'),
  _MathKey.tex(r'x^{n}', '^{}', cursor: 2),
  _MathKey.tex(r'x^{-1}', '^{-1}'),
  _MathKey.back(),

  _MathKey.tex(r'\sqrt{x}', r'\sqrt{}', cursor: 6),
  _MathKey.tex(r'\sqrt[3]{x}', r'\sqrt[3]{}', cursor: 9),
  _MathKey.tex(r'\sqrt[n]{x}', r'\sqrt[]{}', cursor: 6),
  _MathKey.tex(r'\pi', r'\pi '),
  _MathKey('e', 'e'),

  _MathKey.tex(r'e^{x}', r'e^{}', cursor: 3),
  _MathKey.tex(r'10^{x}', r'10^{}', cursor: 4),
  _MathKey.tex(r'x_{n}', r'_{}', cursor: 2),
  _MathKey.tex(r'\infty', r'\infty '),
  _MathKey.left(),
  _MathKey.right(),
];

const _kFraction = [
  _MathKey.tex(r'\frac{a}{b}', r'\frac{}{}', cursor: 6),
  _MathKey.tex(r'\frac{1}{\square}', r'\frac{1}{}', cursor: 9),
  _MathKey.tex(r'\frac{1}{2}', r'\frac{1}{2}'),
  _MathKey.tex(r'\frac{1}{3}', r'\frac{1}{3}'),
  _MathKey.back(),

  _MathKey.tex(r'\frac{1}{4}', r'\frac{1}{4}'),
  _MathKey.tex(r'\frac{3}{4}', r'\frac{3}{4}'),
  _MathKey.tex(r'\frac{2}{3}', r'\frac{2}{3}'),
  _MathKey.tex(r'\frac{3}{2}', r'\frac{3}{2}'),
  _MathKey('(', '('),

  _MathKey.tex(r'\frac{\pi}{2}', r'\frac{\pi}{2}'),
  _MathKey.tex(r'\frac{\pi}{4}', r'\frac{\pi}{4}'),
  _MathKey.tex(r'\frac{\pi}{3}', r'\frac{\pi}{3}'),
  _MathKey.tex(r'\frac{\pi}{6}', r'\frac{\pi}{6}'),
  _MathKey(')', ')'),
];

const _kTrig = [
  _MathKey.tex(r'\sin', r'\sin{}', cursor: 5),
  _MathKey.tex(r'\cos', r'\cos{}', cursor: 5),
  _MathKey.tex(r'\tan', r'\tan{}', cursor: 5),
  _MathKey.tex(r'\cot', r'\cot{}', cursor: 5),
  _MathKey.back(),

  _MathKey.tex(r'\sec', r'\sec{}', cursor: 5),
  _MathKey.tex(r'\csc', r'\csc{}', cursor: 5),
  _MathKey.tex(r'\arcsin', r'\arcsin{}', cursor: 8),
  _MathKey.tex(r'\arccos', r'\arccos{}', cursor: 8),
  _MathKey.tex(r'\arctan', r'\arctan{}', cursor: 8),

  _MathKey.tex(r'\sinh', r'\sinh{}', cursor: 6),
  _MathKey.tex(r'\cosh', r'\cosh{}', cursor: 6),
  _MathKey.tex(r'\tanh', r'\tanh{}', cursor: 6),
  _MathKey.tex(r'\pi', r'\pi '),
  _MathKey('e', 'e'),
];

const _kLog = [
  _MathKey.tex(r'\ln', r'\ln{}', cursor: 4),
  _MathKey.tex(r'\log', r'\log{}', cursor: 5),
  _MathKey.tex(r'\log_{2}', r'\log_{2}{}', cursor: 9),
  _MathKey.tex(r'\log_{10}', r'\log_{10}{}', cursor: 10),
  _MathKey.back(),

  _MathKey.tex(r'\log_{n}', r'\log_{}{}', cursor: 6),
  _MathKey.tex(r'e^{x}', r'e^{}', cursor: 3),
  _MathKey.tex(r'10^{x}', r'10^{}', cursor: 4),
  _MathKey.tex(r'\pi', r'\pi '),
  _MathKey('e', 'e'),

  _MathKey.tex(r'\infty', r'\infty '),
  _MathKey.left(),
  _MathKey.right(),
  _MathKey('(', '('),
  _MathKey(')', ')'),
];

const _kSpecial = [
  _MathKey('|x|', '||', cursor: 1),
  _MathKey.tex(r'\lfloor x \rfloor', r'\lfloor \rfloor', cursor: 8),
  _MathKey.tex(r'\lceil x \rceil', r'\lceil \rceil', cursor: 7),
  _MathKey('n!', '!'),
  _MathKey.back(),

  _MathKey.tex(r'\binom{n}{k}', r'\binom{}{}', cursor: 7),
  // 中文教材的组合数写法，与 \binom 等价；光标落在下标（总数）里
  _MathKey.tex(r'C_n^k', r'C_{}^{}', cursor: 3),
  _MathKey('%', '%'),
  _MathKey('=', '='),
  _MathKey('(', '('),

  // 2×2：光标落在左上角单元格
  _MathKey.tex(
    r'\begin{vmatrix}a&b\\c&d\end{vmatrix}',
    r'\begin{vmatrix}&\\\end{vmatrix}',
    cursor: 15,
  ),
  // 3×3
  _MathKey.tex(
    r'\begin{vmatrix}a&b&c\\d&e&f\\g&h&i\end{vmatrix}',
    r'\begin{vmatrix}&&\\&&\\&&\end{vmatrix}',
    cursor: 15,
  ),
  _MathKey.tex(r'\pi', r'\pi '),
  _MathKey('e', 'e'),
  _MathKey.tex(r'\infty', r'\infty '),
  _MathKey(')', ')'),
];

// `name` is a translation key — render with `cat.name.tr`.
const _kCategories = [
  _Category('cat_basic', Icons.grid_view, _kBasic, cols: 5),
  _Category('cat_power_root', Icons.superscript, _kPowerRoot, cols: 5),
  _Category('cat_fraction', Icons.percent, _kFraction, cols: 5),
  _Category('cat_trig', Icons.waves, _kTrig, cols: 5),
  _Category('cat_log', Icons.show_chart, _kLog, cols: 5),
  _Category('cat_other', Icons.more_horiz, _kSpecial, cols: 5),
];
