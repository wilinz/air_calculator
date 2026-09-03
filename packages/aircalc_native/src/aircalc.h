// air_calculator 识别核心的 C ABI。
//
// 同一份头文件供三方共用：Dart 经 ffigen 生成绑定，Swift 与 JNI 直接引用。
// 不依赖任何宿主语言的运行时——这正是不用 flutter_rust_bridge 的原因：
// FRB 只保证 Dart 侧的对象生命周期与并发安全，管不到 Swift/JNI 那两条路径。
//
// 线程模型：所有句柄操作在 Rust 侧统一加锁，三条调用路径天然串行化。
// 句柄是不透明整数而非裸指针，失效后查表落空返回错误码，不会悬垂。

#ifndef MWH_H
#define MWH_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ── 错误码 ──────────────────────────────────────────────────────

#define AIRCALC_OK                       0
#define AIRCALC_ERR_INVALID_HANDLE      -1
#define AIRCALC_ERR_INVALID_ARG         -2
#define AIRCALC_ERR_LOAD                -3
#define AIRCALC_ERR_EXECUTE             -4
#define AIRCALC_ERR_BACKEND_UNAVAILABLE -5

// ── 后端选择 ────────────────────────────────────────────────────

#define AIRCALC_BACKEND_AUTO        0  // 按编译进来的 feature 自动挑
#define AIRCALC_BACKEND_LITERT      1  // Android：XNNPACK CPU
// 2 曾经是 ExecuTorch，已整体移除；号不复用。
#define AIRCALC_BACKEND_COREML      3  // iOS/macOS：裸 Core ML（.mlmodelc）

// ── 数据结构 ────────────────────────────────────────────────────

/// 一个采样点。t 为秒。
typedef struct {
    double x;
    double y;
    double t;
} InkHmerPoint;

/// 一条笔画，指向连续的点数组。数组由调用方保有，调用期间须存活。
typedef struct {
    const InkHmerPoint* points;
    size_t count;
} InkHmerStroke;

/// 识别结果。由 ink_hmer_recognize 填充，用完须调 ink_hmer_result_free。
typedef struct {
    char*   latex;        ///< UTF-8，null 结尾；失败时为 NULL
    int32_t* token_ids;
    size_t  token_count;
    double  enc_ms;
    double  prefill_ms;
    double  decode_ms;
    double  total_ms;
} InkHmerResult;

// ── 生命周期 ────────────────────────────────────────────────────

/// 创建识别器。返回句柄；0 表示失败，具体原因写入 err（可传 NULL）。
///
/// model_dir   模型目录。各后端按自己的命名约定在其中找文件：
///               LiteRT      prefix_enc.tflite / decoder.tflite
///               ExecuTorch  prefix_enc.pte    / decoder.pte（多方法）
///                           退回 decoder_prefill_kv.pte + decoder_step_kv.pte
/// vocab_json  vocab.json 的完整内容
/// backend     见 AIRCALC_BACKEND_*
/// num_threads CPU 线程数；0 用后端默认。
///             Android 走 XNNPACK 时建议显式设 4，避开大小核调度拖累。
uint64_t ink_hmer_engine_create(const char* model_dir,
                           const char* vocab_json,
                           int32_t backend,
                           int32_t num_threads,
                           int32_t* err);

/// 销毁识别器。重复调用安全。
void ink_hmer_engine_destroy(uint64_t handle);

/// 返回后端名（静态字符串，勿释放）。句柄无效时返回 NULL。
const char* ink_hmer_engine_backend_name(uint64_t handle);

// ── 识别 ────────────────────────────────────────────────────────

/// 识别一组笔画。成功返回 AIRCALC_OK 并填充 out。
int32_t ink_hmer_recognize(uint64_t handle,
                      const InkHmerStroke* strokes,
                      size_t stroke_count,
                      InkHmerResult* out);

/// 释放 ink_hmer_recognize 填充的结果。重复调用安全。
void ink_hmer_result_free(InkHmerResult* r);

// ── 书写方向 ────────────────────────────────────────────────────



// ── 手部关键点检测 ──────────────────────────────────────────────
//
// 与识别共用同一个库：Swift / JNI / Dart 都从这一份 code asset 里解析
// 符号（dlsym），不再各自链接一份。原先 iOS 与 Android 走 MediaPipe SDK、
// 只有 macOS 走 Rust，三端行为不统一，桌面端也无从复用。

#define HAND_TRACK_LANDMARKS 63   // 21 点 × 3 维
#define HAND_TRACK_MAX_HANDS       2

typedef struct {
    char    handedness[6];                       ///< "Left" / "Right"
    float   landmarks[HAND_TRACK_LANDMARKS];       ///< 归一化图像坐标 [0,1]
    float   world_landmarks[HAND_TRACK_LANDMARKS]; ///< 世界坐标，单位米
    float   presence;
    int32_t landmark_count;                      ///< 检出时为 21
} HandTrackHand;

typedef struct {
    HandTrackHand hands[HAND_TRACK_MAX_HANDS];
    int32_t count;
} HandTrackHands;

/// 初始化手部检测。两个模型均为内存中的字节。成功返回 AIRCALC_OK。
int32_t hand_track_init(const uint8_t* palm_data, size_t palm_len,
                      const uint8_t* landmark_data, size_t landmark_len);

// 按文件路径初始化手部检测。
//
// Core ML 没有从内存字节建模型的入口，`.mlpackage` 本身还是个目录，所以那条
// 路只能给路径；其它后端读成字节后转交，行为与 hand_track_init 一致。
int32_t hand_track_init_path(const char* palm_path, const char* landmark_path);

/// 预热：把手掌与关键点两个模型各跑一次，触发 Core ML 编译。
/// 应在 init 之后、进入取景之前调一次。
void hand_track_warm_up(void);

/// 是否已初始化。
int32_t hand_track_ready(void);

/// 在一帧上检测手部。pixels 为 w*h*4 字节；format：0 = RGBA，1 = BGRA。
HandTrackHands hand_track_detect(const uint8_t* pixels, int32_t w, int32_t h,
                         int32_t num_hands, float min_presence, int32_t format);

/// 释放手部检测资源。重复调用安全。
void hand_track_destroy(void);

#ifdef __cplusplus
}
#endif

#endif // MWH_H
