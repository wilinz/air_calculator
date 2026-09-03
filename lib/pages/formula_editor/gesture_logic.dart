// ─── 手势识别处理（landmarks / 剪刀模式）─────────────────────────────
part of '../formula_editor_page.dart';

extension _GestureLogic on _FormulaEditorPageState {
  void _onLandmarks(List<HandLandmarks> hands) {
    // 帧率统计
    final now = DateTime.now().millisecondsSinceEpoch;
    _frameTimestamps.add(now);
    while (_frameTimestamps.length > _FormulaEditorPageState._kFpsWindow) _frameTimestamps.removeAt(0);
    if (_frameTimestamps.length >= 2) {
      final elapsed = (now - _frameTimestamps.first) / 1000.0;
      final fps = ((_frameTimestamps.length - 1) / elapsed).round();
      if (fps != _fpsVN.value) _fpsVN.value = fps;
    }

    if (hands.isEmpty) {
      _onAirHandDetected(null);
    } else {
      _onAirHandDetected(hands.first);
    }
  }

  void _onAirHandDetected(HandLandmarks? hand) {
    // 防御：相机已关闭后仍有事件循环里排队的 callback 到达
    if (!_airMode) return;
    if (hand == null) {
      _airSkeletonVN.value = null;
      _airIndicatorVN.value = null;
      _airClick.update(null);
      _airClickSafe.update(null);
      // 剪刀模式：手消失时清除 overlay 并重置 dwell
      if (_scissorMode) {
        _scissorVN.value = null;
        _scissorTargetIdx = null;
        _scissorDwellStart = null;
      }
      // 滑动模式：手消失立即清除 indicator 并退出
      _airSwipeMode = false;
      _airSwipeDwellStart = null;
      _airSwipeLastX = null;
      _airSwipeActivatedY = null;
      _airSwipeLostFrames = 0;
      _airSwipeVN.value = null;
      // 也结束未完成的笔画，避免下次手回来续接到错误位置
      if (_airCanvas.currentStroke != null) {
        _airCanvas.currentStroke!.trimTail(enabled: true);
        _airCanvas.currentStroke!.smooth();
        _airCanvas.endStroke();
        _ptTracker.reset();
        _drawLostFrames = 0;
        _airCanvasTickVN.value++;
      }
      _isAirDrawingVN.value = false;
      if (_handDetected) {
        if (!mounted) return;
        setState(() {
          _handDetected = false;
          if (!_airRecognizing) {
            _airStatusText = () => 'put_hand_in_view'.tr;
            _airStatusColor = Colors.white70;
          }
        });
        _startAutoRecogCountdown();
      }
      return;
    }

    final sk = hand.landmarks.map((l) => _transformCoord(l.x, l.y)).toList();

    // 手部朝向：wrist(0) → middle_mcp(9)，屏幕空间下的角度（已含相机/屏幕变换）
    if (sk.length > 9) {
      final v = sk[9] - sk[0];
      if (v.distanceSquared > 1.0) {
        _airHandAngle = math.atan2(v.dy, v.dx);
      }
    }

    final gesture = _gestureRec.recognize(hand, _screenSize, mirrorX: false);

    // 食指尖（landmark 8）作为非绘制时的悬停指针
    Offset? fingertip;
    if (sk.length > 8) fingertip = sk[8];

    // ── 剪刀模式：用食指尖检测笔画并 dwell 删除 ──────────────────────────
    if (_scissorMode && fingertip != null) {
        // 剪刀模式下只允许悬停剪刀按钮本身
      _airClick.setEnabled(true);
      _airClick.update(fingertip);
      _airClickSafe.setEnabled(true);
      _airClickSafe.update(fingertip);
      if (_airClick.hoverVN.value != null) {
        // 悬停在剪刀按钮上：清除笔画命中状态
        _scissorVN.value = null;
        _scissorTargetIdx = null;
        _scissorDwellStart = null;
      } else {
        _updateScissor(fingertip!);
      }
      _airSkeletonVN.value = sk;
      _airIndicatorVN.value = null;
      _isAirDrawingVN.value = false;
      _airCanvasTickVN.value++;
      final newStrokeCount = _airCanvas.strokeCount;
      if (newStrokeCount != _airStrokeCount) {
        setState(() => _airStrokeCount = newStrokeCount);
      }
      return;
    }

    Offset? indicator = fingertip; // 默认显示食指尖位置
    if (gesture.drawingPoint != null) {
      final raw = _transformCoord(
        gesture.drawingPoint!.dx,
        gesture.drawingPoint!.dy,
      );
      // PointTracker 死区 + 速度自适应 EMA 平滑（在所有帧都跑，避免开始绘制时
      // 第一个 smoothed 因为 _lastPoint=null 直接返回 raw 导致开头一段不平滑）
      final smoothed = _ptTracker.update(raw);
      // 显示指针 = 平滑后的位置（与笔画落点一致，视觉看起来平滑）
      if (gesture.isDrawing) indicator = smoothed;

      final canDraw = _drawingEnabled && !_airSwipeMode && !gesture.isTwoFingerPinch;
      if (gesture.isDrawing && canDraw) {
        _drawLostFrames = 0;
        if (_airCanvas.currentStroke == null) {
          _airCanvas.startStroke();
          // 用户重新落笔 → 解除"撤销识别后抑制自动识别"的状态
          _suppressAutoRecog = false;
        }
        _airCanvas.addPoint(smoothed, pinchRatio: gesture.pinchRatio);
      } else if (_airCanvas.currentStroke != null && canDraw) {
        // isDrawing 短暂丢失：容忍几帧避免快速移动断笔
        _drawLostFrames++;
        if (_drawLostFrames > _FormulaEditorPageState._kDrawLostFramesTol) {
          _airCanvas.currentStroke!.trimTail(enabled: true);
          _airCanvas.currentStroke!.smooth();
          _airCanvas.endStroke();
          _ptTracker.reset();
          _drawLostFrames = 0;
        } else {
          // 容忍期内继续画，按上一帧 ratio 沿用
          _airCanvas.addPoint(smoothed, pinchRatio: gesture.pinchRatio);
        }
      } else if (_airCanvas.currentStroke != null) {
        // canDraw 不成立（如进入双指/滑动模式）→ 立即结束
        _airCanvas.currentStroke!.trimTail(enabled: true);
        _airCanvas.currentStroke!.smooth();
        _airCanvas.endStroke();
        _ptTracker.reset();
        _drawLostFrames = 0;
      }
    }

    // 高频更新
    _airSkeletonVN.value = sk;
    _airIndicatorVN.value = indicator;
    _isAirDrawingVN.value = gesture.isDrawing && _drawingEnabled;
    _airCanvasTickVN.value++;

    // 判断食指指尖是否在公式预览区内
    final previewBox = _previewKey.currentContext?.findRenderObject() as RenderBox?;
    final tipInPreview = previewBox != null && gesture.indexTip != null
        ? () {
            final tipScreen = _transformCoord(gesture.indexTip!.dx, gesture.indexTip!.dy);
            final previewRect = previewBox.localToGlobal(Offset.zero) & previewBox.size;
            return previewRect.contains(tipScreen);
          }()
        : false;

    // 五指张开立即识别
    if (gesture.isFullyOpen && _drawingEnabled && _airCanvas.strokeCount > 0 && !_airRecognizing) {
      _cancelAutoRecog();
      _airRecognizeNow();
      return;
    }

    // 空中按钮悬停点击：始终用食指尖做 hover 指针，绘制中禁用避免误点
    // 双指并拢且在预览区内（蓄力中或已激活）时禁用空中点击，避免同时触发
    final swipeBlocking = gesture.isTwoFingerPinch && (tipInPreview || _airSwipeMode);
    final airPointer = gesture.isIndexPointing ? fingertip : null;
    _airClick.setEnabled(!swipeBlocking);
    _airClick.update(airPointer);
    _airClickSafe.setEnabled(!swipeBlocking);
    _airClickSafe.update(airPointer);

    // 空中滑动：食指+中指并拢长按激活，横向拖拽滚动公式预览

    if (gesture.isTwoFingerPinch && gesture.indexTip != null && (tipInPreview || _airSwipeMode)) {
      _airSwipeLostFrames = 0; // 检测到，重置容错计数
      final tipScreen = _transformCoord(gesture.indexTip!.dx, gesture.indexTip!.dy);
      if (_airSwipeMode) {
        // 已激活：检查垂直越界
        final dy = (tipScreen.dy - _airSwipeActivatedY!).abs();
        if (dy > _FormulaEditorPageState._kSwipeVerticalCancel) {
          _airSwipeMode = false;
          _airSwipeDwellStart = null;
          _airSwipeLastX = null;
          _airSwipeActivatedY = null;
          _airSwipeLostFrames = 0;
          _airSwipeVN.value = null;
        } else {
          if (_airSwipeLastX != null && _previewScroll.hasClients) {
            final dx = _airSwipeLastX! - tipScreen.dx;
            if (dx.abs() > _FormulaEditorPageState._kSwipeDeadZone) {
              final target = (_previewScroll.offset + dx).clamp(
                0.0,
                _previewScroll.position.maxScrollExtent,
              );
              _previewScroll.jumpTo(target);
            }
          }
          _airSwipeLastX = tipScreen.dx;
          _airSwipeVN.value = _SwipeIndicatorState(tip: tipScreen, activated: true);
        }
      } else {
        // 未激活：计时等待长按
        _airSwipeDwellStart ??= DateTime.now();
        final elapsed = DateTime.now().difference(_airSwipeDwellStart!).inMilliseconds;
        final progress = (elapsed / _FormulaEditorPageState._kSwipeDwellMs).clamp(0.0, 1.0);
        _airSwipeVN.value = _SwipeIndicatorState(tip: tipScreen, activated: false, progress: progress);
        if (elapsed >= _FormulaEditorPageState._kSwipeDwellMs) {
          _airSwipeMode = true;
          _airSwipeActivatedY = tipScreen.dy;
          _airSwipeLastX = tipScreen.dx;
          HapticFeedback.selectionClick();
        }
      }
    } else if (_airSwipeMode || _airSwipeDwellStart != null) {
      // 检测短暂丢失：容错 N 帧再真正取消
      _airSwipeLostFrames++;
      if (_airSwipeLostFrames > _FormulaEditorPageState._kSwipeLostFramesTol) {
        _airSwipeMode = false;
        _airSwipeDwellStart = null;
        _airSwipeLastX = null;
        _airSwipeActivatedY = null;
        _airSwipeLostFrames = 0;
        _airSwipeVN.value = null;
      }
    }

    // 仅边沿触发 setState（绘制开始/停止、笔画数变化、首次检测到手）
    final newStrokeCount = _airCanvas.strokeCount;
    final drawingChanged = gesture.isDrawing != _isAirDrawing;
    final strokeChanged = newStrokeCount != _airStrokeCount;
    final handJustDetected = !_handDetected;
    if (!drawingChanged && !strokeChanged && !handJustDetected) return;

    // 手回来：取消自动识别倒计时
    _cancelAutoRecog();

    if (!mounted) return;
    setState(() {
      _handDetected = true;
      _isAirDrawing = gesture.isDrawing;
      _airStrokeCount = newStrokeCount;
      if (!_airRecognizing) {
        _airStatusText = gesture.isDrawing
            ? () => 'drawing_status'.tr
            : () => 'stopped'.tr;
        _airStatusColor = gesture.isDrawing ? Colors.green : Colors.orange;
      }
    });
  }

