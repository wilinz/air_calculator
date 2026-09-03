// 一元函数的参数槽。
//
// \sin{...} 原先落进"通用命令吞掉所有 {..} 参数当整体叶子"的分支，参数里
// 的分式没有槽、光标进不去；而不带花括号的 \sin\frac{\pi}{2} 反倒正常。
// 两种写法必须行为一致。

import 'package:flutter_test/flutter_test.dart';
import 'package:air_calculator/pages/formula_editor_page.dart';

void main() {
  test('\\sin{\\frac{\\pi}{2}} 的参数是槽', () {
    expect(funcArgAtomCountForTest(r'\sin{\frac{\pi}{2}}'), 1);
    expect(atomShapeForTest(r'\sin{\frac{\pi}{2}}'), [
      ('func', r'\sin{\frac{\pi}{2}}'),
    ]);
  });

  test('不带花括号的写法仍然把分式解析成独立 atom', () {
    expect(atomShapeForTest(r'\sin\frac{\pi}{2}'), [
      ('leaf', r'\sin'),
      ('frac', r'\frac{\pi}{2}'),
    ]);
  });

  test('空参数是空槽而不是叶子', () {
    expect(funcArgAtomCountForTest(r'\sin{}'), 0);
    expect(atomShapeForTest(r'\sin{}'), [('func', r'\sin{}')]);
  });

  test('各函数都认', () {
    for (final f in ['cos', 'tan', 'ln', 'exp', 'arctan', 'tanh']) {
      expect(atomShapeForTest('\\$f{1}').first.$1, 'func', reason: f);
    }
  });

  test('\\log_{2}3 的下标不受影响', () {
    // \log 后面跟的是 _ 不是 {，走通用分支 + attachScript
    final shape = atomShapeForTest(r'\log_{2}3');
    expect(shape.first.$1, 'script');
  });

  test('\\sin^2{x} 的上标仍走 script 包装', () {
    expect(atomShapeForTest(r'\sin^2{1}').first.$1, 'script');
  });

  test('未闭合花括号不崩', () {
    expect(() => atomShapeForTest(r'\sin{1'), returnsNormally);
  });

  test('用户报的整条式子里两种写法都有槽', () {
    const src =
        r'\sqrt{2}+4^{2}+78+\log_{2}3+74+89+\sin{\frac{\pi}{2}}+\sin\frac{\pi}{2}';
    final shape = atomShapeForTest(src);
    // 带花括号的那个是 func（有槽），不带的是 leaf + frac
    expect(shape.where((e) => e.$1 == 'func').length, 1);
    expect(shape.where((e) => e.$1 == 'frac').length, 1);
    expect(funcArgAtomCountForTest(src), 1);
  });
}
