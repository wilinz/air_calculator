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

/// 一元函数带花括号参数：\sin{...}、\ln{...}…
///
/// 不这么做的话它会落进"通用命令吞掉所有 {..} 参数当整体叶子"那条分支，
/// 于是 \sin{\frac{\pi}{2}} 里的分式没有槽，光标进不去；而不带花括号的
/// \sin\frac{\pi}{2} 反倒是好的，两种写法行为不一致。
class _FuncAtom extends _Atom {
  /// 不含反斜杠的命令名
  final String cmd;
  final _Slot arg;
  @override
  final int srcStart;
  @override
  final int srcEnd;
  _FuncAtom(this.cmd, this.arg, this.srcStart, this.srcEnd);
}

/// 参数带槽的一元函数。列表之外的命令仍按整体叶子处理。
const _kSlottedFuncs = {
  'sin', 'cos', 'tan',
  'arcsin', 'arccos', 'arctan',
  'sinh', 'cosh', 'tanh',
  'cot', 'sec', 'csc',
  'ln', 'lg', 'log', 'exp',
};

/// 矩阵环境 \begin{env}a&b\\c&d\end{env}
///
/// 每个单元格是一个槽，光标可以进去编辑。整块当叶子的话渲染是对的，
/// 但光标进不去单元格，只能整体删掉重写。
class _MatrixAtom extends _Atom {
  /// 环境名，决定左右定界符：vmatrix→竖线、pmatrix→圆括号、
  /// bmatrix→方括号、Vmatrix→双竖线、matrix→无
  final String env;

  /// 按行存的单元格
  final List<List<_Slot>> rows;
  @override
  final int srcStart;
  @override
  final int srcEnd;
  _MatrixAtom(this.env, this.rows, this.srcStart, this.srcEnd);
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
              if (envName.endsWith('matrix')) {
                out.add(
                  _MatrixAtom(
                    envName,
                    _parseMatrixCells(src, envR.after, endIdx),
                    i,
                    wholeEnd,
                  ),
                );
              } else {
                // 非矩阵环境（cases、align…）暂不支持编辑，整块当叶子
                out.add(_LeafAtom(src.substring(i, wholeEnd), i, wholeEnd));
              }
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

