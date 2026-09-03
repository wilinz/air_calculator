#!/usr/bin/env bash
# 把 platform_models/{ios,android}/ 下的权重拷到 assets/models/，覆盖原内容。
# Flutter 构建会读 assets/models/ 进 flutter_assets bundle。
#
# 用法：
#   tool/copy_platform_models.sh ios
#   tool/copy_platform_models.sh android
#
# 由 ios Run Script Phase 和 android gradle task 在 build 前自动调用。
# 也可手动跑用于切换平台调试。
#
# 识别的两个模型按平台分后缀：Android 是 LiteRT 的 .tflite（decoder 双签名
# prefill+decode）；iOS/macOS 的模型走 app bundle，不经这里。vocab.json 三端同名。
#
# 但 vocab.json 的内容按平台不同：Android 那份多 max_kv / n_prefix 两个字段，
# 给 LiteRT 的双签名 decoder 用。目录必须分开，拿错了不报错，只会识别错。
#
# Android 那份由 air_calculator_py/export/export_tf_android_fp32.py 导出；
# iOS 的 Core ML 模型由 export_coreml_ios.py 导出，直接进 Runner 的 bundle。
#
# 缺源文件时 fail-fast：直接 exit 1，让上游构建立刻挂掉，避免静默使用错误权重。

set -euo pipefail

PLATFORM="${1:-}"
case "$PLATFORM" in
  ios|android|macos) ;;
  *)
    echo "用法: $0 {ios|android}" >&2
    exit 2
    ;;
esac

# 脚本固定位置：tool/copy_platform_models.sh，项目根 = 上一级
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$PROJ_ROOT/platform_models/$PLATFORM"
DST="$PROJ_ROOT/assets/models"

if [ ! -d "$SRC" ]; then
  echo "[copy_platform_models] ERROR: $SRC 不存在" >&2
  echo "  Android: python3 air_calculator_py/export/export_tf_android_fp32.py --ckpt ... --data-dir ..." >&2
  echo "  iOS:     python3 air_calculator_py_v3/export_fp16_hybrid.py --platform ios ..." >&2
  echo "  并把产物拷到 $SRC/" >&2
  exit 1
fi

mkdir -p "$DST"

# iOS/macOS 的识别模型不再走 assets：它们是 .mlpackage（带子目录的目录，
# Flutter 的目录型 asset 不递归），由 Runner 的构建阶段用 coremlcompiler 编成
# .mlmodelc 直接放进 app bundle，Dart 侧把 model_dir 指到那里（见
# MathwritingRecognitionService._prepareModelDir）。所以这里只管 vocab。
if [ "$PLATFORM" = "android" ]; then
  REQUIRED=(prefix_enc.tflite decoder.tflite vocab.json)
else
  REQUIRED=(vocab.json)
fi

# 手部检测的两个模型同理按平台分（Core ML fp16 对 XNNPACK fp32），落到
# hand_camera 包自己的 assets 目录，由该包的 pubspec 打进 flutter_assets。
# 手部检测的权重归 hand-track 仓所有（与它的转换脚本放在一起），这里只是把
# 当前平台那份取过来暂存。两个仓要并排 checkout；找不到就退回本地暂存的旧副本。
HAND_SRC="$PROJ_ROOT/../hand-track/models/$PLATFORM"
[ -d "$HAND_SRC" ] || HAND_SRC="$SRC/hand"
HAND_DST="$PROJ_ROOT/hand_camera/assets/models"
# Android 上手部检测走 LiteRT 的 GPU delegate，要的是 MediaPipe 原本的
# .tflite；iOS/macOS 走裸 Core ML，那两个模型进 Runner 的 bundle，
# 不进 hand_camera 的 assets。
if [ "$PLATFORM" = "android" ]; then
  HAND_REQUIRED=(hand_detector.tflite hand_landmarks_detector.tflite)
  HAND_STALE=()
else
  HAND_REQUIRED=()
  HAND_STALE=("*.tflite")
fi
# 要清掉的：另一平台的识别权重（后缀不同、名字同，留着会白白多进包近 200MB），
# 以及 decoder 之前拆成两个文件那版导出的残留（两份各带一套权重）。
if [ "$PLATFORM" = "android" ]; then
  STALE_PATTERNS=()
else
  # iOS 的识别模型走 bundle，assets 里的 .tflite 全是 Android 残留。
  STALE_PATTERNS=("*.tflite")
fi

for f in "${REQUIRED[@]}"; do
  if [ ! -f "$SRC/$f" ]; then
    echo "[copy_platform_models] ERROR: 缺少 $SRC/$f" >&2
    exit 1
  fi
done
# iOS 上这个数组是空的（模型走 bundle，不进 assets）。bash 3.2 在 set -u 下
# 展开空数组会报 unbound variable，所以先判长度。
for f in ${HAND_REQUIRED[@]+"${HAND_REQUIRED[@]}"}; do
  if [ ! -f "$HAND_SRC/$f" ]; then
    echo "[copy_platform_models] ERROR: 缺少 $HAND_SRC/$f" >&2
    echo "  由 air_calculator-rs/tools/convert_hand_models.py --backend {coreml|xnnpack} 导出" >&2
    exit 1
  fi
done

# 先清理对方平台残留（用 find -delete 避免 glob 不匹配时 rm 报错）
for pat in ${STALE_PATTERNS[@]+"${STALE_PATTERNS[@]}"}; do
  find "$DST" -maxdepth 1 -type f -name "$pat" -delete 2>/dev/null || true
done

for f in "${REQUIRED[@]}"; do
  cp -f "$SRC/$f" "$DST/$f"
done
mkdir -p "$HAND_DST"
# 另一平台的残留会被 pubspec 的 assets 一并打进包，白白多几 MB。
for pat in ${HAND_STALE[@]+"${HAND_STALE[@]}"}; do
  find "$HAND_DST" -maxdepth 1 -type f -name "$pat" -delete 2>/dev/null || true
done
for f in ${HAND_REQUIRED[@]+"${HAND_REQUIRED[@]}"}; do
  cp -f "$HAND_SRC/$f" "$HAND_DST/$f"
done

echo "[copy_platform_models] $PLATFORM → $DST"
# 通配符按平台只会命中一半，让 ls 的非零返回不要掀翻 set -e。
ls -lh "$DST"/*.tflite "$DST"/vocab.json "$HAND_DST"/* 2>/dev/null \
  | awk '{print "  " $5 "\t" $NF}' || true
