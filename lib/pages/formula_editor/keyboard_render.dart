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

// ─── 键盘 / 标签栏 / 手写面板 / LaTeX 原文行 ─────────────────────────────
part of '../formula_editor_page.dart';

extension _KeyboardRender on _FormulaEditorPageState {
  Widget _buildRawRow() {
    final pos = _latex.selection.isValid ? _latex.selection.start : 0;
    final len = _latex.text.length;

    Widget collapsedRow = GestureDetector(
      onTap: () => setState(() => _showRaw = true),
      child: Container(
        color: _airMode ? Colors.transparent : _Pal.rawBg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.code, color: _fgMuted, size: 14),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _latex.text.isEmpty ? 'latex_raw'.tr : _latex.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _latex.text.isEmpty ? _fgWeak : _fgMuted,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            Text('$pos/$len', style: TextStyle(color: _fgMuted, fontSize: 10)),
            const SizedBox(width: 4),
            _air(
              'raw:expand',
              () => setState(() => _showRaw = true),
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: Icon(Icons.expand_more, color: _fgMuted, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Widget expandedRow = Container(
      color: _airMode ? Colors.transparent : _Pal.rawBg,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _latex,
              style: TextStyle(
                color: _fgText,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
                hintText: r'\frac{1}{2}',
                hintStyle: TextStyle(color: _fgWeak, fontSize: 12),
              ),
            ),
          ),
          _air(
            'raw:collapse',
            () => setState(() => _showRaw = false),
            IconButton(
              onPressed: () => setState(() => _showRaw = false),
              icon: Icon(Icons.expand_less, color: _fgMuted, size: 18),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );

    // air mode：直接条件切换，避免 AnimatedCrossFade 内部 Stack 导致 AirClickable rect 偏移
    if (_airMode) {
      final content = _showRaw ? expandedRow : collapsedRow;
      return Stack(
        children: [
          // 横屏由外层统一 bg，跳过自身 bg 避免叠加
          if (!_isLandscapeAir)
            Positioned.fill(child: ColoredBox(color: _airBg(_Pal.rawBg))),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: _isLandscapeAir
                  ? double.infinity
                  : _screenSize.width * 0.72,
              child: content,
            ),
          ),
        ],
      );
    }

    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 180),
      crossFadeState: _showRaw
          ? CrossFadeState.showSecond
          : CrossFadeState.showFirst,
      firstChild: collapsedRow,
      secondChild: expandedRow,
    );
  }

  Widget _buildTabBar() {
    if (_airMode) return _buildAirTabBar();

    return Container(
      color: _Pal.appBar,
      child: TabBar(
        controller: _tab,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: _Pal.tabIndicator,
        indicatorWeight: 2.5,
        labelColor: _Pal.tabIndicator,
        unselectedLabelColor: _Pal.textMuted,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        dividerColor: _Pal.divider,
        padding: EdgeInsets.zero,
        indicatorSize: TabBarIndicatorSize.tab,
        tabs: [
          Tab(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.edit, size: 14),
                const SizedBox(width: 4),
                Text('handwriting'.tr),
              ],
            ),
          ),
          ..._kCategories.map(
            (c) => Tab(
              height: 40,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(c.icon, size: 14),
                  const SizedBox(width: 4),
                  Text(c.name.tr),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAirTabBar() {
    final tabs = [
      (Icons.front_hand, 'air'.tr),
      (Icons.edit, 'handwriting'.tr),
      ..._kCategories.map((c) => (c.icon, c.name.tr)),
    ];
    return Stack(
      children: [
        // 背景延伸到全宽（横屏交给外层统一 bg）
        if (!_isLandscapeAir)
          Positioned.fill(child: ColoredBox(color: _airBg(_Pal.appBar))),
        // tab 按钮限制在 72%（横屏三栏布局时由外层 Row 约束，铺满）
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: _isLandscapeAir ? double.infinity : _screenSize.width * 0.72,
            child: AnimatedBuilder(
              animation: _tab,
              builder: (_, __) {
                final selected = _tab.index;
                return Row(
                  children: List.generate(tabs.length, (i) {
                    final isSelected = i == selected;
                    final icon = tabs[i].$1;
                    final name = tabs[i].$2;
                    return Expanded(
                      child: AirClickable(
                        id: 'tab:$i',
                        controller: _airClick,
                        onTap: () => _tab.animateTo(i),
                        child: GestureDetector(
                          onTap: () => _tab.animateTo(i),
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: isSelected
                                      ? _Pal.tabIndicator
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Icon(
                                  icon,
                                  size: 16,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white54,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── 手写面板 ──────────────────────────────────────────────────────────

  Widget _buildHandwritingPanel() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final padHeight = constraints.maxHeight - 56; // 留 56 给操作行
        return Container(
          // 横屏由外层统一 bg
          color: _isLandscapeAir ? Colors.transparent : _airBg(_Pal.scaffold),
          // 底部让出安全区。padding 在 Container 的 color 内部，背景仍铺到
          // 屏幕底边，只是操作行往上收，不会被 home indicator 和圆角切到。
          padding: EdgeInsets.fromLTRB(8, 6, 8, 6 + _safeBottom),
          child: Column(
            children: [
              // 状态行
              SizedBox(
                height: 24,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    Icon(
                      _modelReady ? Icons.check_circle : Icons.hourglass_empty,
                      color: _modelReady ? _Pal.cursor : _Pal.textWeak,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AppGlyphText(
                        _hwStatus(),
                        style: TextStyle(color: _fgMuted, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // 画布
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    // 空中模式下与其他面板背景使用同一 alpha，避免视觉割裂
                    color: _airMode
                        ? Colors.black.withValues(alpha: 0.4)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _airMode
                          ? Colors.white.withValues(alpha: 0.10)
                          : _Pal.divider,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Builder(
                    builder: (ctx2) => TouchHandwritingPad(
                      canvasState: _hwCanvas,
                      strokeWidth: 4,
                      strokeColor: _airMode ? Colors.white : _Pal.text,
                      background: _airBg(Colors.white, alpha: 0.0),
                      gridColor: _airMode ? Colors.white24 : _Pal.divider,
                      height: padHeight - 32,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // 操作行：air mode 下也保留，并包 AirClickable 以支持悬停点击
              () {
                final undoTap = _hwCanvas.strokes.isEmpty
                    ? null
                    : () {
                        _hwCanvas.undoLastStroke(minPoints: 1);
                        setState(() {});
                      };
                final clearTap = _hwCanvas.strokes.isEmpty
                    ? null
                    : () {
                        _hwCanvas.clear();
                        setState(() {});
                      };
                final recogTap =
                    !_modelReady || _busy || _hwCanvas.strokes.isEmpty
                    ? null
                    : () {
                        final box = (ctx.findRenderObject() as RenderBox?);
                        final size = box?.size ?? const Size(360, 180);
                        _recognizeHandwriting(Size(size.width, padHeight - 32));
                      };
                return Row(
                  children: [
                    _air(
                      'hw:undo',
                      undoTap,
                      _hwActionBtn(
                        icon: Icons.undo,
                        label: 'undo'.tr,
                        onTap: undoTap,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _air(
                      'hw:clear',
                      clearTap,
                      _hwActionBtn(
                        icon: Icons.delete_outline,
                        label: 'clear'.tr,
                        onTap: clearTap,
                      ),
                    ),
                    const Spacer(),
                    _air(
                      'hw:recognize',
                      recogTap,
                      _hwActionBtn(
                        icon: Icons.text_fields,
                        label: _busy ? 'recognizing'.tr : 'recognize_insert'.tr,
                        primary: true,
                        onTap: recogTap,
                      ),
                    ),
                  ],
                );
              }(),
            ],
          ),
        );
      },
    );
  }

  Widget _hwActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
  }) {
    final disabled = onTap == null;
    // air mode 用半透明白底 + 亮色前景以贴合摄像头预览背景
    final fg = _airMode
        ? (disabled ? Colors.white38 : (primary ? Colors.white : Colors.white))
        : (disabled ? _Pal.textWeak : (primary ? Colors.white : _Pal.text));
    final bg = _airMode
        ? (disabled
              ? Colors.white.withValues(alpha: 0.06)
              : (primary
                    ? const Color(0xFF1976D2).withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.18)))
        : (disabled ? _Pal.divider : (primary ? _Pal.accent : _Pal.keyBg));
    final borderColor = _airMode
        ? Colors.white.withValues(alpha: 0.10)
        : _Pal.divider;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 13,
                fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(_Category cat) => GridView.builder(
    // 底部多让出一个安全区：最后一行键否则会压在 home indicator 上，
    // iPhone 的屏幕圆角还会切掉两侧的键。面板背景是外层 Positioned.fill
    // 画的，铺满全高，所以这里只收内容、不会露出相机。
    padding: EdgeInsets.fromLTRB(6, 6, 6, 6 + _safeBottom),
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: cat.cols,
      childAspectRatio: 1.65,
      crossAxisSpacing: 5,
      mainAxisSpacing: 5,
    ),
    itemCount: cat.keys.length,
    itemBuilder: (_, i) => _buildKeyBtn(cat.keys[i]),
  );

  Widget _buildKeyBtn(_MathKey key) {
    final Color bg = _airBg(_Pal.keyBg, alpha: 0.4);
    final Widget label;

    if (key.isBack) {
      label = const Icon(
        Icons.backspace_outlined,
        color: _Pal.accent,
        size: 20,
      );
    } else if (key.isCursorMove) {
      // 原来直接画 '◀'/'▶'，这两个码位在 Android 上落到 emoji 字体会被渲染成
      // 彩色三角；改用自绘图标，颜色/字重与其它键一致。
      label = AppIcon(
        key.moveDir < 0 ? AppIconData.caretLeft : AppIconData.caretRight,
        size: 18,
        color: _fgText,
      );
    } else if (key.isLatex) {
      label = Math.tex(
        key.label,
        textStyle: TextStyle(color: _fgText, fontSize: 15),
        onErrorFallback: (_) =>
            Text(key.label, style: TextStyle(color: _fgMuted, fontSize: 11)),
      );
    } else {
      final isOp = '÷×−+()=,%'.contains(key.label);
      label = Text(
        key.label,
        style: TextStyle(
          color: isOp
              ? (_airMode ? Colors.redAccent[100]! : _Pal.operator)
              : _fgText,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    onTap() => _onKey(key);
    return _air(
      'kkey:${key.label}:${key.insert.hashCode}',
      onTap,
      Material(
        color: bg,
        elevation: 0.5,
        shadowColor: _Pal.keyShadow,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          splashColor: _Pal.divider,
          highlightColor: _Pal.divider,
          onTap: onTap,
          onLongPress: key.isBack
              ? () {
                  _latex.clear();
                }
              : null,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: FittedBox(fit: BoxFit.scaleDown, child: label),
            ),
          ),
        ),
      ),
    );
  }
}