      // 已知一元函数 + 花括号参数 → 参数成槽
      if (_kSlottedFuncs.contains(cmd)) {
        int k = j;
        while (k < to && src[k] == ' ') {
          k++;
        }
        final argR = _readBraced(src, k);
        if (argR != null) {
          out.add(
            _FuncAtom(
              cmd,
              _Slot(argR.s, argR.e, _parseAtoms(src, argR.s, argR.e)),
              i,
              argR.after,
            ),
          );
          i = argR.after;
          attachScript();
          continue;
        }
        // 没跟花括号（\sin\frac{}{} 或 \sin^2 x）→ 落回下面的通用处理
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

/// 把矩阵体 [from..to) 按行列切成单元格槽。
///
/// 只在顶层切：花括号内部和嵌套的 \begin…\end 里的 `&` `\\` 不算分隔符，
/// 否则单元格里放个分式或子矩阵就会被切碎。
List<List<_Slot>> _parseMatrixCells(String src, int from, int to) {
  final rows = <List<_Slot>>[];
  var row = <_Slot>[];
  int cellStart = from;
  int brace = 0, env = 0;
  int j = from;

  void closeCell(int end) {
    row.add(_Slot(cellStart, end, _parseAtoms(src, cellStart, end)));
  }

  while (j < to) {
    final c = src[j];
    if (c == '{') {
      brace++;
      j++;
      continue;
    }
    if (c == '}') {
      if (brace > 0) brace--;
      j++;
      continue;
    }
    if (c == '\\') {
      // 行分隔 \\
      if (j + 1 < to && src[j + 1] == '\\') {
        if (brace == 0 && env == 0) {
          closeCell(j);
          rows.add(row);
          row = <_Slot>[];
          j += 2;
          cellStart = j;
          continue;
        }
        j += 2;
        continue;
      }
      // 命令：记嵌套环境的深度
      int k = j + 1;
      while (k < to && _isLetter(src[k])) {
        k++;
      }
      final cmd = src.substring(j + 1, k);
      if (cmd == 'begin') env++;
      if (cmd == 'end' && env > 0) env--;
      j = k > j + 1 ? k : j + 2;
      continue;
    }
    if (c == '&' && brace == 0 && env == 0) {
      closeCell(j);
      j++;
      cellStart = j;
      continue;
    }
    j++;
  }
  closeCell(to);
  rows.add(row);
  return rows;
}

// ── 槽位查询（纯函数，放这里才好测）────────────────────────────────────

/// 列出 atom 的所有可编辑槽（递归到 ScriptAtom 的 base）
List<_Slot> _slotsOf(_Atom atom) {
  if (atom is _FracAtom) return [atom.num, atom.den];
  if (atom is _BinomAtom) return [atom.top, atom.bot];
  if (atom is _SqrtAtom) {
    return [if (atom.idx != null) atom.idx!, atom.content];
  }
  if (atom is _FuncAtom) return [atom.arg];
  // 按行优先展平：光标在单元格间的移动顺序就是阅读顺序
  if (atom is _MatrixAtom) {
    return [for (final row in atom.rows) ...row];
  }
  if (atom is _ScriptAtom) {
    return [
      ..._slotsOf(atom.base),
      if (atom.sup != null) atom.sup!,
      if (atom.sub != null) atom.sub!,
    ];
  }
  return const [];
}

bool _isAtomEmpty(_Atom atom) {
  final slots = _slotsOf(atom);
  if (slots.isEmpty) return false;
  return slots.every((s) => s.children.isEmpty);
}

/// 在 atoms（递归）中找包含 cursor 的最深一层槽
({_Slot slot, _Atom atom})? _findEnclosingSlot(
  List<_Atom> atoms,
  int cursor,
) {
  for (final atom in atoms) {
    for (final slot in _slotsOf(atom)) {
      if (cursor >= slot.contentStart && cursor <= slot.contentEnd) {
        final deeper = _findEnclosingSlot(slot.children, cursor);
        if (deeper != null) return deeper;
        return (slot: slot, atom: atom);
      }
    }
  }
  return null;
}

/// 在 [at] 处插入 [text] 之前，是否需要先补一个空格。
/// 规则见 utils/latex_text.dart，识别结果的 token 拼接用的是同一条。
bool needsSpaceBeforeInsert(String src, int at, String text) =>
    latexNeedsSeparator(src.substring(0, at), text);

/// 退格时光标左邻的东西该怎么处理，在同一层的兄弟 atom 列表里判断。
///
/// 返回 (start, end, caret)：把 [start,end) 删掉、光标落到 caret；
/// start == end 表示不删字符，只挪光标。
///
/// 顶层和槽内部必须共用这一套。原先只有顶层按 atom 整体删除，槽内部是
/// 无脑删一个字符，于是 \pi 在顶层一下删干净，放进 \frac{\pi}{2} 却被
/// 削成 \p——\times、\infty、\sqrt 这些多字母命令全都一样。
({int start, int end, int caret}) _backspaceInSiblings(
  List<_Atom> siblings,
  int pos,
) {
  _Atom? left;
  for (final atom in siblings) {
    if (atom.srcEnd == pos) {
      left = atom;
      break;
    }
  }
  if (left != null) {
    final slots = _slotsOf(left);
    if (slots.isNotEmpty && !_isAtomEmpty(left)) {
      // 有内容的结构：先进最后一个非空槽，让用户继续编辑内部
      final lastNonEmpty = slots.lastWhere(
        (sl) => sl.children.isNotEmpty,
        orElse: () => slots.last,
      );
      return (start: pos, end: pos, caret: lastNonEmpty.contentEnd);
    }
    // 整体删除：空结构，或 \pi / \times 这类命令叶子，或单字符
    return (start: left.srcStart, end: left.srcEnd, caret: left.srcStart);
  }
  // 左邻不是一个完整 atom（例如光标在多字符叶子中间）：退一个字符
  return (start: pos - 1, end: pos, caret: pos - 1);
}

/// 测试入口：给定 LaTeX 与光标位置，返回退格后的完整文本与新光标。
({String text, int caret}) backspaceApplyForTest(String src, int cursor) {
  final tree = _parseAtoms(src, 0, src.length);
  final hit = _findEnclosingSlot(tree, cursor);

  if (hit != null) {
    if (cursor == hit.slot.contentStart) {
      final target = _backspaceAtSlotStart(hit.atom, hit.slot);
      if (target == null) {
        return (
          text: src.replaceRange(hit.atom.srcStart, hit.atom.srcEnd, ''),
          caret: hit.atom.srcStart,
        );
      }
      return (text: src, caret: target);
    }
    final r = _backspaceInSiblings(hit.slot.children, cursor);
    return (text: src.replaceRange(r.start, r.end, ''), caret: r.caret);
  }

  final r = _backspaceInSiblings(tree, cursor);
  return (text: src.replaceRange(r.start, r.end, ''), caret: r.caret);
}

/// 光标停在某个槽的起点时，退格该做什么。
///
/// 返回 null 表示"整个结构都空了，删掉它"；否则返回光标要去的新位置。
///
/// 关键是同一结构里还有前一个槽时要退到那个槽的末尾，继续往回删。直接跳到
/// 结构之前的话，`\sin{\frac{\pi}{2}}` 删掉分母的 2 之后，下一次退格就
/// 越过分子里的 π 一路跳到 \sin 前面，中间的内容再也删不掉。
int? _backspaceAtSlotStart(_Atom atom, _Slot slot) {
  if (_isAtomEmpty(atom)) return null;
  final slots = _slotsOf(atom);
  final idx = slots.indexOf(slot);
  if (idx > 0) return slots[idx - 1].contentEnd;
  return atom.srcStart;
}

/// 测试入口：给定完整 LaTeX 与光标位置，返回退格的落点。
/// 光标不在任何槽的起点时返回 (inSlot: false)。
({bool inSlot, bool deleteAtom, int? caret}) backspaceProbeForTest(
  String src,
  int cursor,
) {
  final tree = _parseAtoms(src, 0, src.length);
  final hit = _findEnclosingSlot(tree, cursor);
  if (hit == null || cursor != hit.slot.contentStart) {
    return (inSlot: false, deleteAtom: false, caret: null);
  }
  final target = _backspaceAtSlotStart(hit.atom, hit.slot);
  return (inSlot: true, deleteAtom: target == null, caret: target);
}

/// 测试入口：解析整串。`part of` 的文件没法只对测试开放，索性明说。
List<_Atom> parseAtomsForTest(String src) => _parseAtoms(src, 0, src.length);

/// 测试入口：列出顶层每个 atom 的类型名与源文本，用来断言"有没有被切出槽"。
List<(String, String)> atomShapeForTest(String src) {
  String kind(_Atom a) => switch (a) {
    _LeafAtom() => 'leaf',
    _FracAtom() => 'frac',
    _BinomAtom() => 'binom',
    _SqrtAtom() => 'sqrt',
    _ScriptAtom() => 'script',
    _MatrixAtom() => 'matrix',
    _FuncAtom() => 'func',
    _ => 'other',
  };
  return [
    for (final a in parseAtomsForTest(src))
      (kind(a), src.substring(a.srcStart, a.srcEnd)),
  ];
}

/// 测试入口：一元函数 atom 的参数槽里解析出了几个子 atom。
/// 0 表示参数没被切成槽（光标进不去）。
int funcArgAtomCountForTest(String src) {
  final f = parseAtomsForTest(src).whereType<_FuncAtom>().first;
  return f.arg.children.length;
}

/// 测试入口：列出一个矩阵 atom 每个单元格的源文本。
List<List<String>> matrixCellsForTest(String src) {
  final atoms = parseAtomsForTest(src);
  final m = atoms.whereType<_MatrixAtom>().first;
  return [
    for (final row in m.rows)
      [for (final c in row) src.substring(c.contentStart, c.contentEnd)],
  ];
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
