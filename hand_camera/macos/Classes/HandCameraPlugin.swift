// Copyright 2026 wilinz.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Cocoa
import FlutterMacOS
import AVFoundation
import Accelerate

// MARK: - Camera Texture

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
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.wilinz.hand_camera.macos",
                                              qos: .userInitiated)

    private var nativeW: Int = 0
    private var nativeH: Int = 0

    private var trackerReady = false
    private let trackerLock = NSLock()

    /// Dedicated queue for hand-tracking inference so the camera callback never
    /// blocks.  Without this the AVCaptureSession delivery queue stalls on every
    /// 每次检测调用都会拖慢相机回调、导致丢帧 (18-22 fps instead of 30).
    private let inferenceQueue = DispatchQueue(label: "com.wilinz.hand_camera.inference",
                                                qos: .userInitiated)
    /// Guarded by sessionQueue (read/write both happen there).
    private var inferenceBusy = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = HandCameraPlugin()
        instance.textureRegistry = registrar.textures

        let mc = FlutterMethodChannel(name: "hand_camera",
                                      binaryMessenger: registrar.messenger)
        registrar.addMethodCallDelegate(instance, channel: mc)
        instance.methodChannel = mc

        let ec = FlutterEventChannel(name: "hand_camera/landmarks",
                                     binaryMessenger: registrar.messenger)
        ec.setStreamHandler(instance)
        instance.landmarkChannel = ec

        let psc = FlutterEventChannel(name: "hand_camera/preview_size",
                                      binaryMessenger: registrar.messenger)
        psc.setStreamHandler(instance.previewSizeStream)
        instance.previewSizeChannel = psc
    }

    // MARK: - FlutterPlugin

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize": handleInitialize(call, result: result)
        case "warmUp":     handleWarmUp(call, result: result)
        case "dispose":    handleDispose(result: result)
        default:           result(FlutterMethodNotImplemented)
        }
    }

    private func handleInitialize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        sessionQueue.async {
            do {
                try self.setupCamera()

                self.setupTracker(modelPath: Self.modelPath())

                DispatchQueue.main.async {
                    let texture = CameraTexture()
                    self.cameraTexture = texture
                    let tid = self.textureRegistry?.register(texture) ?? -1
                    self.textureId = tid

                    self.sessionQueue.async { self.captureSession.startRunning() }

                    let w = self.nativeW
                    let h = self.nativeH
                    self.previewSizeStream.push(width: w, height: h)

                    result([
                        "textureId": tid,
                        "sensorOrientation": 0,
                        "previewWidth": w,
                        "previewHeight": h,
                        "cameraWidth": w,
                        "cameraHeight": h,
                    ])
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "INIT_ERROR",
                                        message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    // MARK: - 手部检测初始化（加载两个 PTE，调 hand_track_init）

    /// 只加载模型并预热，不碰相机。供 App 启动时调用，与 iOS 一致。
    private func handleWarmUp(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        sessionQueue.async {
            self.setupTracker(modelPath: Self.modelPath())
            let ok = self.trackerReady
            DispatchQueue.main.async { result(ok) }
        }
    }

    /// 模型在包内的绝对路径。
    ///
    /// lookupKey 在 macOS 上返回相对 Runner.app 的完整路径。取任一模型
    /// 文件即可——setupTracker 只用它的目录部分。
    private static func modelPath() -> String {
        let key = FlutterDartProject.lookupKey(
            forAsset: "assets/models/hand_detector.pte",
            fromPackage: "hand_camera")
        return Bundle.main.bundlePath + "/" + key
    }

    private func setupTracker(modelPath: String) {
        trackerLock.lock()
        defer { trackerLock.unlock() }
        guard !trackerReady else { return }

        guard AircalcNative.isAvailable, let handInit = AircalcNative.handInit else {
            NSLog("hand_camera macOS: aircalc 原生核心不可用")
            return
        }

        // 两个 PTE 与传入路径同目录（由 tools/hand_models_to_pte.py 从原
        // MediaPipe 的 TFLite 转来）。不再解压 .task——那是 MediaPipe SDK
        // 的打包格式，切到 aircalc 原生核心后没有意义。
        let dir = (modelPath as NSString).deletingLastPathComponent
        let palmPath = (dir as NSString).appendingPathComponent("hand_detector.pte")
        let lmPath = (dir as NSString).appendingPathComponent("hand_landmarks_detector.pte")

        guard let palm = FileManager.default.contents(atPath: palmPath),
              let lm = FileManager.default.contents(atPath: lmPath) else {
            NSLog("hand_camera macOS: 找不到手部检测模型 \(palmPath)")
            return
        }

        let rc = palm.withUnsafeBytes { p in
            lm.withUnsafeBytes { l in
                handInit(p.baseAddress?.assumingMemoryBound(to: UInt8.self), palm.count,
                         l.baseAddress?.assumingMemoryBound(to: UInt8.self), lm.count)
            }
        }
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
                NSLog("hand_camera macOS: 手部检测预热 %.0fms",
                      (CFAbsoluteTimeGetCurrent() - sw) * 1000)
            }
        }
        NSLog("hand_camera macOS: 手部检测初始化 \(trackerReady ? "成功" : "失败")"
            + "（palm=\(palm.count)B lm=\(lm.count)B）")
    }

    // MARK: - Camera setup

    private func setupCamera() throws {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .unspecified)
        else { throw makeError(1, "No camera") }

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
        print("HandCamera macOS: native sensor \(nativeW)x\(nativeH)")
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    private var _frameCount = 0
    private var _skipCount = 0
    public func captureOutput(_ output: AVCaptureOutput,
                               didOutput sampleBuffer: CMSampleBuffer,
                               from connection: AVCaptureConnection) {
        let t0 = CACurrentMediaTime()
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Update Flutter texture (GPU-backed) — always on the camera callback.
        cameraTexture?.update(pixelBuffer)
        let tid = textureId
        DispatchQueue.main.async { [weak self] in
            guard tid >= 0 else { return }
            self?.textureRegistry?.textureFrameAvailable(tid)
        }

        _frameCount += 1
        if _frameCount % 60 == 1 {
            NSLog("HandCamera macOS: frame #\(_frameCount) trackerReady=\(trackerReady) sinkSet=\(landmarkSink != nil) skips=\(_skipCount)")
            _skipCount = 0
        }

        // Offload hand tracking to a separate queue so the camera callback
        // returns immediately.  Without this the serial sessionQueue blocks on
        // 否则每次检测都占住回调，AVCaptureSession 会丢帧。
        guard trackerReady else { return }

        // Skip this frame if the previous inference hasn't finished yet.
        if inferenceBusy { _skipCount += 1; return }
        inferenceBusy = true

        // Copy the pixel buffer data — the buffer may be recycled after we return.
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer)
        let copySize = bytesPerRow * h
        let frameCopy = baseAddr.map { Data(bytes: $0, count: copySize) }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        let tCopy = CACurrentMediaTime()

        guard let rgbaData = frameCopy else { inferenceBusy = false; return }

        inferenceQueue.async { [weak self] in
            defer {
                self?.sessionQueue.async { self?.inferenceBusy = false }
            }

            // BGRA → RGBA via vImage (SIMD/AMX, same as before).
            let rowBytes = w * 4
            let rgba = UnsafeMutablePointer<UInt8>.allocate(capacity: rowBytes * h)
            defer { rgba.deallocate() }

            rgbaData.withUnsafeBytes { raw in
                var srcBuf = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: raw.baseAddress!),
                                           height: vImagePixelCount(h),
                                           width: vImagePixelCount(w),
                                           rowBytes: bytesPerRow)
                var dstBuf = vImage_Buffer(data: rgba,
                                           height: vImagePixelCount(h),
                                           width: vImagePixelCount(w),
                                           rowBytes: rowBytes)
                var permute: [UInt8] = [2, 1, 0, 3] // BGRA → RGBA
                vImagePermuteChannels_ARGB8888(&srcBuf, &dstBuf, &permute, vImage_Flags(kvImageNoFlags))
            }

            // Pass RGBA — Rust uses vImage for the heavy downscale.
            // 经 dlsym 拿到的入口；与 Dart 那边共用同一份库。
            guard let detect = AircalcNative.handDetect else { return }
            var results = detect(rgba, Int32(w), Int32(h), 1, 0.5, 0) // format=0 (RGBA)
            let tDetect = CACurrentMediaTime()

            // Always emit — even an empty list — so the Dart side clears the
            // previous frame's skeleton when the hand leaves view. Dropping
            // the event on `count == 0` causes a frozen skeleton to stick.
            let output = self?.convertResults(&results) ?? []
            let tConvert = CACurrentMediaTime()
            DispatchQueue.main.async { [weak self] in
                self?.landmarkSink?(output)
            }
            if (self?._frameCount ?? 0) % 30 == 1 {
                NSLog("HandCamera macOS: copy=%.1fms detect=%.1fms convert=%.1fms hands=%d",
                      (tCopy - t0) * 1000, (tDetect - tCopy) * 1000,
                      (tConvert - tDetect) * 1000, results.count)
            }
        }
    }

    // MARK: - Result conversion (Rust C struct → Dart dict)

    /// Read a C fixed-size float array (imported as tuple by Swift) into [Double].
    private func readFloatArray<T>(_ tuple: T, count: Int) -> [Double] {
        var result = [Double](repeating: 0, count: count)
        withUnsafeBytes(of: tuple) { ptr in
            let floats = ptr.bindMemory(to: Float.self)
            for i in 0..<count {
                result[i] = Double(floats[i])
            }
        }
        return result
    }

    private func convertResults(_ r: inout HandTrackHands) -> [[String: Any]] {
        var output: [[String: Any]] = []
        let hands: [HandTrackHand] = withUnsafeBytes(of: &r.hands) { ptr in
            Array(ptr.bindMemory(to: HandTrackHand.self).prefix(Int(r.count)))
        }
        for hand in hands {
            let handedness = String(cString: withUnsafePointer(to: hand.handedness) {
                $0.withMemoryRebound(to: CChar.self, capacity: 6) { ptr in ptr }
            })

            let lmFloats = readFloatArray(hand.landmarks, count: 63)
            let wlmFloats = readFloatArray(hand.world_landmarks, count: 63)

            var landmarks: [[String: Double]] = []
            var worldLandmarks: [[String: Double]] = []
            for j in 0..<21 {
                let k = j * 3
                landmarks.append(["x": lmFloats[k], "y": lmFloats[k+1], "z": lmFloats[k+2]])
                worldLandmarks.append(["x": wlmFloats[k], "y": wlmFloats[k+1], "z": wlmFloats[k+2]])
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

    // MARK: - FlutterStreamHandler (landmarks)

    public func onListen(withArguments arguments: Any?,
                          eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        landmarkSink = events; return nil
    }
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        landmarkSink = nil; return nil
    }

    // MARK: - Dispose

    private func handleDispose(result: @escaping FlutterResult) {
        sessionQueue.async {
            self.captureSession.stopRunning()
            self.captureSession.beginConfiguration()
            for input  in self.captureSession.inputs  { self.captureSession.removeInput(input)  }
            for output in self.captureSession.outputs { self.captureSession.removeOutput(output) }
            self.captureSession.commitConfiguration()

            self.trackerLock.lock()
            if self.trackerReady {
                AircalcNative.handDestroy?()
                self.trackerReady = false
            }
            self.trackerLock.unlock()

            let tid = self.textureId
            DispatchQueue.main.async {
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
