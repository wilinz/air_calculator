# iOS · 保留 flutter_rust_bridge 入口符号

## 现象

iOS（真机或模拟器）启动时崩溃：

```
Boot failed: Invalid argument(s): Failed to lookup symbol
'frb_get_rust_content_hash':
  dlsym(RTLD_DEFAULT, frb_get_rust_content_hash): symbol not found
This is often because the Rust library is not loaded correctly.
```

栈顶在 `RustLib.init()` → `dart:ffi DynamicLibrary.lookup` → `dlsym`。

## 根因

1. `ios/Podfile` 的 post_install 钩子向 `Pods-Runner.*.xcconfig` 注入了
   `-force_load "${PODS_CONFIGURATION_BUILD_DIR}/rust_lib_air_calculator/librust_lib_air_calculator.a"`。
2. `flutter build ios` 构建时，链接器**确实**把 rust 静态库的 obj 全部加载了进来。
   `librust_lib_air_calculator.a` 里 `_frb_get_rust_content_hash` 等 14 个 `_frb_*` 符号都存在。
3. **但 Xcode 15+ 的新 ld 默认开启 `-dead_strip`，会把链接阶段没人引用的导出符号剪掉。**
   FRB 的 14 个 C 符号全部走 Dart 端 `dlsym` 运行时查找，链接器在链接时看不到任何引用，
   于是全被当作"死代码"剪掉。`-force_load` 只保证 obj 被加载，**不阻止 `-dead_strip`**。
4. 运行时 `dlsym(RTLD_DEFAULT, ...)` 自然找不到符号，FRB 启动失败。

## 修复

在 Runner 自己的 xcconfig 里追加 `-Wl,-u,<symbol>`，把每个 `_frb_*` 符号声明为
"未定义引用"（undefined-root），ld 就会把它们当作活根保留下来。

文件：`ios/Flutter/Release.xcconfig` 与 `ios/Flutter/Debug.xcconfig`

```xcconfig
#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"
#include "Generated.xcconfig"

OTHER_LDFLAGS = $(inherited) \
  -Wl,-u,_frb_create_shutdown_callback \
  -Wl,-u,_frb_dart_fn_deliver_output \
  -Wl,-u,_frb_dart_opaque_dart2rust_encode \
  -Wl,-u,_frb_dart_opaque_drop_thread_box_persistent_handle \
  -Wl,-u,_frb_dart_opaque_rust2dart_decode \
  -Wl,-u,_frb_free_wire_sync_rust2dart_dco \
  -Wl,-u,_frb_free_wire_sync_rust2dart_sse \
  -Wl,-u,_frb_get_rust_content_hash \
  -Wl,-u,_frb_init_frb_dart_api_dl \
  -Wl,-u,_frb_pde_ffi_dispatcher_primary \
  -Wl,-u,_frb_pde_ffi_dispatcher_sync \
  -Wl,-u,_frb_rust_vec_u8_free \
  -Wl,-u,_frb_rust_vec_u8_new \
  -Wl,-u,_frb_rust_vec_u8_resize
```

（实际写在同一行，xcconfig 不支持反斜杠续行。）

## 验证

构建后 `nm` 应能在 Runner 二进制里看到 14 个 `_frb_*` 符号：

```bash
flutter build ios --release --no-codesign
nm build/ios/Release-iphoneos/Runner.app/Runner | grep ' T _frb_'
# 期望输出 14 行
```

之前未修复时该命令输出 0 行（只能看到 `PodsDummy_rust_lib_air_calculator`，
说明只链了空的 cocoapod framework，rust archive 的符号全被剪掉）。

## 维护

后续如果 `flutter_rust_bridge_codegen` 重跑后产生新的公开 C 符号（新的 `_frb_*`），
需要把新符号追加到上述两个 xcconfig 的 `OTHER_LDFLAGS`，否则又会在 release 构建被剪掉。

枚举当前 archive 暴露的所有 `_frb_*` 符号：

```bash
nm build/ios/Release-iphoneos/rust_lib_air_calculator/librust_lib_air_calculator.a \
  | awk '$2=="T" && $3 ~ /^_frb_/ {print $3}' | sort -u
```

## 失败排查记录（已尝试但无效）

- `flutter clean && pod deintegrate && pod install` —— Pods xcconfig 重生成正常，但根因不变。
- 把 `-force_load` 改成绝对路径 / 在 `OTHER_LDFLAGS[sdk=iphoneos*]` 与 unconditional 各加一次 ——
  `ld` 报 `ignoring duplicate libraries`，但即使去重后 archive 仍被加载，
  问题在于 `-dead_strip` 而非加载失败。
- 仅添加 `_frb_get_rust_content_hash` 一个 `-u` —— 启动通过 sanity check，
  但调用具体 Rust API 时仍会触发 `dlsym` 失败（API 函数走另一组符号）。
  必须把 archive 暴露的全部 `_frb_*` 都列上。

## 相关位置

- 错误抛出处：`lib/main.dart` 内 `RustLib.init(externalLibrary: ExternalLibrary.process(...))`。
- FRB 自动生成的入口：`lib/src/rust/frb_generated.dart`、`rust/src/frb_generated.rs`。
- 触发 `-force_load` 的 Podfile 段：`ios/Podfile` 末尾的 post_install。
- rust 静态库产物路径：`build/ios/Release-iphoneos/rust_lib_air_calculator/librust_lib_air_calculator.a`。
