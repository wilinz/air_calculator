# air_calculator

空中手写计算器。摄像头里用手指在空中书写数学表达式，端侧识别成 LaTeX 并求值。

> 2026 届桂林电子科技大学本科毕业设计，校级优秀毕业设计。

| 空闲 | 书写中 | 识别完成 |
|:---:|:---:|:---:|
| ![](docs/images/app_overview_idle.webp) | ![](docs/images/app_overview_writing.webp) | ![](docs/images/app_overview_recognized.webp) |
| 等待抬手，画布显示提示 | 捏合落笔，实时绘制笔迹 | LaTeX 渲染 + 计算结果 + 语音播报 |

三态切换由捏合—释放—停笔状态机驱动，不需要额外操作。

本项目分为五个仓库，需要**并排 checkout**——Rust 侧是 path 依赖。

| 仓库 | 职责 |
|---|---|
| **air_calculator** ← 本仓 | Flutter 客户端：UI、相机接入、手势交互与三端集成 |
| [air_calculator-rs](https://github.com/wilinz/air_calculator-rs) | Rust 核心：识别解码循环、LaTeX 求值与 C ABI |
| [hand-track](https://github.com/wilinz/hand-track) | 手部检测：palm + landmark 两段式流水线与两端权重 |
| [edge-infer](https://github.com/wilinz/edge-infer) | 推理抽象：`Engine` trait + LiteRT / Core ML 后端 |
| [air_calculator_py](https://github.com/wilinz/air_calculator_py) | 模型训练、合成数据生成与端侧导出 |

## 功能

- 空中书写：手部关键点跟踪 + 捏合手势起落笔，绘制轨迹
- 手写识别：笔画序列 → LaTeX（decoder-only 模型，端侧推理）
- 触屏手写板与公式键盘，两种输入方式与空中书写共用同一条识别链路
- LaTeX 解析与数值计算，结果中文语音播报
- 语音指令
- 内置基准页：500 条样本跑端到端延迟与准确率，可导出报告

## 手势

除捏合书写外，还有三个复合手势触发系统级动作。判定阈值与帧节拍在
`lib/pages/formula_editor/gesture_logic.dart`。

| ![](docs/images/gesture_pinch_writing.webp) | ![](docs/images/gesture_open_palm.webp) | ![](docs/images/gesture_two_finger.webp) | ![](docs/images/gesture_air_click.webp) |
|:---:|:---:|:---:|:---:|
| **捏合书写**<br>拇指食指捏合落笔，<br>指尖中点画轨迹 | **五指张开**<br>立即提交识别 | **双指并拢**<br>拖拽预览区<br>横向滚动看长公式 | **单指悬停**<br>停留触发按钮，<br>高风险按钮要停更久 |

## 界面

触屏与空中两种模式共用同一份公式状态，切换不丢编辑结果。差别只在控件布局：
触屏铺满全屏，空中把可点击控件约束在屏幕一侧，避开手部活动区免得误触。

| ![](docs/images/hero.webp) | ![](docs/images/ui_main_air.webp) |
|:---:|:---:|
| **触屏模式**<br>标题栏、公式预览区、光标拖动条、<br>LaTeX 源码行、快捷工具栏、符号面板 | **空中模式**<br>相机预览铺底，编辑器 UI 半透明靠边，<br>笔迹画布 / 手部骨架 / 悬停进度环三层叠加 |

左图是触屏手写与公式键盘混合输入的结果：`\log_{2}8 + 79 + |\begin{matrix}2&3\\4&5\end{matrix}| + \sqrt{\frac{3}{4}}`
——对数、行列式、根式、分数四种结构混排，实时渲染并求值。

另有三个辅助界面：

| ![](docs/images/ui_settings.webp) | ![](docs/images/ui_history.webp) | ![](docs/images/ui_benchmark.webp) |
|:---:|:---:|:---:|
| **设置**<br>API Key、语言、骨架开关 | **历史**<br>停靠式底部面板，<br>点击回填、长按复制 | **基准测试**<br>JSONL 导出与统计报告 |

## 仓库关系

本仓是 Flutter 客户端，内含三个子包：

```
hand_camera/                相机与手部检测插件（CameraX / AVFoundation）
packages/aircalc_native/    核心库的 Dart 绑定与 build hook
flutter_math_fork/          公式渲染（带光标插入）
```

四个兄弟仓见开头的仓库矩阵。几个仓要**并排 checkout**——Rust 侧是 path 依赖，
build hook 默认按这个布局去找核心库与运行时构件（放在别处见 `pubspec.yaml` 里的
`hooks.user_defines` 说明）：

```
some-dir/
├── air_calculator/
├── air_calculator-rs/
├── air_calculator_py/
├── edge-infer/
└── hand-track/
```

## 架构

```
相机帧 ──> hand_camera 插件 ──> aircalc 原生核心（Rust）
                                    │
                              关键点 21 点
                                    ▼
                            捏合判定 / 轨迹累积
                                    ▼
                          笔画 ──> 识别 ──> LaTeX ──> 求值
```

推理和求值都在 Rust 核心里完成，一次识别只跨一次 FFI 边界——解码的每一步不再
往返 Dart。识别跑在常驻 worker isolate 上，不占 UI 线程。

Rust 侧分三个 crate：

| crate | 职责 |
|---|---|
| `ink-hmer` | 笔画特征提取 + 解码循环 |
| `latex-calc` | LaTeX 词法 → 语法 → AST → 求值 |
| `aircalc-ffi` | C ABI，同时供 Dart / Swift / JNI 调用 |

识别模型是 **stroke-only** 的：输入只有笔画序列，没有渲染图那一路
（`vocab.json` 里 `n_prefix: 32`，即 32 个笔画 token）。

求值走任意精度有理数，四则运算、整数幂、阶乘、组合数、行列式全程精确，
遇到 `\sin`、`\ln`、开不尽的根才转浮点——`0.1+0.2` 精确等于 `0.3`，
`21!` 不会在 2^53 处失真。

后端按平台选，由核心库内部的 `Engine` 抽象抹平：

| | Android | iOS / macOS |
|---|---|---|
| 后端 | LiteRT 2.x（GPU 加速器） | 裸 Core ML（神经引擎） |
| 识别模型 | `.tflite` 双签名 | `.mlmodelc` 多函数 |
| 手部模型 | `.tflite` | `.mlmodelc` |

## 模型与训练

识别模型是 decoder-only 的 prefix-LM，**只吃笔画序列**，没有渲染图那一路：

| | |
|---|---|
| 笔画编码器 | 轻量 Transformer，13 维时序特征（位置 / 速度 / 曲率 / 抬笔标志 / 全局比例）→ 32 个 prefix token |
| 解码器 | 8 层因果 self-attention，d=512，nhead=8，词表 230 |
| 参数量 | 27.1 M（全部可训练） |

prefix 与已生成的 token 拼在同一条因果序列里，跨模态对齐和 LaTeX 生成由同一套
self-attention 完成，没有 cross-attention——这样导出成端侧图时只有一种算子模式，
KV cache 的形状也是固定的。

早期版本还有一路 DeiT-Small 图像分支（双流，48.8 M 参数）。去掉之后参数量降到
27.1 M 而 ExpRate 没有明显损失，端侧延迟大幅下降，所以部署的是 stroke-only 这版。

### 训练

```bash
cd train
MATHWRITING_DIR=../../dataset/mathwriting-2024 \
python3 train.py --modality stroke_only --out ./stroke_v4 --epochs 40 --batch 64
```

| 超参 | 值 |
|---|---|
| 优化器 | AdamW，lr 3e-4，weight decay 0.01 |
| 调度 | cosine + warmup |
| batch | 64 × 梯度累积 2（等效 128） |
| 损失 | 交叉熵，label smoothing 0.1 |
| 梯度裁剪 | 1.0 |
| 序列上限 | 笔画点 512，目标 token 64 |

数据是 **MathWriting** 加自建合成集。合成走三步：LLM 批量生成 LaTeX → 渲染出
token 级 bbox → 用从真实人工 InkML 抽出的手写笔画字库按 bbox 拼装成轨迹，所以
合成样本的笔画本身是真人写的，只有排版是拼的。训练分两阶段：先在合成数据上预热，
再用人工数据续训对齐；错误按类型归类后再定向补数据。

## 性能

500 条 MathWriting 样本，端到端（特征提取 → 编码 → prefill → 逐步解码），
应用内置的基准页跑出：

| | iPhone 15（iOS 26.3） | Redmi K40s（Android 13） |
|---|---|---|
| 后端 | 裸 Core ML，神经引擎 | LiteRT，GPU 加速器（OpenCL） |
| 编码器 | 3.1 ms | 1.9 ms |
| Prefill | 2.7 ms | 2.7 ms |
| 每步解码 | 3.2 ms | 11.3 ms |
| **总流水线均值** | **44 ms** | **125 ms** |
| 总流水线 min / max | 10 / 234 ms | 35 / 400 ms |
| ExpRate | 74.60% | 74.60% |

按输出长度分桶（总流水线均值）：

| token 数 | 样本 | iPhone 15 | Redmi K40s |
|---|---|---|---|
| 1–3 | 88 | 14 ms | 41 ms |
| 4–8 | 108 | 24 ms | 71 ms |
| 9–16 | 152 | 40 ms | 116 ms |
| 17+ | 152 | 77 ms | 218 ms |

两端 ExpRate 完全一致，说明特征提取到解码这条链路在两个后端上是数值等价的——
差异只在延迟。长表达式的每步解码反而更快（iPhone 3.2 → 2.9 ms），因为固定开销
被摊薄了。

MathWriting 全量验证集上 EM 77.09% / char-CER 3.84%；基准页这 500 条是随机抽样，
ExpRate 74.60%。

Android 上识别与手部检测都请求 GPU 加速器（OpenCL），接不了的算子由 CPU 兜底。
识别的三个子图都**整图下沉**——encoder `152/152`、prefill `455/455`、
decode `484/484`，各 1 个分区，零算子留在 CPU。这不是默认结果，是导出侧改出来的：
KV cache 从一个 `[8,2,1,80,512]` 大张量拆成逐层独立张量，消掉了图里 48 个
GPU 接不了的 `SLICE`；encoder 那条 `CAST → GREATER_EQUAL → SELECT_V2` 的 BOOL
路径也一并绕掉。改之前是 574/671、3 分区，跑图 16.7 ms；改之后 2.6 ms。

prefill 与 decode 还共用同一个 CompiledModel，这样 prefill 的 KV 输出缓冲能直接
对接 decode 的输入缓冲，省掉一趟 GPU→CPU→GPU 往返——实测那一趟占 prefill 耗时
的八成。
`AndroidManifest.xml` 里那几行 `uses-native-library libOpenCL.so` 就是为此声明的：
targetSdk ≥ 31 起厂商的非 NDK 原生库默认对应用不可见，漏了会静默退回 OpenGL，
手部检测单帧从十几毫秒掉到 44 ms。

## 权重与导出

权重不进 Git。`platform_models/` 放识别模型，手部模型来自 `hand-track` 仓。

```
platform_models/android/  prefix_enc.tflite  decoder.tflite  vocab.json
platform_models/ios/      prefix_enc.mlpackage  decoder.mlpackage  vocab.json
```

由 `air_calculator_py/export/` 下的脚本导出：

```bash
# Android
python3 export/export_tf_android_fp32.py --ckpt <ckpt> --data-dir <dataset>
# iOS / macOS
python3 export/export_coreml_ios.py --ckpt <ckpt> --data-dir <dataset> --max-decode 48
```

`--max-decode` 要与 Rust 侧的 `MAX_DECODE` 一致，否则解到一半会因 KV 缓冲越界
而失败。

构建前 `tool/copy_platform_models.sh <platform>` 把当前平台那份就位：Android 的
模型进 `assets/`；iOS 的识别模型与手部模型由 Xcode 的构建阶段用
`xcrun coremlcompiler` 编成 `.mlmodelc` 直接放进 app bundle，所以 iOS 的
`assets/models/` 里只有一个 `vocab.json`。

## 构建

```bash
# Android 首次：取 LiteRT 运行时
../edge-infer/scripts/fetch_litert.sh android-arm64

flutter pub get
flutter run --release -d <device>
```

Apple 侧不需要取任何运行时构件，`CoreML.framework` 是系统框架。

Rust 核心由 `packages/aircalc_native` 的 build hook 编译，不需要单独构建。

## 权限

相机（空中书写）、麦克风（语音指令）。iOS 在 `Info.plist`、Android 在
`AndroidManifest.xml`，首次进入对应功能时申请。

## License

Apache License 2.0 — see `LICENSE` and `NOTICE`.

The code is free to use, modify, redistribute and commercialize, including
publishing derivative applications on the App Store, Google Play or anywhere
else. Per section 6 of the Apache License 2.0, no trademark or product name
rights are granted: **Air Calculator**, **AirCalculator**, `air_calculator` as
a product name, and the application icons and logos in this repository are
reserved, and may not be used to publish or promote a derivative work without
prior written permission. Fork it, but ship it under your own name. Factual
references such as "based on Air Calculator" are fine, as long as they do not
suggest endorsement.
