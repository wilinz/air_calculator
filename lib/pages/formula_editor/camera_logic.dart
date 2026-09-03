// ─── 摄像头生命周期（toggle/start/stop）─────────────────────────────────
part of '../formula_editor_page.dart';

extension _CameraLogic on _FormulaEditorPageState {
  Future<void> _toggleCamera() async {
    debugPrint(
      '[FormulaEditor] _toggleCamera tapped, busy=$_cameraBusy airMode=$_airMode modelReady=$_modelReady',
    );
    if (_cameraBusy) return; // 防止快速重复点击导致并发 init/dispose
    _cameraBusy = true;
    if (mounted) setState(() {});
    try {
      if (_airMode) {
        await _stopCamera();
      } else {
        await _startCamera();
      }
    } finally {
      _cameraBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _startCamera() async {
    // macOS: permission_handler 无 macOS 实现，依赖 sandbox entitlement +
    // NSCameraUsageDescription，系统在首次 AVCaptureSession 使用时自动弹窗
    if (!Platform.isMacOS) {
      var status = await Permission.camera.status;
      if (status.isDenied || status.isRestricted) {
        status = await Permission.camera.request();
      }
      if (!status.isGranted && !status.isLimited) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status.isPermanentlyDenied
                  ? 'camera_perm_perma_denied'.tr
                  : 'camera_perm_denied'.tr,
            ),
            duration: const Duration(seconds: 3),
            action: status.isPermanentlyDenied
                ? SnackBarAction(
                    label: 'open_settings'.tr,
                    onPressed: openAppSettings,
                  )
                : null,
          ),
        );
        return;
      }
    }

    // 等待手写模型就绪（全局单例，可能已在其他页面初始化）
    if (!_modelReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('model_loading_wait'.tr),
          duration: const Duration(seconds: 2),
        ),
      );
      // 等待模型就绪后自动打开摄像头，避免用户反复点击
      unawaited(
        _recService.init().then((ok) {
          if (ok && mounted) {
            setState(() => _modelReady = true);
            unawaited(_startCamera());
          }
        }),
      );
      return;
    }

    try {
      // 关键：先完成摄像头初始化，成功后才切换 airMode，
      // 避免双 Scaffold 重建期间 MediaPipe GL 初始化冲突
      final result = await HandCamera.initialize(numHands: 1);
      if (!mounted) return;

      _sensorOrientation = Platform.isAndroid ? result.sensorOrientation : 0;
      // previewWidth/Height 是纹理里画面摆正后的尺寸（Android 上相对设备自然
      // 朝向，恒定）。界面朝向对应的 quarterTurns 由 previewSizeStream 推来，
      // 绑定完成时就会推第一帧，之后每次旋转再推。
      setState(() {
        _previewW = result.previewWidth.toDouble();
        _previewH = result.previewHeight.toDouble();
        _textureId = result.textureId;
        _cameraReady = true;
        _airMode = true; // ← 成功后才切换
        _airStatusText = () => 'put_hand_in_view'.tr;
        _airStatusColor = Colors.green;
        // 重建 TabController 以容纳额外的 [Air] tab，并自动切到 0（Air）
        _rebuildTabController(airMode: true, initialIndex: 0);
      });

      _landmarkSub = HandCamera.landmarkStream.listen(_onLandmarks);
    } catch (e, st) {
      debugPrint('[FormulaEditor] camera init failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${'camera_init_failed_prefix'.tr}$e'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(label: 'retry'.tr, onPressed: _startCamera),
        ),
      );
    }
  }

  Future<void> _stopCamera() async {
    // 先取消订阅，杜绝 dispose 流程中再有相机帧到达
    await _landmarkSub?.cancel();
    _landmarkSub = null;

    // 在 widget tree 还正常时清空 ValueNotifier；setState 之后绝不再赋值，
    // 避免 ValueListenableBuilder 在卸载过程中收到通知 → _dependents.isEmpty assertion
    _airSkeletonVN.value = null;
    _airIndicatorVN.value = null;
    _isAirDrawingVN.value = false;
    _airCanvasTickVN.value = 0;

    if (_cameraReady) {
      await HandCamera.dispose(); // 必须 await，否则 native session 未释放就再次 initialize 会报 INIT_ERROR
      // iOS AVCaptureSession 异步关闭，给原生端额外缓冲时间
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (!mounted) return;
    setState(() {
      _airMode = false;
      _scissorMode = false;
      _cameraReady = false;
      _permGranted = false;
      _textureId = null;
      _isAirDrawing = false;
      _airCanvas.clear();
      _airPicCache.picture = null;
      _airStrokeCount = 0;
      // 退回非空中模式，TabController 缩回 length=7（[手写, ...类别]）
      _rebuildTabController(airMode: false, initialIndex: 0);
    });
    _scissorVN.value = null;
    _scissorTargetIdx = null;
    _scissorDwellStart = null;
    _airClick.setAllowedIds(null);
    _ptTracker.reset();
  }
}
