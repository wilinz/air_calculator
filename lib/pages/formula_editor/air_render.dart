// ─── 空中模式 UI 渲染（rail/control/camera/history sheet）─────────────
part of '../formula_editor_page.dart';

extension _AirRender on _FormulaEditorPageState {
  Widget _buildAirActionRow() {
    // 横屏 air mode 由外层 Row 已分好绿栏宽度，跳过 72% 单手区约束。
    final innerWidth = _isLandscapeAir
        ? double.infinity
        : _screenSize.width * 0.72;
    return Container(
      decoration: BoxDecoration(
        // 横屏由外层统一 bg，避免 alpha 叠加
        color: _isLandscapeAir
            ? Colors.transparent
            : Colors.black.withValues(alpha: 0.4),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      padding: EdgeInsets.zero,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: innerWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                // ── 画布操作 ──
                Expanded(
                  child: _railBtn(
                    id: 'rail:drawing',
                    icon: _drawingEnabled ? Icons.gesture : Icons.do_not_touch,
                    label: _drawingEnabled
                        ? 'drawing_label'.tr
                        : 'no_drawing'.tr,
                    isActive: _drawingEnabled,
                    color: _drawingEnabled ? Colors.lightGreenAccent : null,
                    onTap: () {
                      setState(() => _drawingEnabled = !_drawingEnabled);
                      if (!_drawingEnabled &&
                          _airCanvas.currentStroke != null) {
                        _airCanvas.currentStroke!.trimTail(enabled: true);
                        _airCanvas.currentStroke!.smooth();
                        _airCanvas.endStroke();
                        _ptTracker.reset();
                      }
                    },
                  ),
                ),
                Expanded(
                  child: _railBtn(
                    id: 'rail:undo',
                    icon: Icons.undo,
                    label: 'undo'.tr,
                    visuallyDisabled: _airStrokeCount == 0,
                    onTap: () {
                      final removed = _airCanvas.undoLastStroke();
                      if (removed) {
                        setState(
                          () => _airStrokeCount = _airCanvas.strokeCount,
                        );
                        _airPicCache.picture = null;
                        _airCanvasTickVN.value++;
                      }
                    },
                  ),
                ),
                Expanded(
                  child: _railBtn(
                    id: 'rail:redo',
                    icon: Icons.redo,
                    label: 'redo'.tr,
                    visuallyDisabled: !_airCanvas.canRedo,
                    onTap: () {
                      final restored = _airCanvas.redoLastStroke();
                      if (restored) {
                        setState(
                          () => _airStrokeCount = _airCanvas.strokeCount,
                        );
                        _airPicCache.picture = null;
                        _airCanvasTickVN.value++;
                      }
                    },
                  ),
                ),
                Expanded(
                  child: _railBtn(
                    id: 'rail:scissor',
                    icon: Icons.content_cut,
                    label: 'scissor'.tr,
                    isActive: _scissorMode,
                    color: _scissorMode ? Colors.orangeAccent : null,
                    visuallyDisabled: _airStrokeCount == 0 && !_scissorMode,
                    onTap: () {
                      setState(() => _scissorMode = !_scissorMode);
                      if (_scissorMode) {
                        _airClick.setAllowedIds({
                          'rail:scissor',
                          'rail:undo',
                          'rail:redo',
                          'rail:clear',
                        });
                      } else {
                        _airClick.setAllowedIds(null);
                        _scissorVN.value = null;
                        _scissorTargetIdx = null;
                        _scissorDwellStart = null;
                      }
                    },
                  ),
                ),
                Expanded(
                  child: _railBtn(
                    id: 'rail:clear',
                    icon: Icons.delete_outline,
                    label: 'clear'.tr,
                    visuallyDisabled: _airStrokeCount == 0,
                    onTap: () {
                      if (_airCanvas.strokeCount == 0 &&
                          _airCanvas.currentStroke == null)
                        return;
                      setState(() {
                        _airCanvas.clear();
                        _airPicCache.picture = null;
                        _airStrokeCount = 0;
                      });
                      _airCanvasTickVN.value++;
                      _ptTracker.reset();
                    },
                  ),
                ),
                Expanded(
                  child: _railBtn(
                    id: 'rail:undoRecog',
                    // 公式 + 笔画一起还原 → 用 settings_backup_restore（双箭头还原）+ 暖橙
                    icon: Icons.settings_backup_restore,
                    label: 'restore'.tr,
                    tooltip: 'restore_tooltip'.tr,
                    color: _preRecogLatex == null ? null : Colors.amberAccent,
                    visuallyDisabled: _preRecogLatex == null,
                    onTap: _undoAirRecognize,
                  ),
                ),
                Expanded(
                  child: _railBtn(
                    id: 'rail:undoRecogLatex',
                    // 仅公式文本还原 → 用 short_text（文字行）+ 青蓝，跟橙色形成色差
                    icon: Icons.short_text,
                    label: 'restore_formula'.tr,
                    tooltip: 'restore_formula_tooltip'.tr,
                    color: _preRecogLatex == null ? null : Colors.cyanAccent,
                    visuallyDisabled: _preRecogLatex == null,
                    onTap: _undoAirRecognizeLatexOnly,
                  ),
                ),
                // ── 识别放最右 ──
                Expanded(
                  child: ValueListenableBuilder<double>(
                    valueListenable: _autoRecogProgressVN,
                    builder: (_, progress, child) {
                      return Stack(
                        fit: StackFit.passthrough,
                        children: [
                          child!,
                          if (progress > 0)
                            Positioned(
                              left: 2,
                              right: 2,
                              bottom: 2,
                              height: 3,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: Colors.white12,
                                  valueColor: const AlwaysStoppedAnimation(
                                    Color(0xFF42A5F5),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                    child: _railBtn(
                      id: 'rail:recognize',
                      icon: _airRecognizing
                          ? Icons.hourglass_empty
                          : Icons.text_fields,
                      label: _airRecognizing
                          ? 'recognizing'.tr
                          : 'recognize'.tr,
                      color: const Color(0xFF1976D2),
                      primary: true,
                      visuallyDisabled: _airStrokeCount == 0 || _airRecognizing,
                      onTap: _airRecognizeNow,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// air 行内按钮（始终包 AirClickable，stable id + stable onTap）。
  Widget _railDivider() => SizedBox(
    width: 1,
    height: 28,
    child: DecoratedBox(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2)),
    ),
  );

  Widget _railBtn({
    required String id,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    bool primary = false,
    bool isActive = false,
    bool visuallyDisabled = false,
    String? tooltip,
  }) {
    final fg = visuallyDisabled ? Colors.white24 : (color ?? Colors.white);
    final bg = primary && !visuallyDisabled
        ? (color ?? Colors.white).withValues(alpha: 0.20)
        : (isActive
              ? Colors.white.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.06));
    final btn = Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(height: 1),
          // 固定高度以容纳两行文字，所有按钮高度一致
          SizedBox(
            height: 24,
            child: Center(
              child: Text(
                label,
                style: TextStyle(color: fg, fontSize: 10, height: 1.1),
                textAlign: TextAlign.center,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.visible,
              ),
            ),
          ),
        ],
      ),
    );
    final wrapped = tooltip != null
        ? Tooltip(message: tooltip, child: btn)
        : btn;
    return AirClickable(
      id: id,
      controller: _airClick,
      onTap: onTap,
      child: GestureDetector(onTap: onTap, child: wrapped),
    );
  }

  /// 语音快捷切换：第一次按开始录音，第二次停止并发送（取代长按）
  Future<void> _voiceQuickToggle() async {
    if (_voiceRecording) {
      await _voiceStopAndProcess();
    } else {
      await _voiceStart();
    }
  }

  Widget _buildCameraPreview() {
    // buffer 与 display 同朝向，无需 RotatedBox：iOS 靠动态 videoOrientation，
    // Android 靠 CameraX Preview 的 targetRotation——旋转记在 SurfaceTexture
    // 的变换矩阵里，Flutter 的 Texture 会应用它。
    //
    // 前置镜像两端都由相机自己做掉了，这里不能再翻：
    //   iOS      AVCaptureConnection.isVideoMirrored
    //   Android  CameraX 的 Preview 用例把镜像一并记进 SurfaceTexture 的
    //            变换矩阵（试过在这里加 Transform.scale(scaleX: -1)，结果是
    //            把画面翻正了——衣服上的字能正着读，而关键点仍是镜像的，
    //            两边对不上）。
    // 关键点那一侧的镜像在插件里做（21 个点，不是 30 万个像素）。
    //
    // 横屏补转：Android 端把 Preview 的 targetRotation 钉在 ROTATION_0，纹理里
    // 的画面只相对设备自然朝向摆正，屏幕转到哪要在这里补一个 RotatedBox
    // （官方 camera_android_camerax 的 SurfaceTextureRotatedPreview 同样思路）。
    // iOS 的 quarterTurns 恒为 0，这一层是空转。
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _shownPreviewW,
          height: _shownPreviewH,
          child: RotatedBox(
            quarterTurns: _previewTurns,
            child: SizedBox(
              width: _previewW,
              height: _previewH,
              child: Texture(textureId: _textureId!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAirControlBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
      ),
      // 把 SafeArea 放在背景内部：按钮停在安全区内，但容器背景延伸到 home indicator 区域
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 状态行
            AnimatedOpacity(
              opacity: _handDetected || _airRecognizing ? 1.0 : 0.45,
              duration: const Duration(milliseconds: 400),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _airStatusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppGlyphText(
                        _airStatusText(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_airStrokeCount > 0)
                      Text(
                        '$_airStrokeCount${'strokes_suffix'.tr}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
            // 操作行
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  _airBtn(
                    icon: _airRecognizing
                        ? Icons.hourglass_empty
                        : Icons.text_fields,
                    // label 用稳定字符串，避免 air-click id 漂移
                    label: 'recognize_insert'.tr,
                    // onTap 永远是同一个引用，幂等由 _airRecognizeNow 头部 guard 保证
                    onTap: _airRecognizeNow,
                    visuallyDisabled: _airStrokeCount == 0 || _airRecognizing,
                    primary: true,
                  ),
                  const SizedBox(width: 8),
                  _airBtn(
                    icon: Icons.delete_outline,
                    label: 'clear'.tr,
                    onTap: () {
                      if (_airCanvas.strokeCount == 0 &&
                          _airCanvas.currentStroke == null) {
                        return;
                      }
                      setState(() {
                        _airCanvas.clear();
                        _airPicCache.picture = null;
                        _airStrokeCount = 0;
                      });
                      _airCanvasTickVN.value++;
                      _ptTracker.reset();
                    },
                  ),
                  const SizedBox(width: 8),
                  _airBtn(
                    icon: _showSkeleton
                        ? Icons.visibility
                        : Icons.visibility_off,
                    label: 'skeleton'.tr,
                    onTap: () => setState(() => _showSkeleton = !_showSkeleton),
                    isActive: _showSkeleton,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _airBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
    bool isActive = false,
    // 视觉上 disabled，但 onTap 仍 register 给 AirClickable，保证 stable reference
    bool visuallyDisabled = false,
  }) {
    final disabled = onTap == null || visuallyDisabled;
    Color bg;
    if (disabled) {
      bg = Colors.white.withValues(alpha: 0.06);
    } else if (primary) {
      bg = const Color(0xFF1976D2).withValues(alpha: 0.85);
    } else if (isActive) {
      bg = Colors.white24;
    } else {
      bg = Colors.white.withValues(alpha: 0.18);
    }
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: disabled ? Colors.white38 : Colors.white,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: disabled ? Colors.white38 : Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
    // 始终包 AirClickable，onTap 始终是同一个 reference（不因 disabled 切换）
    // 由回调自身的 guard 决定是否真正执行（保证 air-click 注册稳定）
    return Expanded(
      child: AirClickable(
        id: 'airbtn:$label',
        controller: _airClick,
        onTap: onTap ?? () {},
        child: btn,
      ),
    );
  }

  AppBar _buildAppBar(BuildContext ctx) {
    final bgColor = _airMode
        ? Colors.black.withValues(alpha: 0.4)
        : _Pal.appBar;
    final fgColor = _airMode ? Colors.white : _Pal.text;
    final shape = _airMode
        ? null
        : const Border(bottom: BorderSide(color: _Pal.divider, width: 1));

    // 摄像头开关按钮（共用）
    final cameraBtn = widget.allowCamera
        ? IconButton(
            tooltip: _cameraBusy
                ? 'processing'.tr
                : (_airMode ? 'close_camera'.tr : 'open_air_writing'.tr),
            icon: _cameraBusy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _airMode ? Colors.greenAccent : _Pal.text,
                    ),
                  )
                : Icon(
                    _airMode ? Icons.videocam : Icons.videocam_outlined,
                    color: _airMode ? Colors.greenAccent : _Pal.text,
                  ),
            onPressed: _cameraBusy ? null : _toggleCamera,
          )
        : null;

    if (widget.isStandalone) {
      // ── 独立主页面 AppBar ─────────────────────────────────────────────
      return AppBar(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: shape,
        titleSpacing: 8,
        title: ValueListenableBuilder<int>(
          valueListenable: _fpsVN,
          builder: (_, fps, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'app_title'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: fgColor,
                  ),
                ),
              ),
              if (_airMode && fps > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$fps${'fps_suffix'.tr}',
                  style: TextStyle(
                    fontSize: 11,
                    color: fps >= 25
                        ? Colors.greenAccent
                        : fps >= 15
                        ? Colors.orangeAccent
                        : Colors.redAccent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          // air mode 顶栏：语音、播报、骨架、历史、设置（紧凑布局）
          if (_airMode) ...[
            _topIcon(
              'top:voice',
              icon: _voiceRecording ? Icons.mic : Icons.mic_none,
              color: _voiceRecording ? Colors.redAccent : Colors.white70,
              tooltip: 'voice'.tr,
              onTap: _voiceService.hasApiKey
                  ? _voiceQuickToggle
                  : _showVoiceApiKeyDialog,
            ),
            _topIcon(
              'top:tts',
              icon: _ttsEnabled ? Icons.volume_up : Icons.volume_off,
              color: _ttsEnabled ? Colors.greenAccent : Colors.white70,
              tooltip: 'speak'.tr,
              onTap: () {
                setState(() => _ttsEnabled = !_ttsEnabled);
                if (!_ttsEnabled) _tts.stop();
              },
            ),
            if (_history.isNotEmpty)
              _topIcon(
                'top:history',
                icon: Icons.history,
                color: Colors.white70,
                tooltip: 'history'.tr,
                onTap: () => _showHistorySheet(ctx),
              ),
            _topIcon(
              'top:settings',
              icon: Icons.settings,
              color: Colors.white70,
              tooltip: 'settings'.tr,
              onTap: _showVoiceApiKeyDialog,
            ),
          ],
          // 非 air mode 顶栏：与空中模式同款紧凑图标布局
          if (!_airMode) ...[
            _topIcon(
              'top:voice',
              icon: _voiceRecording ? Icons.mic : Icons.mic_none,
              color: _voiceRecording
                  ? Colors.redAccent
                  : (_voiceService.hasApiKey ? _Pal.text : Colors.grey),
              tooltip: _voiceService.hasApiKey
                  ? 'press_to_record'.tr
                  : 'set_api_key_first'.tr,
              onTap: _voiceService.hasApiKey
                  ? _voiceQuickToggle
                  : _showVoiceApiKeyDialog,
            ),
            _topIcon(
              'top:tts',
              icon: _ttsEnabled ? Icons.volume_up : Icons.volume_off,
              color: _ttsEnabled ? Colors.green : _Pal.textMuted,
              tooltip: 'speak'.tr,
              onTap: () {
                setState(() => _ttsEnabled = !_ttsEnabled);
                if (!_ttsEnabled) _tts.stop();
              },
            ),
            if (_history.isNotEmpty)
              _topIcon(
                'top:history',
                icon: Icons.history,
                color: _Pal.text,
                tooltip: 'history_records'.tr,
                onTap: () => _showHistorySheet(ctx),
              ),
            _topIcon(
              'top:settings',
              icon: Icons.settings,
              color: _Pal.text,
              tooltip: 'settings'.tr,
              onTap: _showVoiceApiKeyDialog,
            ),
          ],
          if (cameraBtn != null)
            if (_airMode && !_cameraBusy)
              AirClickable(
                id: 'top:camera',
                controller: _airClickSafe,
                onTap: _toggleCamera,
                child: cameraBtn,
              )
            else
              _air('top:camera', _cameraBusy ? null : _toggleCamera, cameraBtn),
          const SizedBox(width: 4),
        ],
      );
    }

    // ── 对话框模式 AppBar ──────────────────────────────────────────────────
    return AppBar(
      backgroundColor: bgColor,
      foregroundColor: fgColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: shape,
      title: Text(
        'formula_editor_title'.tr,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: fgColor,
        ),
      ),
      actions: [
        if (cameraBtn != null) cameraBtn,
        if (!_airMode) ...[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'cancel'.tr,
              style: TextStyle(color: _fgMuted, fontSize: 15),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _Pal.accent,
                side: const BorderSide(color: _Pal.accent),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 0,
                ),
                minimumSize: const Size(0, 36),
              ),
              onPressed: _latex.text.trim().isEmpty || _busy
                  ? null
                  : _calculateNow,
              child: Text(
                'equals_calculate'.tr,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _Pal.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 0,
                ),
                minimumSize: const Size(0, 36),
              ),
              onPressed: _latex.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, _latex.text.trim()),
              child: Text(
                'confirm'.tr,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ] else ...[
          TextButton(
            onPressed: _latex.text.trim().isEmpty
                ? null
                : () => Navigator.pop(ctx, _latex.text.trim()),
            child: Text(
              'confirm'.tr,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showHistorySheet(BuildContext ctx) {
    final airMode = _airMode;
    // Air mode: solid dark background, white text, AirClickable wrappers.
    final bgColor = airMode ? const Color(0xF20E1116) : _Pal.appBar;
    final titleColor = airMode ? Colors.white : _Pal.text;
    final mutedColor = airMode ? Colors.white60 : _fgWeak;
    final dividerColor = airMode
        ? Colors.white.withValues(alpha: 0.10)
        : _Pal.divider;
    final formulaColor = airMode ? Colors.white : _fgFormula;
    final accentColor = airMode ? Colors.lightBlueAccent : _Pal.accent;

    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: bgColor,
      barrierColor: airMode ? Colors.black54 : null,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        minChildSize: 0.25,
        builder: (_, sc) => StatefulBuilder(
          builder: (_, setSt) => Column(
            children: [
              if (airMode)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Text(
                      'calc_history'.tr,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                    const Spacer(),
                    _air(
                      'history:clear',
                      _history.isEmpty
                          ? null
                          : () {
                              setState(() => _history.clear());
                              setSt(() {});
                              Navigator.pop(ctx);
                            },
                      TextButton(
                        onPressed: _history.isEmpty
                            ? null
                            : () {
                                setState(() => _history.clear());
                                setSt(() {});
                                Navigator.pop(ctx);
                              },
                        child: Text(
                          'clear'.tr,
                          style: TextStyle(color: accentColor),
                        ),
                      ),
                    ),
                    _air(
                      'history:close',
                      () => Navigator.pop(ctx),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icon(Icons.close, color: mutedColor),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: dividerColor, height: 1),
              Expanded(
                child: _history.isEmpty
                    ? Center(
                        child: Text(
                          'no_records'.tr,
                          style: TextStyle(color: mutedColor),
                        ),
                      )
                    : ListView.separated(
                        controller: sc,
                        itemCount: _history.length,
                        separatorBuilder: (_, __) =>
                            Divider(color: dividerColor, height: 1),
                        itemBuilder: (_, i) {
                          final e = _history[i];
                          final t =
                              '${e.time.hour.toString().padLeft(2, '0')}:${e.time.minute.toString().padLeft(2, '0')}';
                          void onTap() {
                            setState(() {
                              _latex.text = e.expr;
                              _calcResult = '= ${e.result}';
                              _lastTextLen = e.expr.length;
                              _setSrcCursor(e.expr.length);
                            });
                            Navigator.pop(ctx);
                          }

                          final tile = ListTile(
                            dense: true,
                            title: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  Math.tex(
                                    e.expr,
                                    textStyle: TextStyle(
                                      color: formulaColor,
                                      fontSize: 18,
                                    ),
                                    onErrorFallback: (_) => Text(
                                      e.expr,
                                      style: TextStyle(
                                        color: formulaColor,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Math.tex(
                                    '= ${e.result}',
                                    textStyle: TextStyle(
                                      color: accentColor,
                                      fontSize: 18,
                                    ),
                                    onErrorFallback: (_) => Text(
                                      '= ${e.result}',
                                      style: TextStyle(
                                        color: accentColor,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            trailing: Text(
                              t,
                              style: TextStyle(color: mutedColor, fontSize: 12),
                            ),
                            onTap: onTap,
                          );
                          return _air('history:item:$i', onTap, tile);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 横屏 air mode：preview / blue 左栏 / green 中栏 / yellow 右栏 ──────────

  Widget _buildLandscapeAirBody(MediaQueryData mq, double bottomKb) {
    final w = mq.size.width;
    final h = mq.size.height;
    final previewH = h * 0.25;
    final blueW = 64.0 + mq.padding.left; // 左侧加上 notch 安全区
    final yellowW = (w * 0.32).clamp(220.0, 360.0) + mq.padding.right;

    // 横屏整体一层 0.4 alpha；内层各 widget（_buildAirActionRow/_buildRawRow/
    // _buildCursorDragBar/_buildAirTabBar/_buildQuickToolbar/_buildHandwritingPanel/
    // _buildPreview 内框）通过 _isLandscapeAir flag 把自己的 bg 改为透明，避免
    // alpha 叠加。
    return Container(
      color: _airBg(_Pal.scaffold, alpha: 0.4),
      child: Column(
        children: [
          // ── 预览 ──
          SizedBox(
            height: previewH + mq.padding.top,
            child: Padding(
              padding: EdgeInsets.only(top: mq.padding.top),
              child: _buildPreview(),
            ),
          ),
          const Divider(color: _Pal.divider, height: 1),
          // ── 下方三栏 ──
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 蓝：左侧竖向图标栏（语音/播报/历史/设置/摄像头）
                SizedBox(width: blueW, child: _buildLandscapeIconColumn()),
                Container(width: 1, color: _Pal.divider),
                // 绿：中栏（运算键 + air actions 在上，光标滑块 + LaTeX 原文 + 录音提示在下）
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildQuickToolbar(),
                        _buildAirActionRow(),
                        // _buildAirActionRow 底 border + _buildCursorDragBar
                        // 顶 border 已天然构成分割线，不再加 Divider 避免重复。
                        _buildCursorDragBar(),
                        _buildRawRow(),
                        if (_voiceStatus().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: AppGlyphText(
                                _voiceStatus(),
                                style: TextStyle(
                                  color: _voiceRecording
                                      ? Colors.redAccent
                                      : _fgMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, color: _Pal.divider),
                // 黄：右侧 tab + 内容。分隔线延伸到屏幕最右；TabBar / 内容
                // 各自包 Padding 让出 right safe area。
                SizedBox(
                  width: yellowW,
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.only(right: mq.padding.right),
                        child: _buildTabBar(),
                      ),
                      const Divider(color: _Pal.divider, height: 1),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: mq.padding.right,
                            bottom: mq.padding.bottom,
                          ),
                          child: TabBarView(
                            controller: _tab,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              // [0] 空中提示
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  'air_draw_hint'.tr,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              // [1] 触摸手写
                              _buildHandwritingPanel(),
                              // [2..] 键盘分类
                              ..._kCategories.map(_buildGrid),
                            ],
                          ),
                        ),
                      ),
                      if (bottomKb > 0) SizedBox(height: bottomKb),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 横屏 air mode 左侧蓝栏：原 AppBar actions 改为竖排。
  /// 不再加自己的 bg，沿用外层 _buildLandscapeAirBody 的统一背景。
  Widget _buildLandscapeIconColumn() {
    return SafeArea(
      right: false,
      bottom: false,
      child: Column(
        children: [
          // 标题简写 + FPS
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ValueListenableBuilder<int>(
              valueListenable: _fpsVN,
              builder: (_, fps, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calculate_outlined,
                    color: Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fps > 0 ? '$fps' : '',
                    style: TextStyle(
                      color: fps >= 25
                          ? Colors.greenAccent
                          : fps >= 15
                          ? Colors.orangeAccent
                          : Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 4),
          _topIcon(
            'land:voice',
            icon: _voiceRecording ? Icons.mic : Icons.mic_none,
            color: _voiceRecording ? Colors.redAccent : Colors.white70,
            tooltip: 'voice'.tr,
            onTap: _voiceService.hasApiKey
                ? _voiceQuickToggle
                : _showVoiceApiKeyDialog,
          ),
          _topIcon(
            'land:tts',
            icon: _ttsEnabled ? Icons.volume_up : Icons.volume_off,
            color: _ttsEnabled ? Colors.greenAccent : Colors.white70,
            tooltip: 'speak'.tr,
            onTap: () {
              setState(() => _ttsEnabled = !_ttsEnabled);
              if (!_ttsEnabled) _tts.stop();
            },
          ),
          if (_history.isNotEmpty)
            _topIcon(
              'land:history',
              icon: Icons.history,
              color: Colors.white70,
              tooltip: 'history'.tr,
              onTap: () => _showHistorySheet(context),
            ),
          _topIcon(
            'land:settings',
            icon: Icons.settings,
            color: Colors.white70,
            tooltip: 'settings'.tr,
            onTap: _showVoiceApiKeyDialog,
          ),
          const Spacer(),
          // 摄像头开关放底部
          if (widget.allowCamera)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _topIcon(
                'land:camera',
                icon: _cameraBusy
                    ? Icons.hourglass_empty
                    : (_airMode ? Icons.videocam : Icons.videocam_outlined),
                color: _airMode ? Colors.greenAccent : Colors.white70,
                tooltip: _airMode ? 'close_camera'.tr : 'open_air_writing'.tr,
                onTap: _cameraBusy ? null : _toggleCamera,
              ),
            ),
        ],
      ),
    );
  }
}