  void _updateScissor(Offset tip) {
    const hitThreshold = 40.0;
    int? hitIdx;
    double minDist = hitThreshold;
    final strokes = _airCanvas.strokes;
    for (int i = 0; i < strokes.length; i++) {
      for (final p in strokes[i].points) {
        final d = (p - tip).distance;
        if (d < minDist) {
          minDist = d;
          hitIdx = i;
        }
      }
    }

    if (hitIdx == null) {
      _scissorTargetIdx = null;
      _scissorDwellStart = null;
      _scissorVN.value = _ScissorOverlayState(tip: tip);
      return;
    }

    if (_scissorTargetIdx != hitIdx) {
      _scissorTargetIdx = hitIdx;
      _scissorDwellStart = DateTime.now();
    }

    final elapsed =
        DateTime.now().difference(_scissorDwellStart!).inMilliseconds;
    final progress = (elapsed / _FormulaEditorPageState._scissorDwellMs).clamp(0.0, 1.0);
    _scissorVN.value = _ScissorOverlayState(
      tip: tip,
      targetPoints: List.from(strokes[hitIdx].points),
      progress: progress,
    );

    if (progress >= 1.0) {
      _airCanvas.removeStrokeAt(hitIdx);
      _airPicCache.picture = null;
      _airCanvasTickVN.value++;
      _scissorTargetIdx = null;
      _scissorDwellStart = null;
      HapticFeedback.selectionClick();
    }
  }
}
