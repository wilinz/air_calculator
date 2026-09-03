// ─── LaTeX atom 树解析 ───────────────────────────────────────────────────────
// 把源 LaTeX 解析成嵌套的 atom 树。每个 atom 记录在源 LaTeX 中的位置范围。
// "槽" (Slot) 表示一个可填充的空位，记录其在源 LaTeX 中的内容范围 (open..close)，
// 包含一个子 atom 列表。
part of '../formula_editor_page.dart';

bool _isLetter(String c) {
  if (c.isEmpty) return false;
  final code = c.codeUnitAt(0);
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
}

class _Slot {
  /// 内容在源 LaTeX 中的范围（不含 `{` `}`）
  final int contentStart, contentEnd;
  final List<_Atom> children;
  const _Slot(this.contentStart, this.contentEnd, this.children);
  bool get isEmpty => children.isEmpty;
}

abstract class _Atom {
  int get srcStart;
  int get srcEnd;

  /// 为上下标包装提供：去掉脚本之前的 base 部分末尾位置
  int get baseEnd => srcEnd;
}

/// 普通字符或简单命令（无槽位）。直接交给 Math.tex 渲染。
class _LeafAtom extends _Atom {
  final String latex;
  @override
  final int srcStart;
  @override
  final int srcEnd;
  _LeafAtom(this.latex, this.srcStart, this.srcEnd);
}

/// 分式 \frac{num}{den}
class _FracAtom extends _Atom {
  final _Slot num, den;
  @override
  final int srcStart;
  @override
  final int srcEnd;
  _FracAtom(this.num, this.den, this.srcStart, this.srcEnd);
}

/// 二项式 \binom{top}{bot}
class _BinomAtom extends _Atom {
  final _Slot top, bot;
  @override
  final int srcStart;
  @override
  final int srcEnd;
  _BinomAtom(this.top, this.bot, this.srcStart, this.srcEnd);
}

/// 根式 \sqrt{content} 或 \sqrt[idx]{content}
class _SqrtAtom extends _Atom {
  final _Slot? idx; // 可空（不带次数）
  final _Slot content;
  @override
  final int srcStart;
  @override
  final int srcEnd;
  _SqrtAtom(this.idx, this.content, this.srcStart, this.srcEnd);
}

/// 上下标包装：base 后跟 ^{...} 或 _{...}（也可能两者都有）
class _ScriptAtom extends _Atom {
  final _Atom base;
  final _Slot? sup;
  final _Slot? sub;
  @override
  final int srcStart;
  @override
  final int srcEnd;
  @override
  final int baseEnd;
  _ScriptAtom(
    this.base,
    this.sup,
    this.sub,
    this.srcStart,
    this.srcEnd,
    this.baseEnd,
  );
}

/// 解析 `{...}` 内容并返回（contentStart, contentEnd, posAfter}）
({int s, int e, int after})? _readBraced(String src, int from) {
  if (from >= src.length || src[from] != '{') return null;
  int depth = 1, j = from + 1;
  final s = j;
  while (j < src.length && depth > 0) {
    if (src[j] == '{') {
      depth++;
    } else if (src[j] == '}')
      depth--;
    if (depth == 0) break;
    j++;
  }
  if (j >= src.length) return (s: s, e: src.length, after: src.length);
  return (s: s, e: j, after: j + 1);
}

/// 解析 `[...]` 内容
({int s, int e, int after})? _readBracketed(String src, int from) {
  if (from >= src.length || src[from] != '[') return null;
  int depth = 1, j = from + 1;
  final s = j;
  while (j < src.length && depth > 0) {
    if (src[j] == '[') {
      depth++;
    } else if (src[j] == ']')
      depth--;
    if (depth == 0) break;
    j++;
  }
  if (j >= src.length) return (s: s, e: src.length, after: src.length);
  return (s: s, e: j, after: j + 1);
}

