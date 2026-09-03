# mwh

空中手写数学公式识别的 Dart 包。笔画序列进，LaTeX 出。

特征提取、模型推理与贪心解码全在 Rust 侧（`air_calculator-rs`）完成，
一次识别只跨一次 FFI 边界。

## 为什么是纯 Dart 包而不是 Flutter 插件

原生库由 `hook/build.dart` 编译并打包，取代了 CocoaPods / Gradle / CMake
那三套胶水；因为是 build hook，`dart run` 与 `dart test` 同样适用。所以这里
没有 `android/` `ios/` `macos/` 目录。

## 为什么不用 flutter_rust_bridge

相机帧从 CameraX / AVFoundation 直接进 Rust，JNI 线程与 Dart 线程会碰同一个
识别器实例——FRB 只保证 Dart 侧的对象生命周期与并发安全，对另外两条路径
一无所知。手写 C ABI 后，锁在 Rust 侧统一持有，三条路径共享同一把锁。

顺带的好处是核心库不绑定 Dart：同一份 `src/mwh.h` 给 ffigen、Swift、JNI
共用，将来做桌面版或命令行批量识别可直接复用。

## 本地开发

运行时构件还没发 release，先自己编一份再指过来：

```bash
cd ../../air_calculator-rs
scripts/build_executorch.sh macos-arm64
export MWH_RUNTIME_DIR=$PWD/third_party/build/macos-arm64/install
```

## 重新生成绑定

```bash
dart run ffigen --config ffigen.yaml
```

`src/mwh.h` 从 `air_calculator-rs/include/mwh.h` 拷来，两边需保持同步。
