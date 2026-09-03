import 'dart:async';
import 'package:flutter/services.dart';

part 'src/types.dart';

class HandCamera {
  HandCamera._();

  static const _method = MethodChannel('hand_camera');
  static const _events = EventChannel('hand_camera/landmarks');
  static const _previewSize = EventChannel('hand_camera/preview_size');

  static Stream<List<HandLandmarks>>? _stream;
  static Stream<HandCameraPreviewSize>? _sizeStream;

  /// Opens the front camera and starts LIVE_STREAM hand detection.
  ///
  /// Returns a [HandCameraInitResult] with:
  /// - [HandCameraInitResult.textureId] — pass to `Texture(textureId: ...)` for preview.
  /// - [HandCameraInitResult.sensorOrientation] — sensor rotation in degrees (Android only).
  ///
  /// [modelAssetPath] 指向模型所在目录下的任一文件；实现只取它的目录部分，
  /// 在同目录下找 `hand_detector.pte` 与 `hand_landmarks_detector.pte`。
  static Future<HandCameraInitResult> initialize({
    int numHands = 1,
    double minHandDetectionConfidence = 0.5,
    double minHandPresenceConfidence = 0.5,
    double minTrackingConfidence = 0.5,
    String modelAssetPath =
        'packages/hand_camera/assets/models/hand_detector.pte',
  }) async {
    final result =
        await _method.invokeMapMethod<String, dynamic>('initialize', {
      'numHands': numHands,
      'minHandDetectionConfidence': minHandDetectionConfidence,
      'minHandPresenceConfidence': minHandPresenceConfidence,
      'minTrackingConfidence': minTrackingConfidence,
      'modelAssetPath': 'flutter_assets/$modelAssetPath',
    });
    return HandCameraInitResult(
      textureId: result!['textureId'] as int,
      sensorOrientation: result['sensorOrientation'] as int? ?? 0,
      previewWidth: result['previewWidth'] as int? ?? 480,
      previewHeight: result['previewHeight'] as int? ?? 640,
      cameraWidth: result['cameraWidth'] as int? ?? 480,
      cameraHeight: result['cameraHeight'] as int? ?? 640,
    );
  }

  /// Broadcast stream of hand landmark results from the camera.
  /// Each event contains one entry per detected hand (usually 0 or 1).
  static Stream<List<HandLandmarks>> get landmarkStream {
    _stream ??= _events.receiveBroadcastStream().map((event) {
      final list = event as List<dynamic>;
      return list
          .map((e) => HandLandmarks._fromMap(e as Map<Object?, Object?>))
          .toList();
    });
    return _stream!;
  }

  /// 预览画面尺寸与界面朝向的实时流。
  ///
  /// native 端会在朝向变化时主动推送：
  /// - iOS：`AVCaptureConnection.videoOrientation` 已根据设备朝向更新，
  ///   所以 buffer 跟显示同朝向，宽高随之变化，`displayRotation` 恒为 0。
  /// - Android：画面在纹理里始终相对设备**自然**朝向摆正，宽高恒定；
  ///   界面转了多少度由 `displayRotation` 报出来。
  ///
  /// 调用方按 [HandCameraPreviewSize.rotatedWidth]/[HandCameraPreviewSize.rotatedHeight]
  /// 设外层 `SizedBox`，中间套一个 `RotatedBox(quarterTurns: size.quarterTurns)`，
  /// 里层再用原始 width/height 包住 `Texture`。
  static Stream<HandCameraPreviewSize> get previewSizeStream {
    _sizeStream ??= _previewSize.receiveBroadcastStream().map((event) {
      final m = event as Map<Object?, Object?>;
      return HandCameraPreviewSize(
        width: (m['width'] as num).toInt(),
        height: (m['height'] as num).toInt(),
        // iOS 不发这个键：buffer 已跟显示同朝向，等价于 0。
        displayRotation: (m['displayRotation'] as num?)?.toInt() ?? 0,
      );
    });
    return _sizeStream!;
  }

  /// Stops the camera and releases all native resources.
  /// 只加载并预热手部检测模型，不启动相机。
  ///
  /// 首次安装后 Core ML 要编译两个模型（几秒）。在 App 启动时调一次，
  /// 趁用户还没进空中书写页时做掉；之后 [initialize] 会跳过重复加载。
  ///
  /// 失败不抛异常——预热只是提前量，进页面时还会再试一次。
  static Future<bool> warmUp({
    String modelAssetPath =
        'packages/hand_camera/assets/models/hand_detector.pte',
  }) async {
    try {
      final ok = await _method.invokeMethod<bool>('warmUp', {
        'modelAssetPath': 'flutter_assets/$modelAssetPath',
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> dispose() async {
    _stream = null;
    _sizeStream = null;
    await _method.invokeMethod<void>('dispose');
  }
}