/// 在 [from..to) 范围内递归解析 atoms
List<_Atom> _parseAtoms(String src, int from, int to) {
  final out = <_Atom>[];
  int i = from;

  void attachScript() {
    // 检查紧邻 `^` / `_`，把 last 包装成 _ScriptAtom
    while (i < to && (src[i] == '^' || src[i] == '_')) {
      _Slot? sup, sub;
      int? scriptEnd;
      while (i < to && (src[i] == '^' || src[i] == '_')) {
        final isSup = src[i] == '^';
        i++;
        _Slot slot;
        if (i < to && src[i] == '{') {
          final r = _readBraced(src, i)!;
          slot = _Slot(r.s, r.e, _parseAtoms(src, r.s, r.e));
          i = r.after;
        } else {
          // 单字符脚本：包装成虚拟槽（contentStart == contentEnd 表示无大括号）
          if (i < to) {
            final cStart = i;
            final children = _parseSingleAtom(src, i, to);
            i = children.isEmpty ? i + 1 : children.last.srcEnd;
            slot = _Slot(cStart, i, children);
          } else {
            slot = _Slot(i, i, const []);
          }
        }
        if (isSup) {
          sup = slot;
        } else {
          sub = slot;
        }
        scriptEnd = i;
        // 不允许脚本字符之间断开（连写 ^{2}_{3}）
        // continue to allow ^_ or _^ pairs
      }
      if (out.isNotEmpty && scriptEnd != null) {
        final base = out.removeLast();
        out.add(
          _ScriptAtom(base, sup, sub, base.srcStart, scriptEnd, base.srcEnd),
        );
      } else {
        // 不应发生，但兜底
        break;
      }
    }
  }

  while (i < to) {
    final c = src[i];

    if (c == ' ') {
      i++;
      continue;
    }

    if (c == '\\') {
      // 解析命令名
      int j = i + 1;
      while (j < to && _isLetter(src[j])) {
        j++;
      }
      // 单字符命令（如 \\, \!）
      if (j == i + 1 && j < to) j++;
      final cmd = src.substring(i + 1, j);

      // 已知带槽的结构命令
      if (cmd == 'frac' || cmd == 'binom') {
        // 跳过空白
        while (j < to && src[j] == ' ') {
          j++;
        }
        final a = _readBraced(src, j);
        int? bAfter;
        _Slot? slot1, slot2;
        if (a != null) {
          slot1 = _Slot(a.s, a.e, _parseAtoms(src, a.s, a.e));
          j = a.after;
          while (j < to && src[j] == ' ') {
            j++;
          }
          final b = _readBraced(src, j);
          if (b != null) {
            slot2 = _Slot(b.s, b.e, _parseAtoms(src, b.s, b.e));
            j = b.after;
            bAfter = b.after;
          }
        }
        if (slot1 != null && slot2 != null) {
          if (cmd == 'frac') {
            out.add(_FracAtom(slot1, slot2, i, bAfter!));
          } else {
            out.add(_BinomAtom(slot1, slot2, i, bAfter!));
          }
          i = j;
          attachScript();
          continue;
        }
        // 未匹配 → 退化为叶子
        out.add(_LeafAtom(src.substring(i, j), i, j));
        i = j;
        attachScript();
        continue;
      }

      // \begin{...matrix}...\end{...matrix} 整体作为单个叶子，
      // 否则会被拆成 \begin / & / \\ / 数字 / \end 多个原子，渲染崩坏
      if (cmd == 'begin') {
        // j 当前在 \begin 之后；要先读出环境名 {matrix}/{vmatrix}/{pmatrix}...
        while (j < to && src[j] == ' ') {
          j++;
        }
        if (j < to && src[j] == '{') {
          final envR = _readBraced(src, j);
          if (envR != null) {
            final envName = src.substring(envR.s, envR.e);
            // 找匹配的 \end{envName}
            final endPattern = '\\end{$envName}';
            final endIdx = src.indexOf(endPattern, envR.after);
            if (endIdx >= 0 && endIdx < to) {
              final wholeEnd = endIdx + endPattern.length;
              out.add(_LeafAtom(src.substring(i, wholeEnd), i, wholeEnd));
              i = wholeEnd;
              attachScript();
              continue;
            }
          }
        }
        // 未匹配 → 退化为叶子（吃掉至少 \begin{...}）
        out.add(_LeafAtom(src.substring(i, j), i, j));
        i = j;
        attachScript();
        continue;
      }

      if (cmd == 'sqrt') {
        // 可选 [idx]
        while (j < to && src[j] == ' ') {
          j++;
        }
        _Slot? idxSlot;
        final idxR = _readBracketed(src, j);
        if (idxR != null) {
          idxSlot = _Slot(idxR.s, idxR.e, _parseAtoms(src, idxR.s, idxR.e));
          j = idxR.after;
        }
        while (j < to && src[j] == ' ') {
          j++;
        }
        final cR = _readBraced(src, j);
        if (cR != null) {
          final content = _Slot(cR.s, cR.e, _parseAtoms(src, cR.s, cR.e));
          out.add(_SqrtAtom(idxSlot, content, i, cR.after));
          i = cR.after;
          attachScript();
          continue;
        }
        // 未匹配 → 退化为叶子
        out.add(_LeafAtom(src.substring(i, j), i, j));
        i = j;
        attachScript();
        continue;
      }

      // 通用命令：吞掉所有连续 {..} / [..] 参数作为整体叶子
      while (j < to && (src[j] == '{' || src[j] == '[' || src[j] == ' ')) {
        if (src[j] == ' ') {
          j++;
          continue;
        }
        final open = src[j], close = open == '{' ? '}' : ']';
        int depth = 1;
        j++;
        while (j < to && depth > 0) {
          if (src[j] == open) {
            depth++;
          } else if (src[j] == close)
            depth--;
          j++;
        }
      }
      out.add(_LeafAtom(src.substring(i, j), i, j));
      i = j;
      attachScript();
      continue;
    }

    if (c == '{') {
      // 独立花括号：作为整组叶子
      final r = _readBraced(src, i)!;
      out.add(_LeafAtom(src.substring(i, r.after), i, r.after));
      i = r.after;
      attachScript();
      continue;
    }

    if (c == '^' || c == '_') {
      // 独立脚本（前面没有 base）：作为叶子吞掉
      attachScript();
      continue;
    }

    // 普通字符
    out.add(_LeafAtom(c, i, i + 1));
    i++;
    attachScript();
  }

  return out;
}

/// 当上下标省略大括号时，读取一个最小 atom（一字符或一 \cmd）
List<_Atom> _parseSingleAtom(String src, int from, int to) {
  if (from >= to) return [];
  if (src[from] == '\\') {
    int j = from + 1;
    while (j < to && _isLetter(src[j])) {
      j++;
    }
    if (j == from + 1 && j < to) j++;
    return [_LeafAtom(src.substring(from, j), from, j)];
  }
  return [_LeafAtom(src[from], from, from + 1)];
}
