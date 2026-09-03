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

import 'package:flutter_test/flutter_test.dart';
import 'package:air_calculator/services/mathwriting_recognition_service.dart';

// 浮点比较容差
const _eps = 1e-9;
void expectNum(String? result, double expected, {double eps = _eps}) {
  expect(result, isNotNull, reason: '期望 $expected，但结果为 null');
  final v = double.tryParse(result!);
  expect(v, isNotNull, reason: '无法解析为 double: $result');
  expect(v!, closeTo(expected, eps), reason: '期望 $expected，实际 $v');
}

void main() {
  // ── 四则运算 ────────────────────────────────────────────────────────────────
  group('四则运算', () {
    test('加法', () => expectNum(evaluateLatexForTest('1+2'), 3));
    test('减法', () => expectNum(evaluateLatexForTest('10-3'), 7));
    test('乘法 ×', () => expectNum(evaluateLatexForTest('3×4'), 12));
    test('乘法 \\times', () => expectNum(evaluateLatexForTest(r'3\times4'), 12));
    test('除法 ÷', () => expectNum(evaluateLatexForTest('10÷4'), 2.5));
    test('除法 \\div', () => expectNum(evaluateLatexForTest(r'8\div2'), 4));
    test('混合运算', () => expectNum(evaluateLatexForTest('2+3×4'), 14));
    test('括号优先', () => expectNum(evaluateLatexForTest('(2+3)×4'), 20));
    test('负数', () => expectNum(evaluateLatexForTest('-3+5'), 2));
  });

  // ── 分数 ────────────────────────────────────────────────────────────────────
  group('分数 \\frac', () {
    test('整除', () => expectNum(evaluateLatexForTest(r'\frac{6}{3}'), 2));
    test('非整除', () => expectNum(evaluateLatexForTest(r'\frac{1}{4}'), 0.25));
    test(
      '分数加法',
      () => expectNum(
        evaluateLatexForTest(r'\frac{1}{2}+\frac{1}{3}'),
        5 / 6,
        eps: 1e-5,
      ),
    );
    test(
      '嵌套分数',
      () => expectNum(evaluateLatexForTest(r'\frac{\frac{1}{2}}{2}'), 0.25),
    );
    test('带分数运算', () => expectNum(evaluateLatexForTest(r'1+\frac{1}{2}'), 1.5));
  });

  // ── 根式 ────────────────────────────────────────────────────────────────────
  group('根式 \\sqrt', () {
    test('平方根', () => expectNum(evaluateLatexForTest(r'\sqrt{4}'), 2));
    test(
      '非整数根',
      () => expectNum(evaluateLatexForTest(r'\sqrt{2}'), 1.41421356, eps: 1e-6),
    );
    test('立方根', () => expectNum(evaluateLatexForTest(r'\sqrt[3]{8}'), 2));
    test('四次根', () => expectNum(evaluateLatexForTest(r'\sqrt[4]{16}'), 2));
    test('根式加法', () => expectNum(evaluateLatexForTest(r'\sqrt{9}+1'), 4));
  });

  // ── 幂 ──────────────────────────────────────────────────────────────────────
  group('幂运算 ^', () {
    test('整数幂', () => expectNum(evaluateLatexForTest(r'2^{3}'), 8));
    test('简写幂', () => expectNum(evaluateLatexForTest(r'3^2'), 9));
    test('分数幂', () => expectNum(evaluateLatexForTest(r'4^{\frac{1}{2}}'), 2));
    test('零次幂', () => expectNum(evaluateLatexForTest(r'5^{0}'), 1));
    test('负幂', () => expectNum(evaluateLatexForTest(r'2^{-1}'), 0.5));
  });

  // ── 对数 ────────────────────────────────────────────────────────────────────
  group('对数', () {
    test(
      r'\ln e',
      () => expectNum(evaluateLatexForTest(r'\ln{e}'), 1, eps: 1e-9),
    );
    test(r'\ln 1', () => expectNum(evaluateLatexForTest(r'\ln{1}'), 0));
    test(
      r'\log_{2}8',
      () => expectNum(evaluateLatexForTest(r'\log_{2}8'), 3, eps: 1e-9),
    );
    test(
      r'\log_{10}100',
      () => expectNum(evaluateLatexForTest(r'\log_{10}100'), 2, eps: 1e-9),
    );
    test(
      r'\log{100}（log10）',
      () => expectNum(evaluateLatexForTest(r'\log{100}'), 2, eps: 1e-9),
    );
    test(
      r'\log(1000)',
      () => expectNum(evaluateLatexForTest(r'\log(1000)'), 3, eps: 1e-9),
    );
    test(
      r'\log_{2}{32}',
      () => expectNum(evaluateLatexForTest(r'\log_{2}{32}'), 5, eps: 1e-9),
    );
    // 模型直接输出 lne^{3}：e^3 是 ln 的参数，ln(e^3) = 3
    test(
      'lne^{3} 合并写法',
      () => expectNum(evaluateLatexForTest(r'lne^{3}'), 3, eps: 1e-9),
    );
    // lne 无指数：ln(e) = 1
    test(
      'lne 合并写法',
      () => expectNum(evaluateLatexForTest('lne'), 1, eps: 1e-9),
    );
    // \arctan 后面跟数字（无大括号）
    test(
      r'\arctan1 无括号',
      () => expectNum(
        evaluateLatexForTest(r'\arctan1'),
        3.14159265 / 4,
        eps: 1e-6,
      ),
    );
    test(
      r'\arctan1/2 无括号除法',
      () => expectNum(
        evaluateLatexForTest(r'\arctan1/2'),
        (3.14159265 / 4) / 2,
        eps: 1e-6,
      ),
    );
  });

  // ── 三角函数 ────────────────────────────────────────────────────────────────
  group('三角函数', () {
    test(
      r'\sin 0',
      () => expectNum(evaluateLatexForTest(r'\sin{0}'), 0, eps: 1e-9),
    );
    test(
      r'\cos 0',
      () => expectNum(evaluateLatexForTest(r'\cos{0}'), 1, eps: 1e-9),
    );
    test(
      r'\sin\pi',
      () => expectNum(evaluateLatexForTest(r'\sin{\pi}'), 0, eps: 1e-9),
    );
    test(
      r'\cos\pi',
      () => expectNum(evaluateLatexForTest(r'\cos{\pi}'), -1, eps: 1e-9),
    );
    test(
      r'\tan\frac{\pi}{4}',
      () =>
          expectNum(evaluateLatexForTest(r'\tan{\frac{\pi}{4}}'), 1, eps: 1e-9),
    );
    test(
      r'\arcsin 1',
      () => expectNum(
        evaluateLatexForTest(r'\arcsin{1}'),
        3.14159265 / 2,
        eps: 1e-6,
      ),
    );
    test(
      r'\arctan 1',
      () => expectNum(
        evaluateLatexForTest(r'\arctan{1}'),
        3.14159265 / 4,
        eps: 1e-6,
      ),
    );
    test(
      r'\arccos 0',
      () => expectNum(
        evaluateLatexForTest(r'\arccos{0}'),
        3.14159265 / 2,
        eps: 1e-6,
      ),
    );
    test(
      r'\cot\frac{\pi}{4}',
      () =>
          expectNum(evaluateLatexForTest(r'\cot{\frac{\pi}{4}}'), 1, eps: 1e-6),
    );
    test(
      r'\sec 0',
      () => expectNum(evaluateLatexForTest(r'\sec{0}'), 1, eps: 1e-9),
    );
  });

  // ── 常量 ────────────────────────────────────────────────────────────────────
  group('常量', () {
    test(
      r'\pi',
      () => expectNum(evaluateLatexForTest(r'\pi'), 3.14159265, eps: 1e-6),
    );
    test(
      'e（孤立字母）',
      () => expectNum(evaluateLatexForTest('e+0'), 2.71828182, eps: 1e-6),
    );
    test(
      r'\pi × 2',
      () =>
          expectNum(evaluateLatexForTest(r'2\times\pi'), 6.28318530, eps: 1e-6),
    );
  });

  // ── 绝对值 ──────────────────────────────────────────────────────────────────
  group('绝对值', () {
    test('正数', () => expectNum(evaluateLatexForTest('|3|'), 3));
    test('负数', () => expectNum(evaluateLatexForTest('|-5|'), 5));
    test('表达式', () => expectNum(evaluateLatexForTest('|2-7|'), 5));
  });

  // ── 阶乘 ────────────────────────────────────────────────────────────────────
  group('阶乘', () {
    test('5!', () => expectNum(evaluateLatexForTest('5!'), 120));
    test('0!', () => expectNum(evaluateLatexForTest('0!'), 1));
    test('10!', () => expectNum(evaluateLatexForTest('10!'), 3628800));
  });

  // ── 百分数 ──────────────────────────────────────────────────────────────────
  group('百分数', () {
    test('50%', () => expectNum(evaluateLatexForTest('50%'), 0.5));
    test('200%', () => expectNum(evaluateLatexForTest('200%'), 2));
    test('计算', () => expectNum(evaluateLatexForTest('100×20%'), 20));
  });

  // ── 组合数 ──────────────────────────────────────────────────────────────────
  group('组合数 \\binom', () {
    test('C(4,2)', () => expectNum(evaluateLatexForTest(r'\binom{4}{2}'), 6));
    test('C(5,0)', () => expectNum(evaluateLatexForTest(r'\binom{5}{0}'), 1));
    test('C(5,5)', () => expectNum(evaluateLatexForTest(r'\binom{5}{5}'), 1));
  });

  // ── 行列式 ──────────────────────────────────────────────────────────────────
  group('行列式', () {
    test('2×2 vmatrix', () {
      expectNum(
        evaluateLatexForTest(r'\begin{vmatrix}2&3\\4&5\end{vmatrix}'),
        -2,
      );
    });
    test('2×2 竖线', () {
      expectNum(
        evaluateLatexForTest(r'|\begin{matrix}1&0\\0&1\end{matrix}|'),
        1,
      );
    });
    test('2×2 det pmatrix', () {
      expectNum(
        evaluateLatexForTest(r'\det\begin{pmatrix}3&1\\2&4\end{pmatrix}'),
        10,
      );
    });
    test('3×3', () {
      expectNum(
        evaluateLatexForTest(
          r'\begin{vmatrix}1&2&3\\4&5&6\\7&8&9\end{vmatrix}',
        ),
        0,
        eps: 1e-6,
      );
    });
    test('3×3 非零', () {
      // |2 -1 0; 1 3 -2; 0 1 4| = 2*(12+2)+1*(4-0)+0 = 28+4 = 32
      expectNum(
        evaluateLatexForTest(
          r'\begin{vmatrix}2&-1&0\\1&3&-2\\0&1&4\end{vmatrix}',
        ),
        32,
        eps: 1e-6,
      );
    });
  });

  // ── 取整 ────────────────────────────────────────────────────────────────────
  group('取整', () {
    test(
      '向下取整',
      () => expectNum(evaluateLatexForTest(r'\lfloor 3.7 \rfloor'), 3),
    );
    test(
      '向上取整',
      () => expectNum(evaluateLatexForTest(r'\lceil 3.2 \rceil'), 4),
    );
  });

  // ── 复合表达式 ───────────────────────────────────────────────────────────────
  group('复合表达式', () {
    test('分数根式', () {
      expectNum(
        evaluateLatexForTest(r'\frac{\sqrt{2}}{2}'),
        0.70710678,
        eps: 1e-6,
      );
    });
    test('幂与分数', () {
      expectNum(
        evaluateLatexForTest(r'2^{\frac{3}{2}}'),
        2.82842712,
        eps: 1e-6,
      );
    });
    test('sin²+cos²=1', () {
      expectNum(
        evaluateLatexForTest(
          r'\sin{\frac{\pi}{6}}^{2}+\cos{\frac{\pi}{6}}^{2}',
        ),
        1,
        eps: 1e-6,
      );
    });
    test('连乘', () => expectNum(evaluateLatexForTest(r'2\times3\times4'), 24));
    test('嵌套括号', () => expectNum(evaluateLatexForTest('((2+3)×(4-1))'), 15));
  });

  // ── 错误/边界 ────────────────────────────────────────────────────────────────
  group('错误输入', () {
    test('空串', () => expect(evaluateLatexForTest(''), isNull));
    test('纯空白', () => expect(evaluateLatexForTest('   '), isNull));
    test('除以零', () => expect(evaluateLatexForTest(r'\frac{1}{0}'), isNull));
  });
}
