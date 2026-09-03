// 退格在结构边界上的落点。
//
// 光标停在一个槽的起点时，退格不删字符，只挪光标。挪到哪里决定了能不能
// 把结构里的内容逐个删掉：必须先退到同一结构的**前一个槽**的末尾，全部
// 槽都走完了才跳出整个结构。

import 'package:flutter_test/flutter_test.dart';
import 'package:air_calculator/pages/formula_editor_page.dart';

void main() {
  group(r'\sin{\frac{\pi}{2}}', () {
    // 索引：\sin{ = 0..4，\frac{ = 5..10，\pi = 11..13，}{ = 14..15，2 = 16
    const src = r'\sin{\frac{\pi}{2}}';

    test('分母起点 → 退到分子末尾，而不是跳出 \\sin', () {
      final denStart = src.indexOf('{2}') + 1;
      final r = backspaceProbeForTest(src, denStart);
      expect(r.inSlot, isTrue);
      expect(r.deleteAtom, isFalse);
      // 分子内容是 \pi，落点应当是它的末尾
      expect(r.caret, src.indexOf(r'\pi') + r'\pi'.length);
    });

    test('分子起点 → 跳出分式（分式是函数参数槽里唯一的 atom）', () {
      final numStart = src.indexOf(r'\pi');
      final r = backspaceProbeForTest(src, numStart);
      expect(r.inSlot, isTrue);
      expect(r.deleteAtom, isFalse);
      expect(r.caret, src.indexOf(r'\frac'));
    });

    test('函数参数槽起点 → 跳到 \\sin 之前', () {
      final argStart = src.indexOf('{') + 1;
      final r = backspaceProbeForTest(src, argStart);
      expect(r.caret, 0);
    });
  });

  test('全空的结构 → 整体删除', () {
    const src = r'\frac{}{}';
    final r = backspaceProbeForTest(src, src.indexOf('}{') + 2);
    expect(r.inSlot, isTrue);
    expect(r.deleteAtom, isTrue);
  });

  test('分子有内容、分母空 → 不删结构，退到分子末尾', () {
    const src = r'\frac{5}{}';
    final r = backspaceProbeForTest(src, src.length - 1);
    expect(r.deleteAtom, isFalse);
    expect(r.caret, src.indexOf('5') + 1);
  });

  test(r'\sqrt[3]{8}：内容起点退到次数末尾', () {
    const src = r'\sqrt[3]{8}';
    final r = backspaceProbeForTest(src, src.indexOf('8'));
    expect(r.caret, src.indexOf('3') + 1);
  });

  test('矩阵：第二格起点退到第一格末尾', () {
    const src = r'\begin{vmatrix}1&2\\3&4\end{vmatrix}';
    final r = backspaceProbeForTest(src, src.indexOf('2'));
    expect(r.caret, src.indexOf('1') + 1);
  });

  test('矩阵：第二行第一格起点退到上一行最后一格末尾', () {
    const src = r'\begin{vmatrix}1&2\\3&4\end{vmatrix}';
    final r = backspaceProbeForTest(src, src.indexOf('3'));
    expect(r.caret, src.indexOf('2') + 1);
  });

  test('矩阵：第一格起点跳出整个矩阵', () {
    const src = r'\begin{vmatrix}1&2\\3&4\end{vmatrix}';
    final r = backspaceProbeForTest(src, src.indexOf('1'));
    expect(r.caret, 0);
  });

  test('光标不在槽起点时不归这条逻辑管', () {
    const src = r'\frac{12}{3}';
    final r = backspaceProbeForTest(src, src.indexOf('2') + 1);
    expect(r.inSlot, isFalse);
  });

  _slotLeafDeletion();
}

// ── 命令叶子在槽里也要整体删除 ────────────────────────────────────────
//
// 顶层原先按 atom 整体删，槽内部却是无脑删一个字符，于是 \pi 在顶层一下
// 删干净，放进 \frac{\pi}{2} 却被削成 \p。多字母命令全都一样。
void _slotLeafDeletion() {
  group('多字母命令在槽里整体删除', () {
    ({String text, int caret}) bs(String src, int at) =>
        backspaceApplyForTest(src, at);

    test(r'顶层 \pi 一次删净', () {
      final r = bs(r'1+\pi', 5);
      expect(r.text, '1+');
    });

    test(r'\frac{\pi}{2} 的分子里 \pi 也一次删净', () {
      const src = r'\frac{\pi}{2}';
      final r = bs(src, src.indexOf(r'\pi') + 3);
      expect(r.text, r'\frac{}{2}');
    });

    test(r'\times 在槽里不被削成 \time', () {
      const src = r'\frac{2\times3}{4}';
      final r = bs(src, src.indexOf(r'\times') + 6);
      expect(r.text, r'\frac{23}{4}');
    });

    test(r'\infty 在槽里整体删', () {
      const src = r'\frac{\infty}{2}';
      final r = bs(src, src.indexOf(r'\infty') + 6);
      expect(r.text, r'\frac{}{2}');
    });

    test('矩阵单元格里的命令整体删', () {
      const src = r'\begin{vmatrix}\pi&2\\3&4\end{vmatrix}';
      final r = bs(src, src.indexOf(r'\pi') + 3);
      expect(r.text, r'\begin{vmatrix}&2\\3&4\end{vmatrix}');
    });

    test('槽里的普通数字仍逐字符删', () {
      const src = r'\frac{12}{3}';
      final r = bs(src, src.indexOf('2') + 1);
      expect(r.text, r'\frac{1}{3}');
    });
  });
}
