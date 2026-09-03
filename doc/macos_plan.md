# macOS 端实现计划

## 一、hand_camera 插件：手部关键点方案调研

### 1.1 现状

iOS 端使用 `MediaPipeTasksVision` CocoaPod（封装 Google MediaPipe 的 HandLandmarker），提供 21 个 3D 手部关节点检测。

### 1.2 MediaPipeTasksVision 能否直接用于 macOS？

**结论：不能直接用，但可以自己编译。**

- MediaPipe 本身是 **Apache 2.0 开源**的（[github.com/google-ai-edge/mediapipe](https://github.com/google-ai-edge/mediapipe)）
- `MediaPipeTasksVision` podspec 只声明 `s.platform = :ios, '15.0'`，**不含 macOS**
- 官方 Hand Landmarker 文档只列出 Android / Web / Python / iOS 四个平台
- C++ 核心代码是平台无关的 `cc_library`，理论上可以编译到 macOS
- 社区有 macOS 编译需求（GitHub issue [#6167](https://github.com/google-ai-edge/mediapipe/issues/6167) "Swift Package Manager support"，已 assign maintainer 但尚未完成）
- 已知问题：macOS 15.2 上 zlib 版本不兼容、Bazel 构建链复杂

### 1.3 三个可行方案

| 方案 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **A: 提取 TFLite 模型 + TensorFlowLiteC** | 从 .task bundle 中提取 palm_detection + hand_landmark 两个 TFLite 模型，通过 `TensorFlowLiteC` CocoaPod（支持 macOS）自行推理 | 完全可控，TFLite pod 支持 macOS | 需要重新实现 MediaPipe 的预处理（手掌检测 → ROI 裁剪 → 关键点回归）和后处理，工作量大 |
| **B: 从源码 Bazel 编译 MediaPipe** | 拉取 mediapipe 源码，用 Bazel 编译 .xcframework for macOS | 得到完整 MediaPipe pipeline，与 iOS 行为完全一致 | Bazel 构建链复杂，macOS 上已知有编译问题（zlib 等），维护成本高 |
| **C: Apple Vision 原生 API** | 使用系统内置 `VNDetectHumanHandPoseRequest`（macOS 12+），零外部依赖 | 最简单，无编译，CoreML 自动加速 | 关键点格式与 MediaPipe 不同（需归一化适配），行为细节可能有差异 |

### 1.4 推荐

**首选方案 A（TFLite 自跑）**：TensorFlowLiteC pod 明确支持 macOS，模型文件从现有 `hand_landmarker.task` 中提取。预处理/后处理的 C++ 代码也在 MediaPipe 源码中可直接参考移植。

### 1.5 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `hand_camera/macos/Classes/HandCameraPlugin.swift` | 新增 ~300 行 | AVFoundation 摄像头 + TFLite 推理 pipeline |
| `hand_camera/macos/hand_camera.podspec` | 新增 ~25 行 | 依赖 `TensorFlowLiteC`（非 MediaPipeTasksVision） |
| `hand_camera/macos/Resources/PrivacyInfo.xcprivacy` | 新增 | 从 iOS 复制 |
| `hand_camera/pubspec.yaml` | 修改 +5 行 | 添加 macOS platform 注册 |

## 二、推理引擎：macOS 走 ExecuTorch + CoreML

与 iOS 完全一致（两个平台都是 Apple Silicon + CoreML + ANE）。

| 文件 | 行号 | 当前代码 | 改为 |
|------|------|---------|------|
| `lib/services/mathwriting_recognition_service.dart` | 58 | `Platform.isAndroid ? 'tflite_fp32' : 'executorch_coreml'` | 不变，macOS 也落入 else |
| `lib/services/mathwriting_recognition_service.dart` | 99 | `if (Platform.isAndroid)` | 不变 |
| `lib/services/mathwriting_recognition_service.dart` | 194,216,237 | 同上 | 不变 |
| `lib/services/mwh_litert_engine.dart` | 119-123 | `Platform.isIOS ? CoreML : Platform.isAndroid ? XNNPACK : auto` | 添加 `Platform.isMacOS ? CoreML` |
| `lib/pages/formula_editor_page.dart` | 317 | `Platform.isAndroid ? gpu : auto` | 不变 |
| `lib/controllers/air_writing_controller.dart` | 142 | 同上 | 不变 |

## 三、模型文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `tool/copy_platform_models.sh` | 修改 | 添加 `macos` case，拷贝 iOS 的 `.pte` 文件 |
| `platform_models/macos/` | 新增软链 | 指向 `platform_models/ios/`（模型完全相同） |

## 四、Rust / flutter_rust_bridge

| 文件 | 行号 | 当前代码 | 改为 |
|------|------|---------|------|
| `lib/main.dart` | 36 | `Platform.isIOS ? ExternalLibrary.process` | `Platform.isIOS \|\| Platform.isMacOS ? ExternalLibrary.process` |

## 五、macOS Runner 配置（权限 + entitlement）

| 文件 | 操作 | 说明 |
|------|------|------|
| `macos/Runner/Info.plist` | 修改 | 添加 `NSCameraUsageDescription`、`NSMicrophoneUsageDescription` |
| `macos/Runner/DebugProfile.entitlements` | 修改 | 添加 `com.apple.security.device.camera`、`com.apple.security.device.audio-input` |
| `macos/Runner/Release.entitlements` | 修改 | 同上 |

## 六、Dart 层 Platform 分支修正（7 个文件，~15 处）

所有 `Platform.isAndroid` / `Platform.isIOS` 二分支的地方，macOS 应落入 iOS 分支。

| 文件 | 行号 | 改动 |
|------|------|------|
| `lib/main.dart` | 36 | `Platform.isIOS` → `Platform.isIOS \|\| Platform.isMacOS` |
| `lib/controllers/air_writing_controller.dart` | 59 | `Platform.isIOS` → `isIOS \|\| isMacOS`（TTS） |
| `lib/controllers/air_writing_controller.dart` | 443 | `Platform.isAndroid` → 加 `!Platform.isMacOS`（camera portrait 判断） |
| `lib/pages/air_writing_page.dart` | 81 | `sensorOrientation` 赋值：macOS 落入 `: 0` 分支 |
| `lib/pages/air_writing_page.dart` | 151 | `screenSize` 计算：macOS 走 iOS 路径 |
| `lib/pages/formula_editor/camera_logic.dart` | 68 | `sensorOrientation` 赋值：macOS 落入 `: 0` 分支 |
| `lib/pages/formula_editor_page.dart` | 793 | `Platform.isIOS` → 加 macOS（TTS） |
| `lib/pages/formula_editor_page.dart` | 881 | `screenSize` 计算：macOS 走 iOS 路径 |

## 七、不走的部分

| 模块 | 原因 |
|------|------|
| `sensors_plus` | macOS 无重力传感器，app 已用写字起点象限判定替代 |
| `permission_handler` | macOS 相机/麦克风权限走 entitlement，不需要运行时弹窗 |
| `flutter_tts` | macOS 原生 TTS 通过 `AVSpeechSynthesizer`，`flutter_tts` 不声明 macOS 支持，需在 controller 中跳过 `setSharedInstance`/`setIosAudioCategory`（仅 iOS 需要） |

总改动量估计：~100 行新增（插件 + podspec），~30 行修改（Dart 分支修补 + 权限配置），主 App 代码无需架构变更。
