import Foundation

/// 运行时解析 aircalc 原生核心的手部检测入口。
///
/// 库并不链接进这个插件——它是 `aircalc_native` 包的 build hook 产出的 Dart code
/// asset，由 Dart 运行时持有，Xcode 在链接期根本看不到它。用 dlsym 查符号，
/// 是为了让相机这条路径与 Dart 那边共用同一份库，而不是各自打包一份。
///
/// 这也顺带解决了三端不统一的问题：原先 iOS 与 Android 走 MediaPipe SDK、
/// 只有 macOS 走 Rust，行为有差异，桌面端也无从复用。
enum AircalcNative {
    typealias HandInit = @convention(c) (
        UnsafePointer<UInt8>?, Int, UnsafePointer<UInt8>?, Int
    ) -> Int32
    typealias HandReady = @convention(c) () -> Int32
    typealias HandWarmUp = @convention(c) () -> Void
    typealias HandDetect = @convention(c) (
        UnsafePointer<UInt8>?, Int32, Int32, Int32, Float, Int32
    ) -> HandTrackHands
    typealias HandDestroy = @convention(c) () -> Void

    /// 库是否可用。为 false 时插件退化成无检测模式，而不是崩溃。
    static var isAvailable: Bool { handle != nil }

    static let handInit: HandInit? = symbol("hand_track_init")
    static let handReady: HandReady? = symbol("hand_track_ready")
    static let handWarmUp: HandWarmUp? = symbol("hand_track_warm_up")
    static let handDetect: HandDetect? = symbol("hand_track_detect")
    static let handDestroy: HandDestroy? = symbol("hand_track_destroy")

    /// 已载入的镜像；若这个包里没有该 code asset 则为 nil。
    ///
    /// 先试 RTLD_DEFAULT：Dart 那边只要用过识别功能，库就已经在进程里，
    /// 再 dlopen 一次是白做功。
    private static let handle: UnsafeMutableRawPointer? = {
        if dlsym(UnsafeMutableRawPointer(bitPattern: -2), "hand_track_ready") != nil {
            return UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        }
        // Flutter 把 code asset 作为 framework 放进应用的私有 frameworks
        // 目录。带 Versions 的是 macOS 布局，扁平的是 iOS 的；@rpath 形式
        // 兜底那些布局不同的宿主。
        let relative = [
            "aircalc.framework/Versions/A/aircalc",
            "aircalc.framework/aircalc",
        ]
        var candidates = relative.map { "@rpath/\($0)" }
        if let frameworks = Bundle.main.privateFrameworksURL?.path {
            candidates = relative.map { "\(frameworks)/\($0)" } + candidates
        }
        for path in candidates {
            if let h = dlopen(path, RTLD_LAZY) { return h }
        }
        NSLog("hand_camera: 找不到 aircalc code asset，请把 aircalc_native 包加为依赖")
        return nil
    }()

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: T.self)
    }
}
