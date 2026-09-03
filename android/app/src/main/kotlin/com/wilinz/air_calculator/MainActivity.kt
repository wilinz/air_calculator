package com.wilinz.air_calculator

import io.flutter.embedding.android.FlutterActivity

/**
 * 没有需要手工注册的插件。
 *
 * 手部检测原先由本模块的 HandDetectorPlugin（MediaPipe + CameraX）提供，
 * 现已整体让给 hand_camera 插件——三端同一份 aircalc 原生核心。那份实现连同
 * MediaPipe 依赖一起删了；Dart 侧早已没有任何地方引用它的通道与平台视图。
 */
class MainActivity : FlutterActivity()
