# air_calculator — 项目详情文档

毕业设计「空中手势交互型智能语音计算器」的 Flutter 端工程。负责相机采集、手部关键点解析、空中书写交互、端侧公式识别、表达式求值、中文语音播报。Python 训练与部署导出在同级 `air_calculator_py/` 中。

---

## 1. 功能实现

### 1.1 空中手势书写
- 单目 RGB 摄像头 + MediaPipe HandLandmarker（封装在自研插件 `hand_camera` 中）以 30 FPS 输出 21 个手部关键点。
- 以「拇指与食指捏合距离 / 手掌大小」的归一化比值作为笔状态信号，配合速度自适应滞回、指数移动平均（EMA）平滑与拉丝裁剪，将空中书写笔迹质量拉到接近触屏书写水平。
- 三类复合手势完成全部交互：**捏合书写**（落笔/抬笔）、**五指张开**（提交识别）、**悬停点击**（虚拟按键聚焦）。

### 1.2 端侧公式识别
- decoder-only prefix-LM 架构：DeiT-Small 图像编码器 + 轻量笔画 Transformer → 拼接为前缀 → 因果解码器输出 LaTeX。可训练参数 ~34.5 M。
- 分平台双 runtime：
  - **Android** 走 LiteRT（XNNPACK CPU + GpuDelegateV2 OpenCL），fp32，三件套 ~187 MB。
  - **iOS** 走 ExecuTorch CoreMLBackend，fp16，整图 lowering 到 ANE，三件套 ~138 MB。
- 三段拆分推理：`prefix_enc`（图像+笔画前缀编码） + `decoder_prefill`（KV 缓存预填） + `decoder_step`（单步解码）。KV-cache 让单步复杂度从平方级降到线性。
- iOS 端到端均值 ~147 ms（中位数 120 ms），Android 中端机 ~578 ms。

### 1.3 LaTeX 解析与求值
- Dart 端自实现 LaTeX 词法/语法解析（`flutter_math_fork` fork）+ `math_expressions` 数值求值。
- 支持四则、分式、根式、幂指数、三角对数、行列式等常见表达式，全部本地完成。

### 1.4 中文语音播报与语音指令
- `flutter_tts` 输出中文播报；自定义 `latex_speech.dart` 把 LaTeX 转为可朗读中文。
- 语音指令通道：`record` 采集 → 云端 Whisper 转写 → 云端 LLM 解析为 `append / replace / delete / clear / calculate` 五类操作 → 编辑当前公式。**仅这条通道需要联网**。

### 1.5 评测与基准
- `BenchmarkPage`：装载 `assets/benchmark_samples.jsonl`（从 MathWriting 抽样的 500 条 InkML），全量跑端侧时延 + 精度。
- 计时跑完后再算 ExpRate（strict / normalized）与 char-level CER，分桶（token 长度 1-3 / 4-8 / 9-16 / 17+），可导出 markdown 报告与 `results.jsonl`（供 `air_calculator_py/eval/mobile/eval_benchmark.py` 离线对照）。

---

## 2. 代码组织架构

