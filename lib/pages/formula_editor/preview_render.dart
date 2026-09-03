// ─── 公式预览渲染（atoms → widgets，含光标插入）─────────────────────────
part of '../formula_editor_page.dart';

extension _PreviewRender on _FormulaEditorPageState {
  Widget _buildPreview() {
    final tree = _parseAtoms(_latex.text, 0, _latex.text.length);
    final cursorSrc = _latex.selection.isValid
        ? _latex.selection.start
        : _latex.text.length;

    final formulaArea = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setSrcCursor(_latex.text.length),
      child: SingleChildScrollView(
        controller: _previewScroll,
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.only(bottom: 6),
          child: _latex.text.isEmpty
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BlinkingCursor(active: true, color: _Pal.cursor),
                    SizedBox(width: 6),
                    Text(
                      'tap_keyboard_input'.tr,
                      style: TextStyle(color: _fgWeak, fontSize: 18),
                    ),
                  ],
                )
              : _buildSlotRow(
                  tree,
                  rowStart: 0,
                  rowEnd: _latex.text.length,
                  cursor: cursorSrc,
                  fontSize: 32,
                ),
        ),
      ),
    );

    if (_isLandscapeAir) {
      // 横屏：左公式编辑，右计算结果（bg 交给外层统一 0.4）。
      return Container(
        key: _previewKey,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: formulaArea),
            const SizedBox(width: 12),
            Container(
              width: 1,
              color: _Pal.divider.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 220,
              child: _calcResult.isEmpty
                  ? Center(
                      child: Text(
                        '= ?',
                        style: TextStyle(color: _fgWeak, fontSize: 18),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(
                              _calcResult,
                              style: TextStyle(
                                color: _airMode ? Colors.white : _Pal.accent,
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        _air(
                          'result:clear',
                          () => setState(() => _calcResult = ''),
                          IconButton(
                            onPressed: () => setState(() => _calcResult = ''),
                            icon: Icon(Icons.close, color: _fgMuted, size: 18),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: _previewKey,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120, maxHeight: 240),
      decoration: BoxDecoration(color: _airBg(_Pal.previewBg)),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      clipBehavior: Clip.hardEdge,
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          formulaArea,
          // 分割线 + 进度条滚动指示（视口宽度，不随内容滚动）
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _previewScroll,
              builder: (_, __) {
                double progress = 0;
                // 旋转切换瞬间会同时挂着新旧树，positions.length 可能 >1，
                // 直接访问 .position 会断言失败，跳过即可。
                if (_previewScroll.positions.length == 1) {
                  final pos = _previewScroll.position;
                  if (pos.hasContentDimensions && pos.hasPixels && pos.maxScrollExtent > 0) {
                    progress = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
                  }
                }
                return SizedBox(
                  height: 1,
                  child: LayoutBuilder(
                    builder: (_, constraints) {
                      final w = constraints.maxWidth;
                      final trackColor = _airMode
                        ? Colors.white.withValues(alpha: 0.15)
                        : _Pal.divider;
                      final thumbColor = _airMode
                        ? Colors.white.withValues(alpha: 0.75)
                        : _Pal.cursor.withValues(alpha: 0.75);
                      if (_previewScroll.positions.length != 1) {
                        return ColoredBox(color: trackColor);
                      }
                      final pos2 = _previewScroll.position;
                      if (!pos2.hasContentDimensions || !pos2.hasPixels || pos2.maxScrollExtent <= 0) {
                        return ColoredBox(color: trackColor);
                      }
                      final thumbW = (w * pos2.viewportDimension / (pos2.maxScrollExtent + pos2.viewportDimension)).clamp(20.0, w);
                      final thumbX = (w - thumbW) * progress;
                      return Stack(fit: StackFit.expand, children: [
                        ColoredBox(color: trackColor),
                        Positioned(
                          left: thumbX,
                          width: thumbW,
                          top: 0,
                          bottom: 0,
                          child: ColoredBox(color: thumbColor),
                        ),
                      ]);
                    },
                  ),
                );
              },
            ),
          ),
          // 语音状态行
          if (_voiceStatus().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: AppGlyphText(
                _voiceStatus(),
                style: TextStyle(
                  color: _voiceRecording ? Colors.redAccent : _fgMuted,
                  fontSize: 12,
                ),
              ),
            ),
          // 计算结果行
          if (_calcResult.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Row(
                children: [
                  Text(
                    _calcResult,
                    style: TextStyle(
                      color: _airMode ? Colors.white : _Pal.accent,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  _air(
                    'result:clear',
                    () => setState(() => _calcResult = ''),
                    IconButton(
                      onPressed: () => setState(() => _calcResult = ''),
                      icon: Icon(Icons.close, color: _fgMuted, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      ),
    );
  }

  // ── 光标滑动条 ────────────────────────────────────────────────────────

  /// 收集所有合法的"光标停靠点"（去重排序）：每个 row/slot 的 atom 边界。
  List<int> _collectStops(List<_Atom> atoms, int rowStart, int rowEnd) {
    final stops = <int>{rowStart, rowEnd};
    for (final atom in atoms) {
      stops
        ..add(atom.srcStart)
        ..add(atom.srcEnd);
      for (final slot in _slotsOf(atom)) {
        stops.addAll(
          _collectStops(slot.children, slot.contentStart, slot.contentEnd),
        );
      }
    }
    return stops.toList()..sort();
  }

  void _moveCursorByStop(int dir) {
    final tree = _parseAtoms(_latex.text, 0, _latex.text.length);
    final stops = _collectStops(tree, 0, _latex.text.length);
    if (stops.length < 2) return;
    final cur =
        (_latex.selection.isValid ? _latex.selection.start : _latex.text.length)
            .clamp(0, _latex.text.length);

    int idx = stops.indexOf(cur);
    if (idx < 0) {
      // 若当前位置不在 stops 中（理论不该发生），找最近的
      int best = 0, dist = (cur - stops[0]).abs();
      for (int i = 1; i < stops.length; i++) {
        final d = (cur - stops[i]).abs();
        if (d < dist) {
          dist = d;
          best = i;
        }
      }
      idx = best;
    }
    final newIdx = (idx + dir).clamp(0, stops.length - 1);
    _setSrcCursor(stops[newIdx]);
  }

  Widget _buildCursorDragBar() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _dragAccum = 0,
      onHorizontalDragUpdate: (details) {
        _dragAccum += details.delta.dx;
        while (_dragAccum.abs() >= _FormulaEditorPageState._kPxPerStep) {
          final dir = _dragAccum > 0 ? 1 : -1;
          _moveCursorByStop(dir);
          _dragAccum -= dir * _FormulaEditorPageState._kPxPerStep;
        }
      },
      onHorizontalDragEnd: (_) => _dragAccum = 0,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          // 横屏由外层统一 bg
          color: _isLandscapeAir ? Colors.transparent : _airBg(_Pal.appBar),
          border: const Border(
            top: BorderSide(color: _Pal.divider, width: 1),
            bottom: BorderSide(color: _Pal.divider, width: 1),
          ),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: _airMode ? _screenSize.width * 0.72 : double.infinity,
            child: Row(
              children: [
                // ◀ 单击：往左一步
                _arrowBtn(Icons.chevron_left, () => _moveCursorByStop(-1)),
                // 中间：拖动区
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Icon(Icons.drag_handle, color: _fgWeak, size: 16),
                        // SizedBox(width: 8),
                        Text(
                          'swipe_to_move_cursor'.tr,
                          style: TextStyle(color: _fgMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                _arrowBtn(Icons.chevron_right, () => _moveCursorByStop(1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _arrowBtn(IconData icon, VoidCallback onTap) {
    return _air(
      'arrow:${icon.codePoint}',
      onTap,
      InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 36,
          child: Icon(icon, color: _fgMuted, size: 22),
        ),
      ),
    );
  }

  // ── 基础符号工具栏（始终显示，独立于 tab 之外） ─────────────────────
  Widget _buildQuickToolbar() {
    final inner = Container(
      height: 48,
      padding: EdgeInsets.zero,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: _airMode ? _screenSize.width * 0.72 : double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                Expanded(child: _quickKey('+', '+')),
                _quickGap(),
                Expanded(child: _quickKey('−', '-')),
                _quickGap(),
                Expanded(child: _quickKey('×', r'\times ')),
                _quickGap(),
                Expanded(child: _quickKey('÷', r'\div ')),
                _quickGap(),
                Expanded(child: _quickKey('(', '(')),
                _quickGap(),
                Expanded(child: _quickKey(')', ')')),
                _quickGap(),
                // 撤销：把算式回退到上一次。空中模式不放——那边这栏只有 72%
                // 宽，且 _buildAirActionRow 已经有撤销/撤全部/撤公式三个了。
                if (!_airMode) ...[
                  Expanded(child: _quickUndoBtn()),
                  _quickGap(),
                ],
                // 退格
                Expanded(
                  child: _quickIconBtn(
                    Icons.backspace_outlined,
                    _airMode ? Colors.white : _Pal.accent,
                    _backspace,
                  ),
                ),
                _quickGap(),
                // 清空整个公式
                Expanded(child: _quickClearBtn()),
                _quickGap(),
                // = 计算：放在 C 右侧，所有模式都显示
                _quickDivider(),
                _quickGap(),
                Expanded(child: _quickCalcBtn()),
              ],
            ),
          ),
        ),
      ),
    );

    if (_airMode) {
      return Stack(
        children: [
          // 横屏由外层统一 bg
          if (!_isLandscapeAir)
            Positioned.fill(child: ColoredBox(color: _airBg(_Pal.scaffold))),
          inner,
        ],
      );
    }
    return inner;
  }

  Widget _quickGap() => const SizedBox(width: 4);

  Widget _quickDivider() => SizedBox(
        width: 1,
        height: 24,
        child: DecoratedBox(
          decoration: BoxDecoration(color: _Pal.divider),
        ),
      );

  Widget _quickCalcBtn() {
    final disabled = _latex.text.trim().isEmpty || _busy;
    return _air(
      'qcalc',
      disabled ? null : _calculateNow,
      _quickKeyShell(
        onTap: disabled ? null : _calculateNow,
        child: Text(
          '=',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: disabled
                ? _Pal.textWeak
                : (_airMode ? Colors.white : _Pal.accent),
          ),
        ),
      ),
    );
  }

  Widget _quickKey(String label, String insert) {
    final isOp = '÷×−+()='.contains(label);
    onTap() => _onKey(_MathKey(label, insert));
    return _air(
      'qkey:$label',
      onTap,
      _quickKeyShell(
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(
            color: isOp
                ? (_airMode ? Colors.white : _Pal.operator)
                : _fgText,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _quickUndoBtn() {
    final disabled = _latexUndo.isEmpty || _busy;
    return _air(
      'qicon:undoLatex',
      disabled ? null : _undoLatex,
      _quickKeyShell(
        onTap: disabled ? null : _undoLatex,
        child: Icon(
          Icons.undo,
          size: 20,
          color: disabled
              ? _Pal.textWeak
              : (_airMode ? Colors.white : _Pal.accent),
        ),
      ),
    );
  }

  Widget _quickClearBtn() {
    final isEmpty = _latex.text.isEmpty;
    final color = isEmpty
        ? _Pal.textWeak
        : (_airMode ? Colors.white : _Pal.accent);
    onTap() {
      _latex.clear();
      setState(() => _calcResult = '');
    }
    return _air(
      'qicon:clear',
      isEmpty ? null : onTap,
      _quickKeyShell(
        onTap: isEmpty ? null : onTap,
        child: Text(
          'C',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _quickIconBtn(IconData icon, Color iconColor, VoidCallback? onTap) {
    return _air(
      'qicon:${icon.codePoint}',
      onTap,
      _quickKeyShell(
        onTap: onTap,
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }

  /// 与下方键盘网格按钮同款的 shell：Material elevation + 圆角，无 border、无外层背景。
  Widget _quickKeyShell({required VoidCallback? onTap, required Widget child}) {
    return Material(
      color: _airBg(_Pal.keyBg, alpha: 0.4),
      elevation: 0.5,
      shadowColor: _Pal.keyShadow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        splashColor: _Pal.divider,
        highlightColor: _Pal.divider,
        onTap: onTap,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  /// 把一个槽（atoms + 内容范围）渲染成横向 Row，原子之间夹光标条。
  /// air mode 下把 BlinkingCursor 包一层 AirClickable，让空中指针可以点击移动光标
  Widget _airCursorStop(int srcPos, bool active, double height) {
    final cursor = _BlinkingCursor(
      active: active,
      color: _Pal.cursor,
      height: height,
    );
    if (!_airMode) return cursor;
    return AirClickable(
      id: 'cursor:$srcPos',
      controller: _airClick,
      onTap: () => _setSrcCursor(srcPos),
      child: cursor,
    );
  }

  Widget _buildSlotRow(
    List<_Atom> atoms, {
    required int rowStart,
    required int rowEnd,
    required int cursor,
    required double fontSize,
    bool placeholderIfEmpty = false,
  }) {
    if (atoms.isEmpty) {
      // 空槽：显示占位框（除非外层已经显示）
      final inThis = cursor >= rowStart && cursor <= rowEnd;
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (inThis)
            _airCursorStop(rowStart, true, fontSize * 1.1),
          if (placeholderIfEmpty || !inThis)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _setSrcCursor(rowStart),
              child: Container(
                width: fontSize * 0.7,
                height: fontSize * 0.9,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _fgPH,
                    width: 1.2,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      );
    }

    // 非空：用 atoms 边界作为光标停靠点
    final children = <Widget>[];
    children.add(_airCursorStop(rowStart, cursor == rowStart, fontSize * 1.1));
    for (final atom in atoms) {
      children.add(_buildAtomWidget(atom, cursor, fontSize));
      children.add(_airCursorStop(atom.srcEnd, cursor == atom.srcEnd, fontSize * 1.1));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }

  /// 根据 atom 类型分发到不同渲染器
  Widget _buildAtomWidget(_Atom atom, int cursor, double fontSize) {
    if (atom is _LeafAtom) {
      return _buildLeaf(atom, fontSize);
    }
    if (atom is _FracAtom) {
      return _buildFrac(atom, cursor, fontSize);
    }
    if (atom is _BinomAtom) {
      return _buildBinom(atom, cursor, fontSize);
    }
    if (atom is _SqrtAtom) {
      return _buildSqrt(atom, cursor, fontSize);
    }
    if (atom is _ScriptAtom) {
      return _buildScript(atom, cursor, fontSize);
    }
    if (atom is _MatrixAtom) {
      return _buildMatrix(atom, cursor, fontSize);
    }
    if (atom is _FuncAtom) {
      return _buildFunc(atom, cursor, fontSize);
    }
    return Text(
      atom.toString(),
      style: const TextStyle(color: Colors.red, fontSize: 12),
    );
  }

  Widget _buildLeaf(_LeafAtom atom, double fontSize) {
    return Builder(
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          final box = ctx.findRenderObject() as RenderBox?;
          if (box == null) return;
          final isLeft = details.localPosition.dx < box.size.width / 2;
          _setSrcCursor(isLeft ? atom.srcStart : atom.srcEnd);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: _sizedLikeDigit(
            atom.latex,
            fontSize,
            Math.tex(
              atom.latex,
            textStyle: TextStyle(color: _fgFormula, fontSize: fontSize),
              onErrorFallback: (_) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: _Pal.errorBg,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  atom.latex,
                  style: const TextStyle(
                    color: _Pal.error,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 小数点等矮字形的基线修正。
  ///
  /// 每个字符是独立的 Math.tex（逐字符成 atom 才有逐位的光标停靠点），
  /// 而外层 Row 是 CrossAxisAlignment.center——`.` 的字形盒子只有一点点
  /// 高，被垂直居中之后就跑到中间去了，看着像点乘。
  ///
  /// 这里给它撑一个和数字等高的盒子并底对齐，等价于放回基线上。撑高用
  /// 一个透明的 `0`，跟着字体走，不用手算行高。
  Widget _sizedLikeDigit(String latex, double fontSize, Widget child) {
    if (latex != '.') return child;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Opacity(
          opacity: 0,
          child: Math.tex(
            '0',
            textStyle: TextStyle(color: _fgFormula, fontSize: fontSize),
          ),
        ),
        child,
      ],
    );
  }

  /// 分式：上下两槽 + 中间分数线
  Widget _buildFrac(_FracAtom atom, int cursor, double fontSize) {
    final inSlotSize = fontSize * 0.85;
    final num = _buildSlotRow(
      atom.num.children,
      rowStart: atom.num.contentStart,
      rowEnd: atom.num.contentEnd,
      cursor: cursor,
      fontSize: inSlotSize,
      placeholderIfEmpty: true,
    );
    final den = _buildSlotRow(
      atom.den.children,
      rowStart: atom.den.contentStart,
      rowEnd: atom.den.contentEnd,
      cursor: cursor,
      fontSize: inSlotSize,
      placeholderIfEmpty: true,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: num,
          ),
          Container(
            height: 1.5,
            constraints: BoxConstraints(minWidth: inSlotSize * 0.8),
            color: _fgFracBar,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: den,
          ),
        ],
      ),
    );
  }

  /// 一元函数：函数名 + 参数槽。
  ///
  /// 不额外加括号——LaTeX 里 \sin{\frac{\pi}{2}} 本来就渲染成 sin 紧跟一个
  /// 分式，加了反而和不带花括号的写法长得不一样。
  Widget _buildFunc(_FuncAtom atom, int cursor, double fontSize) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 1, right: 2),
          child: Math.tex(
            '\\${atom.cmd}',
            textStyle: TextStyle(color: _fgFormula, fontSize: fontSize),
            onErrorFallback: (_) => Text(
              atom.cmd,
              style: TextStyle(color: _fgFormula, fontSize: fontSize),
            ),
          ),
        ),
        _buildSlotRow(
          atom.arg.children,
          rowStart: atom.arg.contentStart,
          rowEnd: atom.arg.contentEnd,
          cursor: cursor,
          fontSize: fontSize,
          placeholderIfEmpty: true,
        ),
      ],
    );
  }

  /// 矩阵：单元格网格 + 按环境名选定界符。
  ///
  /// 定界符用 IntrinsicHeight 撑满整个网格高度，而不是按行数估字号——
  /// 单元格里放了分式的时候估算会明显对不齐。
  Widget _buildMatrix(_MatrixAtom atom, int cursor, double fontSize) {
    final inSize = fontSize * 0.9;
    final grid = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final row in atom.rows)
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final cell in row)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  child: _buildSlotRow(
                    cell.children,
                    rowStart: cell.contentStart,
                    rowEnd: cell.contentEnd,
                    cursor: cursor,
                    fontSize: inSize,
                    placeholderIfEmpty: true,
                  ),
                ),
            ],
          ),
      ],
    );

    final (left, right) = _matrixDelims(atom.env);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (left != null) _matrixDelim(left, fontSize),
            grid,
            if (right != null) _matrixDelim(right, fontSize),
          ],
        ),
      ),
    );
  }

  /// 环境名 → 左右定界符。null 表示不画（matrix 环境本身没有括号）。
  (String?, String?) _matrixDelims(String env) => switch (env) {
    'vmatrix' => ('|', '|'),
    'Vmatrix' => ('‖', '‖'),
    'pmatrix' => ('(', ')'),
    'bmatrix' => ('[', ']'),
    'Bmatrix' => ('{', '}'),
    _ => (null, null),
  };

  Widget _matrixDelim(String ch, double fontSize) {
    // 竖线画成实心细条，用字符会随字体在不同高度下断开
    if (ch == '|' || ch == '‖') {
      final bars = ch == '|' ? 1 : 2;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var k = 0; k < bars; k++)
              Container(
                width: 1.5,
                margin: EdgeInsets.only(left: k == 0 ? 0 : 2),
                color: _fgFormula,
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: FittedBox(
        fit: BoxFit.fitHeight,
        child: Text(
          ch,
          style: TextStyle(color: _fgFormula, fontSize: fontSize),
        ),
      ),
    );
  }

  /// 二项式：上下两槽 + 大括号
  Widget _buildBinom(_BinomAtom atom, int cursor, double fontSize) {
    final inSlotSize = fontSize * 0.85;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '(',
            style: TextStyle(color: _fgFormula, fontSize: fontSize * 1.6),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSlotRow(
                atom.top.children,
                rowStart: atom.top.contentStart,
                rowEnd: atom.top.contentEnd,
                cursor: cursor,
                fontSize: inSlotSize,
                placeholderIfEmpty: true,
              ),
              const SizedBox(height: 2),
              _buildSlotRow(
                atom.bot.children,
                rowStart: atom.bot.contentStart,
                rowEnd: atom.bot.contentEnd,
                cursor: cursor,
                fontSize: inSlotSize,
                placeholderIfEmpty: true,
              ),
            ],
          ),
          Text(
            ')',
            style: TextStyle(color: _fgFormula, fontSize: fontSize * 1.6),
          ),
        ],
      ),
    );
  }

  /// 根式
  Widget _buildSqrt(_SqrtAtom atom, int cursor, double fontSize) {
    final inSlotSize = fontSize * 0.95;
    final idxSize = fontSize * 0.55;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (atom.idx != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _buildSlotRow(
                atom.idx!.children,
                rowStart: atom.idx!.contentStart,
                rowEnd: atom.idx!.contentEnd,
                cursor: cursor,
                fontSize: idxSize,
                placeholderIfEmpty: true,
              ),
            ),
          Text(
            '√',
            style: TextStyle(
              color: _fgFormula,
              fontSize: fontSize * 1.2,
              height: 1,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _fgFracBar, width: 1.2)),
            ),
            padding: const EdgeInsets.fromLTRB(2, 2, 4, 0),
            child: _buildSlotRow(
              atom.content.children,
              rowStart: atom.content.contentStart,
              rowEnd: atom.content.contentEnd,
              cursor: cursor,
              fontSize: inSlotSize,
              placeholderIfEmpty: true,
            ),
          ),
        ],
      ),
    );
  }

  /// 上下标
  Widget _buildScript(_ScriptAtom atom, int cursor, double fontSize) {
    final scriptSize = fontSize * 0.65;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildAtomWidget(atom.base, cursor, fontSize),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (atom.sup != null)
              Padding(
                padding: EdgeInsets.only(bottom: fontSize * 0.4),
                child: _buildSlotRow(
                  atom.sup!.children,
                  rowStart: atom.sup!.contentStart,
                  rowEnd: atom.sup!.contentEnd,
                  cursor: cursor,
                  fontSize: scriptSize,
                  placeholderIfEmpty: true,
                ),
              ),
            if (atom.sub != null)
              Padding(
                padding: EdgeInsets.only(top: fontSize * 0.1),
                child: _buildSlotRow(
                  atom.sub!.children,
                  rowStart: atom.sub!.contentStart,
                  rowEnd: atom.sub!.contentEnd,
                  cursor: cursor,
                  fontSize: scriptSize,
                  placeholderIfEmpty: true,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
