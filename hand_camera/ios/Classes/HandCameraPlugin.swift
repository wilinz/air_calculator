import Flutter
import UIKit
import AVFoundation
import Accelerate

// MARK: - Flutter Texture

final class CameraTexture: NSObject, FlutterTexture {
    private var latestBuffer: CVPixelBuffer?
    private let lock = NSLock()

    func update(_ buffer: CVPixelBuffer) {
        lock.lock(); latestBuffer = buffer; lock.unlock()
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock(); defer { lock.unlock() }
        guard let buf = latestBuffer else { return nil }
        return .passRetained(buf)
    }
}

// MARK: - Preview size stream

final class PreviewSizeStream: NSObject, FlutterStreamHandler {
    var sink: FlutterEventSink?
    var lastSize: (Int, Int)?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        if let s = lastSize { events(["width": s.0, "height": s.1]) }
        return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? { sink = nil; return nil }

    func push(width: Int, height: Int) {
        lastSize = (width, height)
        DispatchQueue.main.async { self.sink?(["width": width, "height": height]) }
    }
}

// MARK: - Plugin

public class HandCameraPlugin: NSObject, FlutterPlugin, FlutterStreamHandler,
    AVCaptureVideoDataOutputSampleBufferDelegate {

    private var methodChannel: FlutterMethodChannel?
    private var landmarkChannel: FlutterEventChannel?
    private var landmarkSink: FlutterEventSink?

    private var previewSizeChannel: FlutterEventChannel?
    private let previewSizeStream = PreviewSizeStream()

    private var textureRegistry: FlutterTextureRegistry?
    private var cameraTexture: CameraTexture?
    private var textureId: Int64 = -1

    private let captureSession = AVCaptureSession()
    private let videoOutput    = AVCaptureVideoDataOutput()
    private let sessionQueue   = DispatchQueue(label: "com.wilinz.hand_camera.session",
                                               qos: .userInitiated)

    /// 手部检测是否已初始化。检测走 aircalc 原生核心（Rust），不再用 MediaPipe SDK。
    private var trackerReady = false
    private var numHands: Int = 1
    private var minPresence: Float = 0.5

    /// 推理放到独立队列，避免占住相机回调导致丢帧。
    private let inferenceQueue = DispatchQueue(label: "com.wilinz.hand_camera.inference",
                                               qos: .userInitiated)
    /// 上一帧还没算完就跳过当前帧。仅在 sessionQueue 上读写。
    private var inferenceBusy = false

    /// 原生 sensor 尺寸（始终 landscape：width > height）。
    private var nativeW: Int = 0
    private var nativeH: Int = 0

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = HandCameraPlugin()
        instance.textureRegistry = registrar.textures()

        let mc = FlutterMethodChannel(name: "hand_camera",
                                      binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: mc)
        instance.methodChannel = mc

        let ec = FlutterEventChannel(name: "hand_camera/landmarks",
                                     binaryMessenger: registrar.messenger())
        ec.setStreamHandler(instance)
        instance.landmarkChannel = ec

        let psc = FlutterEventChannel(name: "hand_camera/preview_size",
                                      binaryMessenger: registrar.messenger())
        psc.setStreamHandler(instance.previewSizeStream)
        instance.previewSizeChannel = psc
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize": handleInitialize(call, result: result)
        case "warmUp":     handleWarmUp(call, result: result)
        case "dispose":    handleDispose(result: result)
        default:           result(FlutterMethodNotImplemented)
        }
    }

    private func handleInitialize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args        = call.arguments as? [String: Any] ?? [:]
        let numHands    = args["numHands"]                    as? Int    ?? 1
        let minDetect   = Float(args["minHandDetectionConfidence"] as? Double ?? 0.5)
        let minPresence = Float(args["minHandPresenceConfidence"]  as? Double ?? 0.5)
        let minTrack    = Float(args["minTrackingConfidence"]      as? Double ?? 0.5)
        let modelAsset  = args["modelAssetPath"] as? String
            ?? "flutter_assets/packages/hand_camera/assets/models/hand_detector.pte"

        sessionQueue.async {
            do {
                try self.setupDetector(modelAsset: modelAsset, numHands: numHands,
                                       minDetect: minDetect, minPresence: minPresence, minTrack: minTrack)
                try self.setupCamera()
                self.applyOrientation(self.currentVideoOrientation())

                DispatchQueue.main.async {
                    let texture = CameraTexture()
                    self.cameraTexture = texture
                    let tid = self.textureRegistry?.register(texture) ?? -1
                    self.textureId = tid

                    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                    NotificationCenter.default.addObserver(
                        self, selector: #selector(self.onOrientationChanged),
                        name: UIDevice.orientationDidChangeNotification, object: nil)

                    self.sessionQueue.async { self.captureSession.startRunning() }

                    let (w, h) = self.currentBufferSize()
                    self.previewSizeStream.push(width: w, height: h)
                    result(["textureId": tid, "sensorOrientation": 0,
                            "previewWidth": w, "previewHeight": h,
                            "cameraWidth": w, "cameraHeight": h])
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "INIT_ERROR",
                                        message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    /// 只加载模型并预热，不碰相机。
    ///
    /// 供 App 启动时调用：首次安装后 Core ML 要编译两个模型（几秒），
    /// 趁用户还没进空中书写页时做掉。之后进页面时 setupDetector 发现
    /// 已就绪会直接跳过。
    private func handleWarmUp(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let modelAsset = args["modelAssetPath"] as? String
            ?? "flutter_assets/packages/hand_camera/assets/models/hand_detector.pte"
        sessionQueue.async {
            do {
                try self.setupDetector(modelAsset: modelAsset, numHands: 1,
                                       minDetect: 0.5, minPresence: 0.5, minTrack: 0.5)
                DispatchQueue.main.async { result(true) }
            } catch {
                // 预热失败不算错误——进页面时会再试一次。
                NSLog("hand_camera iOS: 预热失败 \(error.localizedDescription)")
                DispatchQueue.main.async { result(false) }
            }
        }
    }

    private func setupDetector(
        modelAsset: String, numHands: Int,
        minDetect: Float, minPresence: Float, minTrack: Float
    ) throws {
        self.numHands = numHands
        self.minPresence = minPresence

        // 启动时的预热可能已经加载过了，直接复用——模型是全局单例。
        if trackerReady { return }

        guard AircalcNative.isAvailable else {
            NSLog("hand_camera iOS: aircalc 原生核心不可用（dlsym 未找到 aircalc.framework）")
            throw makeError(2, "aircalc 原生核心不可用")
        }

        // 两个模型与 .task 放在同一目录下（由 tools/convert_hand_models.py 从原
        // MediaPipe 的 TFLite 转来）。优先用 .mlpackage：那是裸 Core ML，整张图
        // 交给系统框架，构建期已由 coremlcompiler 编成 .mlmodelc。
        let dir = (Bundle.main.bundlePath as NSString)
            .appendingPathComponent("Frameworks/App.framework/"
                + (modelAsset as NSString).deletingLastPathComponent)
        let fm = FileManager.default
        // Core ML 模型不走 flutter_assets（目录型 asset 不递归），由 Runner 的
        // Thin Binary 阶段用 coremlcompiler 编成 .mlmodelc 放到 app bundle 根。
        // 编译在构建期做掉，设备上就不用付首次启动那几秒。
        let bundleRoot = Bundle.main.bundlePath as NSString
        let palmPkg = bundleRoot.appendingPathComponent("hand_detector.mlmodelc")
        let lmPkg = bundleRoot.appendingPathComponent("hand_landmarks_detector.mlmodelc")
        // 没有回退路径：核心库在 iOS 上只编了 Core ML 后端，而 Core ML 没有
        // 从内存字节建模型的入口。
        guard let handInitPath = AircalcNative.handInitPath else {
            throw makeError(2, "核心库缺少 hand_track_init_path（版本不匹配）")
        }
        guard fm.fileExists(atPath: palmPkg), fm.fileExists(atPath: lmPkg) else {
            NSLog("hand_camera iOS: 找不到模型 \(palmPkg)")
            throw makeError(3, "找不到手部检测模型：\(palmPkg)")
        }
        // Core ML 只能从文件加载，所以传路径而不是字节。
        let rc = palmPkg.withCString { p in lmPkg.withCString { l in handInitPath(p, l) } }
        let srcDesc = "mlmodelc"
        trackerReady = (rc == 0)
        if trackerReady {
            // 预热：首次安装后 Core ML 要编译两个模型，几秒起步。
            //
            // 必须异步——它在初始化链路里同步跑的话，相机要等它做完才启动，
            // 进页面时画面会卡住几秒。放到后台后相机立刻起来，预热与头几帧
            // 并行；那几帧会在核心库的锁上排队，但排队发生在推理队列上，
            // 预览和界面都不受影响。
            DispatchQueue.global(qos: .utility).async {
                let sw = CFAbsoluteTimeGetCurrent()
                AircalcNative.handWarmUp?()
                NSLog("hand_camera iOS: 手部检测预热 %.0fms",
                      (CFAbsoluteTimeGetCurrent() - sw) * 1000)
            }
        }
        NSLog("hand_camera iOS: 手部检测初始化 \(trackerReady ? "成功" : "失败")"
            + "（\(srcDesc)）")
        if !trackerReady { throw makeError(4, "手部检测初始化失败") }
    }

    private func setupCamera() throws {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front)
        else { throw makeError(1, "No front camera") }

        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else { throw makeError(2, "Cannot add input") }
        captureSession.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        guard captureSession.canAddOutput(videoOutput) else { throw makeError(3, "Cannot add output") }
        captureSession.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = true }
        }

        captureSession.commitConfiguration()

        try device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        device.unlockForConfiguration()

        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        nativeW = Int(dims.width)
        nativeH = Int(dims.height)
        print("HandCamera iOS: native sensor \(nativeW)x\(nativeH)")
    }

    // MARK: orientation

    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        // UIDeviceOrientation 与 AVCaptureVideoOrientation 的 landscape 是反的（Apple QA1744）。
        let dev = UIDevice.current.orientation
        switch dev {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: break
        }
        // faceUp / faceDown / unknown → 用 windowScene.interfaceOrientation 兜底
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            switch scene.interfaceOrientation {
            case .portrait: return .portrait
            case .portraitUpsideDown: return .portraitUpsideDown
            case .landscapeLeft: return .landscapeLeft
            case .landscapeRight: return .landscapeRight
            default: break
            }
        }
        return .portrait
    }

    private func currentBufferSize() -> (Int, Int) {
        switch currentVideoOrientation() {
        case .portrait, .portraitUpsideDown:
            return (nativeH, nativeW)
        default:
            return (nativeW, nativeH)
        }
    }

    @objc private func onOrientationChanged() {
        sessionQueue.async {
            let o = self.currentVideoOrientation()
            self.applyOrientation(o)
            let (w, h) = self.currentBufferSize()
            self.previewSizeStream.push(width: w, height: h)
        }
    }

    private func applyOrientation(_ o: AVCaptureVideoOrientation) {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported, connection.videoOrientation != o {
            connection.videoOrientation = o
        }
        if connection.isVideoMirroringSupported, !connection.isVideoMirrored {
            connection.isVideoMirrored = true
        }
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(_ output: AVCaptureOutput,
                               didOutput sampleBuffer: CMSampleBuffer,
                               from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        cameraTexture?.update(pixelBuffer)
        let tid = textureId
        DispatchQueue.main.async { [weak self] in
            guard tid >= 0 else { return }
            self?.textureRegistry?.textureFrameAvailable(tid)
        }

        guard trackerReady, let detect = AircalcNative.handDetect else { return }

        // 上一帧还在算就跳过——否则推理队列积压，相机会开始丢帧。
        if inferenceBusy { return }
        inferenceBusy = true

        // 拷一份像素：回调返回后这个缓冲会被相机回收。
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let base = CVPixelBufferGetBaseAddress(pixelBuffer)
        let frame = base.map { Data(bytes: $0, count: bytesPerRow * h) }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        guard let frame else { inferenceBusy = false; return }
        let nHands = Int32(numHands)
        let presence = minPresence

        inferenceQueue.async { [weak self] in
            defer { self?.sessionQueue.async { self?.inferenceBusy = false } }

            // 相机缓冲的 bytesPerRow 常带对齐填充，不等于 w*4；直接按 w*4
            // 解读会让每一行错位、整幅图斜掉，检测自然什么都找不到。
            // 用 vImage 重新打包成紧凑行，顺带把 BGRA 换成 RGBA。
            let rowBytes = w * 4
            let rgba = UnsafeMutablePointer<UInt8>.allocate(capacity: rowBytes * h)
            defer { rgba.deallocate() }

            frame.withUnsafeBytes { raw in
                var src = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: raw.baseAddress!),
                    height: vImagePixelCount(h),
                    width: vImagePixelCount(w),
                    rowBytes: bytesPerRow)
                var dst = vImage_Buffer(
                    data: rgba,
                    height: vImagePixelCount(h),
                    width: vImagePixelCount(w),
                    rowBytes: rowBytes)
                var permute: [UInt8] = [2, 1, 0, 3] // BGRA → RGBA
                vImagePermuteChannels_ARGB8888(&src, &dst, &permute,
                                               vImage_Flags(kvImageNoFlags))
            }

            var results = detect(rgba, Int32(w), Int32(h), nHands, presence, 0)

            // 即便没检出也要发——否则手移出画面时 Dart 侧的骨架会僵在原地。
            let output = Self.convertResults(&results)
            DispatchQueue.main.async { self?.landmarkSink?(output) }
        }
    }

    /// C 结构体 → Flutter 侧的字典数组。
    private static func convertResults(_ r: inout HandTrackHands) -> [[String: Any]] {
        var output: [[String: Any]] = []
        let hands: [HandTrackHand] = withUnsafeBytes(of: &r.hands) { ptr in
            Array(ptr.bindMemory(to: HandTrackHand.self).prefix(Int(r.count)))
        }
        for hand in hands {
            let handedness = String(cString: withUnsafePointer(to: hand.handedness) {
                $0.withMemoryRebound(to: CChar.self, capacity: 6) { $0 }
            })
            let lm = readFloats(hand.landmarks)
            let wlm = readFloats(hand.world_landmarks)

            var landmarks: [[String: Double]] = []
            var worldLandmarks: [[String: Double]] = []
            for j in 0..<21 {
                let k = j * 3
                landmarks.append(["x": lm[k], "y": lm[k + 1], "z": lm[k + 2]])
                worldLandmarks.append(["x": wlm[k], "y": wlm[k + 1], "z": wlm[k + 2]])
            }
            output.append([
                "handedness": handedness,
                "handednessScore": Double(hand.presence),
                "landmarks": landmarks,
                "worldLandmarks": worldLandmarks,
            ])
        }
        return output
    }

    /// C 的定长数组在 Swift 里是元组，按内存读回来。
    ///
    /// 必须用泛型参数而不是 Any：后者会把元组装箱，withUnsafeBytes 读到的
    /// 是存在性容器的字节而非数组内容，读 63 个 float 直接越界崩溃。
    private static func readFloats<T>(_ tuple: T, count: Int = 63) -> [Double] {
        var result = [Double](repeating: 0, count: count)
        withUnsafeBytes(of: tuple) { raw in
            let floats = raw.bindMemory(to: Float.self)
            for i in 0..<count {
                result[i] = Double(floats[i])
            }
        }
        return result
    }

    // MARK: FlutterStreamHandler (landmarks)

    public func onListen(withArguments arguments: Any?,
                          eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        landmarkSink = events; return nil
    }
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        landmarkSink = nil; return nil
    }

    // MARK: Dispose

    private func handleDispose(result: @escaping FlutterResult) {
        sessionQueue.async {
            self.captureSession.stopRunning()
            self.captureSession.beginConfiguration()
            for input  in self.captureSession.inputs  { self.captureSession.removeInput(input)  }
            for output in self.captureSession.outputs { self.captureSession.removeOutput(output) }
            self.captureSession.commitConfiguration()
            if self.trackerReady {
                AircalcNative.handDestroy?()
                self.trackerReady = false
            }

            let tid = self.textureId
            DispatchQueue.main.async {
                NotificationCenter.default.removeObserver(self,
                    name: UIDevice.orientationDidChangeNotification, object: nil)
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
                if tid >= 0 {
                    self.textureRegistry?.unregisterTexture(tid)
                    self.textureId = -1
                    self.cameraTexture = nil
                }
                result(nil)
            }
        }
    }

    private func makeError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "HandCamera", code: code,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