```
air_calculator/
├── lib/
│   ├── main.dart                          # 入口 + GetMaterialApp + Rust bridge init + locale
│   ├── i18n/app_translations.dart         # GetX 多语言（中/英）
│   │
│   ├── models/gesture.dart                # Stroke / Gesture 等核心数据结构
│   │
│   ├── controllers/
│   │   └── air_writing_controller.dart    # 全局控制器：相机帧 → 手势状态机 → 笔画收集
│   │                                       # （捏合滞回、EMA 平滑、拉丝裁剪、自动提交节奏）
│   │
│   ├── services/                          # 端侧能力层（纯 Dart / FFI / 平台通道）
│   │   ├── mathwriting_recognition_service.dart  # 公式识别 facade：装载词表 + 选择 runtime
│   │   ├── mwh_inference_engine.dart             # Engine 抽象接口
│   │   ├── mwh_litert_engine.dart                # Android 用：LiteRT + XNNPACK/GPU delegate
│   │   ├── mwh_executorch_engine.dart            # iOS 用：ExecuTorch + CoreML
│   │   ├── sequence_feature_extractor.dart       # 笔画 13 维特征提取，与 Python 端 stroke_features.py 对齐
│   │   ├── stroke_rasterizer.dart                # 笔画 → 64×256 灰度图，与 Python 端 stroke_renderer.py 对齐
│   │   ├── gesture_recognizer.dart               # 捏合 / 张开 / 悬停的状态机
│   │   ├── point_tracker.dart                    # 指尖轨迹跟踪 + 平滑
│   │   └── voice_command_service.dart            # Whisper + LLM 语音指令通道
│   │
│   ├── utils/
│   │   └── latex_speech.dart              # LaTeX → 中文可朗读字符串
│   │
│   ├── pages/
│   │   ├── air_writing_page.dart          # 空中书写主页面（相机预览 + 笔画 overlay + 结果栏）
│   │   ├── formula_editor_page.dart       # 公式编辑器主页面（首页）
│   │   ├── formula_editor/                # 编辑器拆分子模块
│   │   │   ├── camera_logic.dart          #   相机会话 + landmark 订阅
│   │   │   ├── gesture_logic.dart         #   捏合/张开/悬停判定
│   │   │   ├── recognize_logic.dart       #   笔画 → 识别请求 → 结果应用
│   │   │   ├── air_render.dart            #   空中笔画 + 指针绘制
│   │   │   ├── preview_render.dart        #   实时预览渲染
│   │   │   ├── keyboard_data.dart         #   虚拟键位数据
│   │   │   ├── keyboard_render.dart       #   虚拟键盘绘制
│   │   │   ├── overlays.dart              #   各类弹层
│   │   │   ├── atoms.dart                 #   原子组件
│   │   │   ├── blinking_cursor.dart       #   光标动画
│   │   │   ├── rotation_utils.dart        #   屏幕旋转适配
│   │   │   └── theme.dart                 #   编辑器主题
│   │   └── benchmark_page.dart            # 端侧 benchmark 入口（时延 + ExpRate/CER）
│   │
│   ├── widgets/
│   │   ├── drawing_canvas.dart            # 笔画 CustomPainter
│   │   ├── touch_handwriting_pad.dart     # 触屏书写回退面板（兜底）
│   │   └── air_click.dart                 # 悬停点击交互控件
│   │
│   └── src/rust/                          # flutter_rust_bridge 自动生成的桥接代码
│       ├── frb_generated.dart / .io.dart / .web.dart
│       └── api/
│           ├── orient.dart                # 屏幕朝向工具（Rust 实现）
│           └── simple.dart                # 示例 API
│
├── assets/
│   ├── models/                            # 端侧模型权重
│   │   ├── prefix_enc.pte                 #   iOS encoder（ExecuTorch）
│   │   ├── decoder_prefill_kv.pte         #   iOS prefill
│   │   ├── decoder_step_kv.pte            #   iOS step
│   │   └── vocab.json                     #   词表（230 token）
│   │                                       #   Android 端为 .tflite 双签名两件套，由 build 流程注入
│   └── benchmark_samples.jsonl            # 500 条采样的 MathWriting 验证样本
│
├── platform_models/                       # 各平台模型资产副本（android/ios/macos）
├── hand_camera/                           # 自研相机插件（path dependency）
│                                           # 原生相机采集 + MediaPipe HandLandmarker 零拷贝集成
├── flutter_math_fork/                     # flutter_math 的本地 fork（path dependency）
│                                           # 扩展 LaTeX 解析以适配自研识别词表
├── rust/                                  # Rust 核心库（flutter_rust_bridge）
│   └── src/
│       ├── lib.rs
│       └── api/                           #   屏幕朝向 / 工具函数
│
├── android/  ios/  macos/  linux/  windows/  web/   # Flutter 各平台壳
├── pubspec.yaml                           # 依赖：get / flutter_litert / executorch_flutter /
│                                           #       flutter_tts / record / share_plus / device_info_plus 等
└── README.md / this PROJECT.md
```

### 2.1 关键依赖

| 包 | 作用 |
|---|---|
| `hand_camera` (path) | 自研相机插件，整合原生相机与 MediaPipe Hand Landmarker |
| `flutter_litert` | Android 端 LiteRT 推理（XNNPACK + GPU delegate） |
| `executorch_flutter` | iOS 端 ExecuTorch 推理（CoreML backend） |
| `flutter_math_fork` (path) | LaTeX 渲染（fork 后扩展自研词表对应的语法） |
| `math_expressions` | 数值求值器 |
| `flutter_tts` | 中文语音合成 |
| `record` | 麦克风采集（语音指令） |
| `flutter_rust_bridge` | Dart ↔ Rust 互操作（屏幕朝向 / 性能敏感工具函数） |
| `get` | 状态管理 + 多语言 + 路由 |
| `device_info_plus` / `package_info_plus` | benchmark 报告设备信息 |
| `share_plus` | 导出 benchmark 报告 / results.jsonl |
| `path_provider` | 临时目录 |
| `permission_handler` | 相机 / 麦克风权限 |
| `sensors_plus` | 加速度传感器（用于书写姿态辅助） |

### 2.2 三层架构

1. **应用层** —— `pages/` + `widgets/` + `controllers/`：UI、交互、状态。
2. **插件桥接层** —— `services/` + `hand_camera` + `flutter_rust_bridge`：把相机帧、关键点、模型推理统一成 Dart 接口。
3. **原生推理层** —— LiteRT（Android）/ ExecuTorch（iOS）/ Rust：模型推理与性能敏感运算。

数据流：相机帧 → MediaPipe 关键点 → 手势状态机（捏合/释放）→ 笔画收集（含 EMA 平滑、拉丝裁剪）→ 五指张开触发识别 → 笔画特征 + 灰度图渲染 → encoder/prefill/step 三段推理 → LaTeX token → 求值器 → 渲染 + TTS 播报。

### 2.3 端侧模型与 Python 端的契约

| Python 端文件 | Dart 端对应文件 | 契约 |
|---|---|---|
| `train/stroke_features.py` | `services/sequence_feature_extractor.dart` | 13 维笔画时序特征 |
| `train/stroke_renderer.py` | `services/stroke_rasterizer.dart` | 64×256 灰度图渲染 |
| `train/dataset.py` (Vocabulary) | `assets/models/vocab.json` | 230 token 字符级词表 |
| `export/export_et_hybrid_fp16.py` | iOS `.pte` 三件套 | ExecuTorch fp16 |
| `export/export_tf_android_fp32.py` | Android `.tflite` 两件套 | LiteRT fp32 |
| `eval/mobile/sample_benchmark.py` | `assets/benchmark_samples.jsonl` | 500 条评测样本 |
| `eval/mobile/eval_benchmark.py` | `pages/benchmark_page.dart` | ExpRate / CER 计算逻辑一致 |

任一端修改这些契约时，需同步另一端，否则推理结果会沉默错误。
