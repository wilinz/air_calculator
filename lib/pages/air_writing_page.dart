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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hand_camera/hand_camera.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter_math_fork/flutter_math.dart';

import '../controllers/air_writing_controller.dart';
import '../i18n/app_translations.dart';
import '../pages/formula_editor_page.dart';
import '../widgets/app_icons.dart';
import '../widgets/drawing_canvas.dart';

class AirWritingPage extends StatefulWidget {
  const AirWritingPage({super.key});

  @override
  State<AirWritingPage> createState() => _AirWritingPageState();
}

class _AirWritingPageState extends State<AirWritingPage> {
  late final AirWritingController _ctrl;

  int? _textureId;
  // 纹理里画面摆正后的尺寸（Android 上相对设备自然朝向，绑定后恒定）
  double _previewW = 480.0;
  double _previewH = 640.0;

  /// 纹理要补转的 90 度次数（逆时针）。Android 横屏靠它，iOS 恒为 0。
  int _previewTurns = 0;

  StreamSubscription<List<HandLandmarks>>? _landmarkSub;
  StreamSubscription<HandCameraPreviewSize>? _previewSizeSub;

  bool _cameraReady = false;
  bool _permissionGranted = false;

  int _frameCount = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ctrl = Get.put(AirWritingController());
    // 朝向变化时 native 会重推：画面尺寸恒定，变的是 quarterTurns。
    _previewSizeSub = HandCamera.previewSizeStream.listen((s) {
      if (!mounted) return;
      if (_previewW == s.width.toDouble() &&
          _previewH == s.height.toDouble() &&
          _previewTurns == s.quarterTurns) {
        return;
      }
      setState(() {
        _previewW = s.width.toDouble();
        _previewH = s.height.toDouble();
        _previewTurns = s.quarterTurns;
      });
      _ctrl.previewW = _previewW;
      _ctrl.previewH = _previewH;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _landmarkSub?.cancel();
    _previewSizeSub?.cancel();
    HandCamera.dispose();
    Get.delete<AirWritingController>();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------------

  Future<void> _start() async {
    // macOS: permission_handler 无 macOS 实现，依赖 sandbox entitlement +
    // NSCameraUsageDescription，系统首次启用 AVCaptureSession 时自动弹窗
    if (!Platform.isMacOS) {
      _ctrl.statusText.value = 'checking_camera_perm'.tr;
      var status = await Permission.camera.status;
      if (status.isDenied || status.isRestricted) {
        status = await Permission.camera.request();
      }
      if (!status.isGranted && !status.isLimited) {
        _ctrl.statusText.value = status.isPermanentlyDenied
            ? 'camera_perm_perma_denied'.tr
            : 'camera_perm_denied'.tr;
        _ctrl.statusColor.value = Colors.red;
        return;
      }
    }
    setState(() => _permissionGranted = true);
    await _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _ctrl.statusText.value = 'starting_camera'.tr;
      final result = await HandCamera.initialize(numHands: 1);

      _ctrl.sensorOrientation = Platform.isAndroid
          ? result.sensorOrientation
          : 0;

      // previewWidth/Height 是画面摆正后的尺寸；界面朝向对应的 quarterTurns
      // 由 previewSizeStream 推来（见 initState）。
      setState(() {
        _previewW = result.previewWidth.toDouble();
        _previewH = result.previewHeight.toDouble();
      });
      _ctrl.previewW = _previewW;
      _ctrl.previewH = _previewH;

      debugPrint(
        'HandCamera init: so=${result.sensorOrientation}'
        '  effectiveAnalysis=${result.cameraWidth}x${result.cameraHeight}'
        '  preview=${result.previewWidth}x${result.previewHeight}'
        '  portrait previewW=$_previewW previewH=$_previewH',
      );

      setState(() {
        _textureId = result.textureId;
        _cameraReady = true;
      });

      _ctrl.statusText.value = 'ready_put_hand'.tr;
      _ctrl.statusColor.value = Colors.green;

      // Subscribe to landmark stream
      _landmarkSub = HandCamera.landmarkStream.listen(_onLandmarks);
    } catch (e) {
      _ctrl.statusText.value = '${'init_failed_prefix'.tr}$e';
      _ctrl.statusColor.value = Colors.red;
    }
  }

  void _onLandmarks(List<HandLandmarks> hands) {
    _frameCount++;
    final now = DateTime.now();
    if (now.difference(_lastFpsUpdate).inMilliseconds >= 1000) {
      _ctrl.fps.value =
          _frameCount / now.difference(_lastFpsUpdate).inMilliseconds * 1000;
      _frameCount = 0;
      _lastFpsUpdate = now;
    }

    // Convert hand_camera types to controller-compatible format
    if (hands.isEmpty) {
      _ctrl.onHandDetected(null);
    } else {
      _ctrl.onHandDetected(hands.first);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final topPadding = mq.padding.top;
    final bottomPadding = mq.padding.bottom;
    final isLandscape = mq.orientation == Orientation.landscape;
    final screenW = mq.size.width;
    final screenH = mq.size.height;
    // 横屏：右侧 35% 作为单手控制栏；左侧画布留给手部书写。
    final sidePanelW = isLandscape ? screenW * 0.35 : 0.0;
    return Scaffold(
      backgroundColor: Colors.black,
      // 相机预览和手部 overlay 都是这个 Stack 里的 Positioned.fill，
      // 坐标变换必须用它的**实际布局尺寸**：直接量，别按平台猜系统栏要不要扣。
      // 原先 Android 分支扣掉了 padding.top/bottom，纵向比例偏小，顶部重合、
      // 越往下偏得越多（无 AppBar 的 Scaffold body 本来就是铺满全屏的）。
      body: LayoutBuilder(
        builder: (context, constraints) {
          _ctrl.screenSize = constraints.biggest;
          return Stack(
            children: [
              // ── 相机预览（Flutter Texture，原生直接渲染，无拷贝）────────────
              if (_cameraReady && _textureId != null)
                Positioned.fill(child: _buildPreview()),

              // ── 初始化遮罩 ────────────────────────────────────────────────
              if (!_cameraReady)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.camera_alt,
                          size: 64,
                          color: Colors.white54,
                        ),
                        const SizedBox(height: 16),
                        Obx(
                          () => AppGlyphText(
                            _ctrl.statusText.value,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (!_permissionGranted) ...[
                          ElevatedButton(
                            onPressed: _start,
                            child: Text('request_camera_perm'.tr),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: openAppSettings,
                            child: Text('go_to_settings'.tr),
                          ),
                        ] else
                          const CircularProgressIndicator(),
                      ],
                    ),
                  ),
                ),

              // ── 绘图画布 ──────────────────────────────────────────────────
              if (_permissionGranted)
                Positioned.fill(
                  child: Obx(() {
                    _ctrl.canvasVersion.value;
                    return DrawingCanvas(
                      canvasState: _ctrl.canvasState,
                      pictureCache: _ctrl.pictureCache,
                      currentPoint: _ctrl.indicatorPoint.value,
                      isDrawing: _ctrl.isDrawingGesture.value,
                      lineColor: const Color(0xFF39FF14), // 荧光绿，灯光下易见
                    );
                  }),
                ),

              // ── 手部骨架 ──────────────────────────────────────────────────
              Positioned.fill(
                child: Obx(() {
                  if (!_ctrl.showSkeleton.value) return const SizedBox.shrink();
                  final sk = _ctrl.skeleton.value;
                  if (sk == null) return const SizedBox.shrink();
                  return CustomPaint(
                    painter: HandSkeletonPainter(
                      landmarks: sk,
                      visible: true,
                      useRawCoordinates: true,
                    ),
                  );
                }),
              ),

              // ── 状态栏 + 底部 / 侧栏 ─────────────────────────────────────
              if (isLandscape)
                // 横屏：右侧固定一列容纳状态栏 + 表达式 + 控制按钮。
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: sidePanelW,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    padding: EdgeInsets.fromLTRB(
                      10,
                      topPadding + 10,
                      10,
                      bottomPadding + 10,
                    ),
                    child: Obx(() {
                      return Column(
                        children: [
                          _buildStatusBar(),
                          const SizedBox(height: 8),
                          if (_cameraReady)
                            Expanded(
                              child: SingleChildScrollView(
                                child: _buildBottomPanel(),
                              ),
                            ),
                        ],
                      );
                    }),
                  ),
                )
              else ...[
                Positioned(
                  top: topPadding + 10,
                  left: 10,
                  right: 10,
                  child: Obx(() => _buildStatusBar()),
                ),
                if (_cameraReady)
                  Positioned(
                    bottom: bottomPadding + 12,
                    left: 12,
                    right: 12,
                    child: Obx(() => _buildBottomPanel()),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Widget builders
  // ---------------------------------------------------------------------------

  Widget _buildPreview() {
    // Android 端 Preview 的 targetRotation 钉在 ROTATION_0，纹理里的画面只相对
    // 设备自然朝向摆正，屏幕转到哪在这里补一个 RotatedBox；iOS 恒为 0 圈。
    final shownW = _previewTurns.isEven ? _previewW : _previewH;
    final shownH = _previewTurns.isEven ? _previewH : _previewW;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: shownW,
          height: shownH,
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

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _ctrl.statusColor.value,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppGlyphText(
              _ctrl.statusText.value,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          if (_cameraReady && !_ctrl.demoMode.value)
            Text(
              'FPS: ${_ctrl.fps.value.toStringAsFixed(1)}',
              style: TextStyle(
                color: _ctrl.fps.value >= 20
                    ? Colors.green
                    : _ctrl.fps.value >= 10
                    ? Colors.orange
                    : Colors.red,
                fontSize: 14,
              ),
            ),
          const SizedBox(width: 8),
          // API Key 设置
          GestureDetector(
            onTap: () => _showApiKeyDialog(context),
            child: Icon(
              _ctrl.voiceService.hasApiKey
                  ? Icons.settings
                  : Icons.settings_outlined,
              color: _ctrl.voiceService.hasApiKey
                  ? Colors.greenAccent
                  : Colors.white38,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    final demo = _ctrl.demoMode.value;
    final exprFontSize = demo ? 32.0 : 22.0;
    final resultFontSize = demo ? 38.0 : 24.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 表达式 + 结果显示 ─────────────────────────────────────────
        if (_ctrl.expression.isNotEmpty || _ctrl.calcResult.value.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: demo ? 16 : 12,
            ),
            decoration: BoxDecoration(
              color: demo ? Colors.black : Colors.black87,
              borderRadius: BorderRadius.circular(12),
              border: demo ? Border.all(color: Colors.white24, width: 1) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 表达式：各 token 可单独点击编辑
                if (_ctrl.expression.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < _ctrl.expression.length; i++)
                          GestureDetector(
                            onTap: () => _showTokenEditDialog(context, i),
                            child: Container(
                              margin: const EdgeInsets.only(right: 2),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Math.tex(
                                _ctrl.expression[i],
                                textStyle: TextStyle(
                                  color: const Color(0xFFFFD040),
                                  fontSize: exprFontSize,
                                ),
                                onErrorFallback: (_) => Text(
                                  _ctrl.expression[i],
                                  style: TextStyle(
                                    color: const Color(0xFFFFD040),
                                    fontSize: exprFontSize,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                // 结果：LaTeX 渲染（带 "=" 前缀，长按复制）
                if (_ctrl.calcResult.value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onLongPress: () {
                        _ctrl.copyResultToClipboard();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('copied_result'.tr),
                            duration: const Duration(milliseconds: 1200),
                          ),
                        );
                      },
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Math.tex(
                          _ctrl.calcResult.value,
                          textStyle: TextStyle(
                            color: const Color(0xFF3CDC78),
                            fontSize: resultFontSize,
                          ),
                          onErrorFallback: (e) => Text(
                            _ctrl.calcResult.value,
                            style: TextStyle(
                              color: const Color(0xFF3CDC78),
                              fontSize: resultFontSize,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

        // ── 控制栏 ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 第一行：识别 / 计算 / 删除 / 清式 / 语音
              Row(
                children: [
                  _buildBtn(
                    icon: _ctrl.isRecognizing.value
                        ? Icons.hourglass_empty
                        : Icons.text_fields,
                    label: 'recognize'.tr,
                    onTap: _ctrl.isRecognizing.value
                        ? () {}
                        : _ctrl.recognizeNow,
                    isActive: _ctrl.isRecognizing.value,
                  ),
                  const SizedBox(width: 4),
                  _buildBtn(
                    icon: Icons.calculate_outlined,
                    label: 'calculate'.tr,
                    onTap: _ctrl.calculate,
                  ),
                  const SizedBox(width: 4),
                  _buildBtn(
                    icon: Icons.backspace_outlined,
                    label: 'delete'.tr,
                    onTap: _ctrl.deleteLastToken,
                  ),
                  const SizedBox(width: 4),
                  _buildBtn(
                    icon: Icons.clear_all,
                    label: 'clear_expr'.tr,
                    onTap: _ctrl.clearExpression,
                  ),
                  const SizedBox(width: 4),
                  // 语音按钮：长按录音，松手发送
                  Expanded(
                    child: GestureDetector(
                      onLongPressStart: (_) => _ctrl.startVoiceRecording(),
                      onLongPressEnd: (_) =>
                          _ctrl.stopVoiceRecordingAndProcess(),
                      child: Obx(
                        () => Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _ctrl.isRecordingVoice.value
                                ? Colors.redAccent.withValues(alpha: 0.4)
                                : Colors.white12,
                            borderRadius: BorderRadius.circular(8),
                            border: _ctrl.isRecordingVoice.value
                                ? Border.all(
                                    color: Colors.redAccent,
                                    width: 1.5,
                                  )
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _ctrl.isRecordingVoice.value
                                    ? Icons.mic
                                    : Icons.mic_none,
                                color: _ctrl.isRecordingVoice.value
                                    ? Colors.redAccent
                                    : Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'voice'.tr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // 语音状态提示
              Obx(() {
                final s = _ctrl.voiceStatusText.value;
                if (s.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: AppGlyphText(
                    s,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                );
              }),
              const SizedBox(height: 6),
              // 第二行：清画 / 骨架(非演示) / 笔画数(非演示) / 公式 / 历史 / 演示
              // 按钮多时横向滚动，避免溢出
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildBtn(
                      icon: Icons.delete_outline,
                      label: 'clear_canvas'.tr,
                      onTap: () {
                        _ctrl.clearCanvas();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('cleared_canvas'.tr),
                            duration: const Duration(milliseconds: 400),
                          ),
                        );
                      },
                    ),
                    if (!demo) ...[
                      const SizedBox(width: 4),
                      _buildBtn(
                        icon: _ctrl.showSkeleton.value
                            ? Icons.visibility
                            : Icons.visibility_off,
                        label: 'skeleton'.tr,
                        onTap: _ctrl.toggleSkeleton,
                        isActive: _ctrl.showSkeleton.value,
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${'strokes_label'.tr}${_ctrl.strokeCount.value}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    _buildBtn(
                      icon: Icons.functions,
                      label: 'formula'.tr,
                      onTap: () async {
                        // 父页面摄像头已占用，禁止公式编辑器再次初始化摄像头
                        final result = await openFormulaEditor(
                          context,
                          allowCamera: false,
                        );
                        if (!mounted) return;
                        if (result != null && result.isNotEmpty) {
                          _ctrl.expression.add(result);
                          _ctrl.calcResult.value = '';
                        }
                      },
                    ),
                    const SizedBox(width: 4),
                    _buildBtn(
                      icon: Icons.history,
                      label: 'history'.tr,
                      onTap: () => _showHistorySheet(context),
                    ),
                    const SizedBox(width: 4),
                    _buildBtn(
                      icon: demo
                          ? Icons.present_to_all
                          : Icons.present_to_all_outlined,
                      label: 'demo'.tr,
                      onTap: _ctrl.toggleDemoMode,
                      isActive: demo,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showHistorySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        minChildSize: 0.25,
        builder: (_, scrollCtrl) => Obx(() {
          final hist = _ctrl.history;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'calc_history'.tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (hist.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          _ctrl.clearHistory();
                        },
                        child: Text(
                          'clear'.tr,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              if (hist.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      'no_records'.tr,
                      style: const TextStyle(color: Colors.white38),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    controller: scrollCtrl,
                    itemCount: hist.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Colors.white12, height: 1),
                    itemBuilder: (_, i) {
                      final entry = hist[i];
                      final exprStr = entry.expression.join('');
                      final timeStr =
                          '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                          '${entry.timestamp.minute.toString().padLeft(2, '0')}';
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        title: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Math.tex(
                                exprStr,
                                textStyle: const TextStyle(
                                  color: Color(0xFFFFD040),
                                  fontSize: 18,
                                ),
                                onErrorFallback: (_) => Text(
                                  exprStr,
                                  style: const TextStyle(
                                    color: Color(0xFFFFD040),
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Math.tex(
                                '= ${entry.result}',
                                textStyle: const TextStyle(
                                  color: Color(0xFF3CDC78),
                                  fontSize: 18,
                                ),
                                onErrorFallback: (_) => Text(
                                  '= ${entry.result}',
                                  style: const TextStyle(
                                    color: Color(0xFF3CDC78),
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: Text(
                          timeStr,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          _ctrl.restoreFromHistory(entry);
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('restored_history'.tr),
                              duration: const Duration(milliseconds: 800),
                            ),
                          );
                        },
                        onLongPress: () {
                          final text =
                              '${entry.expression.join('')} = ${entry.result}';
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('copied'.tr),
                              duration: const Duration(milliseconds: 800),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  // ── Token 编辑对话框 ────────────────────────────────────────────────────────

  Future<void> _showTokenEditDialog(BuildContext context, int index) async {
    final current = _ctrl.expression[index];
    // 弹出选项：编辑 or 删除
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Math.tex(
              current,
              textStyle: const TextStyle(
                color: Color(0xFFFFD040),
                fontSize: 26,
              ),
              onErrorFallback: (e) => Text(
                current,
                style: const TextStyle(color: Color(0xFFFFD040), fontSize: 18),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.white70),
            title: Text(
              'edit_in_formula_editor'.tr,
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () => Navigator.pop(sheetCtx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: Text(
              'delete_this_item'.tr,
              style: const TextStyle(color: Colors.redAccent),
            ),
            onTap: () => Navigator.pop(sheetCtx, 'delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );

    if (!context.mounted) return;
    if (action == 'delete') {
      if (index < _ctrl.expression.length) {
        _ctrl.expression.removeAt(index);
        _ctrl.calcResult.value = '';
      }
    } else if (action == 'edit') {
      final result = await openFormulaEditor(
        context,
        initial: current,
        allowCamera: false,
      );
      if (result != null && index < _ctrl.expression.length) {
        _ctrl.replaceToken(index, result);
      }
    }
  }

  // ── API Key 设置对话框 ──────────────────────────────────────────────────────

  void _showApiKeyDialog(BuildContext context) {
    final keyCtrl = TextEditingController(
      text: _ctrl.voiceService.apiKey ?? '',
    );
    final urlCtrl = TextEditingController(text: _ctrl.voiceService.baseUrl);

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          'api_settings'.tr,
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'api_settings_hint'.tr,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text(
              'Base URL',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                hintText: 'https://api.openai.com',
                hintStyle: const TextStyle(color: Colors.white30),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'API Key',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: keyCtrl,
              style: const TextStyle(color: Colors.white),
              obscureText: true,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                hintText: 'sk-...',
                hintStyle: const TextStyle(color: Colors.white30),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'cancel'.tr,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () async {
              await _ctrl.saveApiSettings(
                key: keyCtrl.text.trim(),
                baseUrl: urlCtrl.text.trim(),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: Text('save'.tr, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white24 : Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
