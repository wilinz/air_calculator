// 识别后处理的回归测试。
//
// 这些替换是给手写识别兜底的（计算器场景里没有变量，所以裸 x 一律当乘号），
// 但它们必须只作用在算式上，不能碰 LaTeX 的结构性标识符。

import 'package:flutter_test/flutter_test.dart';
import 'package:air_calculator/pages/formula_editor_page.dart';

void main() {
  group('常见错字修正', () {
    test('裸 x → \\times', () {
      expect(postProcessMathForTest('2x3'), r'2 \times 3');
    });
    test('大写 X 同样处理', () {
      expect(postProcessMathForTest('2X3'), r'2 \times 3');
    });
    test('q → 9', () => expect(postProcessMathForTest('1+q'), '1+9'));
    test('T → +', () => expect(postProcessMathForTest('1T2'), '1+2'));
    test('希腊字母 → 数字', () {
      expect(postProcessMathForTest('ψ+δ'), '4+6');
    });
    test('\\times 命令本身不受影响', () {
      expect(postProcessMathForTest(r'2\times3'), r'2\times3');
    });
    test('\\xi 这类含 x 的命令不受影响', () {
      expect(postProcessMathForTest(r'\xi+1'), r'\xi+1');
    });
  });

  group('环境名必须原样保留', () {
    // 之前 \begin{matrix} 里的 x 被换成 \times，环境名一坏，
    // 渲染和求值同时失败。
    test('matrix', () {
      const src = r'|\begin{matrix}2&9\\3&6\end{matrix}|';
      expect(postProcessMathForTest(src), src);
    });
    test('vmatrix', () {
      const src = r'\begin{vmatrix}1&2\\3&4\end{vmatrix}';
      expect(postProcessMathForTest(src), src);
    });
    test('pmatrix 配 \\det', () {
      const src = r'\det\begin{pmatrix}1&2\\3&4\end{pmatrix}';
      expect(postProcessMathForTest(src), src);
    });
    test('环境内的算式照常修正', () {
      expect(
        postProcessMathForTest(r'\begin{vmatrix}2x3&1\\0&1\end{vmatrix}'),
        r'\begin{vmatrix}2 \times 3&1\\0&1\end{vmatrix}',
      );
    });
    test('未闭合的环境名不能吞掉后面全部内容', () {
      // 花括号没闭合时只抄到串尾，不崩
      expect(postProcessMathForTest(r'\begin{matrix'), r'\begin{matrix');
    });
  });
}
