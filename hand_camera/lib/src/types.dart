part of '../hand_camera.dart';

class NormalizedLandmark {
  final double x, y, z;
  const NormalizedLandmark({required this.x, required this.y, required this.z});

  factory NormalizedLandmark._fromMap(Map<Object?, Object?> m) =>
      NormalizedLandmark(
        x: (m['x'] as num).toDouble(),
        y: (m['y'] as num).toDouble(),
        z: (m['z'] as num).toDouble(),
      );
}

class HandLandmarks {
  final String handedness;
  final double handednessScore;
  final List<NormalizedLandmark> landmarks;
  final List<NormalizedLandmark> worldLandmarks;

  const HandLandmarks({
    required this.handedness,
    required this.handednessScore,
    required this.landmarks,
    required this.worldLandmarks,
  });

  factory HandLandmarks._fromMap(Map<Object?, Object?> m) => HandLandmarks(
        handedness: m['handedness'] as String? ?? 'Unknown',
        handednessScore: (m['handednessScore'] as num?)?.toDouble() ?? 0.0,
        landmarks: (m['landmarks'] as List<dynamic>? ?? [])
            .map((e) => NormalizedLandmark._fromMap(e as Map<Object?, Object?>))
            .toList(),
        worldLandmarks: (m['worldLandmarks'] as List<dynamic>? ?? [])
            .map((e) => NormalizedLandmark._fromMap(e as Map<Object?, Object?>))
            .toList(),
      );
}

/// 纹理里那幅画面的尺寸，以及界面相对设备自然朝向转了多少度。
///
/// Android 端把 `Preview.targetRotation` 钉在 `ROTATION_0`：SurfaceTexture 的
/// 变换矩阵只把画面从 sensor 朝向摆到设备的**自然**朝向，所以 [width]/[height]
/// 绑定后就不再变（不随启动姿势、也不随旋转）。屏幕转到哪，由这里的
/// [quarterTurns] 交给一个 `RotatedBox` 补上。
///
/// iOS 端靠 `AVCaptureConnection.videoOrientation`，buffer 本来就跟显示同朝向，
/// 因此 [displayRotation] 恒为 0，[quarterTurns] 也就是 0，行为和以前一致。
class HandCameraPreviewSize {
  final int width;
  final int height;

  /// 界面相对设备自然朝向的角度（0/90/180/270）。iOS 恒为 0。
  final int displayRotation;

  const HandCameraPreviewSize({
    required this.width,
    required this.height,
    this.displayRotation = 0,
  });

  /// Surface 旋转角 → 逆时针的 90 度次数（0→0, 90→3, 180→2, 270→1）。
  int get quarterTurns => (4 - (displayRotation ~/ 90) % 4) % 4;

  /// 转过之后的尺寸：奇数次旋转宽高对调。
  int get rotatedWidth => quarterTurns.isEven ? width : height;
  int get rotatedHeight => quarterTurns.isEven ? height : width;
}

class HandCameraInitResult {
  final int textureId;

  /// Android sensor rotation degrees (0/90/180/270). iOS always 0.
  final int sensorOrientation;

  /// Actual resolution written to the preview SurfaceTexture (sensor/landscape space).
  /// Use this for the SizedBox in _buildPreview so the transform matrix has no scale factor.
  final int previewWidth;
  final int previewHeight;

  /// ImageAnalysis output resolution (sensor/landscape space).
  /// Use this for landmark coordinate transform (MediaPipe operates on this frame).
  final int cameraWidth;
  final int cameraHeight;

  const HandCameraInitResult({
    required this.textureId,
    required this.sensorOrientation,
    this.previewWidth = 640,
    this.previewHeight = 480,
    this.cameraWidth = 640,
    this.cameraHeight = 480,
  });
}
