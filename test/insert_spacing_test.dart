// 插入时不能把字母粘到左边的命令名上。
//
// \pi 后面紧跟 e 会变成 \pie——LaTeX 里没有这个命令，渲染报错、求值也认
// 不出来。键盘的 π 键靠尾随空格避开，但那个空格被删掉、或光标移回命令
// 正后方时就会粘上。

import 'package:flutter_test/flutter_test.dart';
import 'package:air_calculator/pages/formula_editor_page.dart';

void main() {
  group('需要补空格', () {
    test(r'\pi 后面插入 e', () {
      expect(needsSpaceBeforeInsert(r'\pi', 3, 'e'), isTrue);
    });
    test(r'\times 后面插入字母', () {
      expect(needsSpaceBeforeInsert(r'2\times', 7, 'x'), isTrue);
    });
    test(r'\pi 后面插入函数命令', () {
      // \sin 以反斜杠开头，不是字母，不会粘
      expect(needsSpaceBeforeInsert(r'\pi', 3, r'\sin'), isFalse);
    });
  });

  group('不需要补空格', () {
    test('数字后面插入字母', () {
      expect(needsSpaceBeforeInsert('12', 2, 'e'), isFalse);
    });
    test('裸字母后面插入字母（不构成命令）', () {
      expect(needsSpaceBeforeInsert('ab', 2, 'c'), isFalse);
    });
    test(r'\pi 和光标之间已有空格', () {
      expect(needsSpaceBeforeInsert(r'\pi ', 4, 'e'), isFalse);
    });
    test('插入的是数字', () {
      expect(needsSpaceBeforeInsert(r'\pi', 3, '2'), isFalse);
    });
    test('插入的是运算符', () {
      expect(needsSpaceBeforeInsert(r'\pi', 3, '+'), isFalse);
    });
    test('串首插入', () {
      expect(needsSpaceBeforeInsert('', 0, 'e'), isFalse);
    });
    test('反斜杠正后方（命令名还没有字母）', () {
      expect(needsSpaceBeforeInsert('\\', 1, 'e'), isFalse);
    });
    test('插入空串', () {
      expect(needsSpaceBeforeInsert(r'\pi', 3, ''), isFalse);
    });
  });
}
