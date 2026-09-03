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

package com.wilinz.hand_camera

import android.content.ComponentCallbacks
import android.content.Context
import android.content.res.Configuration
import android.graphics.SurfaceTexture
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Size
import android.view.OrientationEventListener
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * 双用例实现，照 wxscan_live：
 *   Preview       → Flutter 的 SurfaceTexture，全程在 GPU 上，每帧零 CPU
 *   ImageAnalysis → 每帧拷一次 RGBA 送 aircalc 原生核心（Rust）检测
 *
 * 之前是单流：ImageAnalysis 一条流既当预览又当输入，于是每帧要
 * toBitmap → Matrix 旋转镜像 → lockCanvas 软件合成 → copyPixelsToBuffer
 * → JNI 再拷一次，五次全帧拷贝加一次软件合成，实测检测只有 23fps。
 *
 * 症结在于用像素做了本该用坐标做的事：把 30 万个像素转一遍，只为让回传的
 * 21 个关键点落在 display 坐标系里。现在反过来——图像原样送去推理，
 * 旋转与前置镜像作用在检测结果的坐标上（见 [orientLandmarks]），
 * 21 个点的三角函数与 1.2MB 的内存搬运不是一个量级。
 *
 * 朝向分两条路走，照 wxscan_live：
 *
 *   Preview        targetRotation **钉死 ROTATION_0，绑定后不再改**。
 *                  SurfaceTexture 的变换矩阵只把画面从 sensor 朝向摆到设备的
 *                  *自然* 朝向，与 targetRotation 无关；钉住它，纹理里的画面
 *                  尺寸就不随启动时的握持姿势、也不随之后的旋转而变。屏幕转到
 *                  哪由 Dart 侧一个 RotatedBox 补上（预览尺寸事件里带
 *                  displayRotation）。
 *                  ——曾经试过让 Preview 的 targetRotation 跟着界面走：走
 *                  SurfaceTexture 这条路时 CameraX 并不会因此更新变换矩阵，
 *                  于是横屏下画面躺倒、previewSize 还停在竖屏那组值，预览与
 *                  关键点全对不上。
 *
 *   ImageAnalysis  targetRotation **必须跟着界面走**，否则关键点坐标与预览
 *                  不在同一个参考系里。它不动像素，只在 imageInfo.rotationDegrees
 *                  里报还差多少度，由 [orientLandmark] 作用到坐标上。
 *
 * 唯一要 Dart 配合的是前置镜像：以前镜像做在像素上，现在坐标上镜像了，
 * 预览得由 Dart 侧 Transform.scale(x: -1) 翻一下（GPU，免费）。
 *
 * 检测走 aircalc 原生核心（Rust），与 iOS/macOS 同一份实现，不再用 MediaPipe SDK。
 */
class HandCameraPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    EventChannel.StreamHandler {

    companion object {
        private const val TAG = "HandCamera"

        /**
         * 请求的分析分辨率，**按 sensor 朝向给**（横向）。
         *
         * CameraX 的 ResolutionStrategy 拿它跟设备支持的输出尺寸比对，而那些
         * 尺寸都是 sensor 朝向的；写成竖向的 480x640 匹配不上，会按
         * CLOSEST_LOWER 一路掉到 320x240——预览糊，日志里 analysisRes 一看
         * 便知。检测本身在 192x192 上做，再高只是白烧 CPU。
         */
        private val ANALYSIS_SIZE = Size(640, 480)

        /**
         * 朝向事件安静多久才去读一次真实值。
         *
         * 旋转过程中事件每 45 度来一发，而 Configuration 与 display.rotation
         * 会有一段时间对不上；事件一到就读会读到中间态。
         */
        private const val ROTATION_CHECK_DELAY_MS = 120L

        /** 读到变化后再补几次，防止那一次恰好落在中间态。 */
        private const val SETTLE_CHECKS = 3

        /** 每只手在 handDetect 返回数组里占的槽位，与 jni.rs 的 SLOT 一致。 */
        private const val LANDMARKS = 21
        private const val SLOT = 2 + LANDMARKS * 3 * 2
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var landmarkChannel: EventChannel
    private var landmarkSink: EventChannel.EventSink? = null

    private lateinit var previewSizeChannel: EventChannel
    private val previewSizeHandler = PreviewSizeStreamHandler()

    private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private var activityBinding: ActivityPluginBinding? = null

    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var previewSurface: Surface? = null
    private var preview: Preview? = null
    private var cameraProvider: ProcessCameraProvider? = null

    /**
     * 检测走 aircalc 原生核心。库内部是全局单例（模型只加载一次），这里只记初始化
     * 是否成功，以及每帧要用的两个参数。
     */
    @Volatile private var trackerReady = false
    @Volatile private var numHands = 1
    @Volatile private var minPresence = 0.5f

    private var analysis: ImageAnalysis? = null

    /// 绑定后的 CameraInfo，[recomputePreviewSize] 要拿 sensor 安装角。
    private var cameraInfoRef: androidx.camera.core.CameraInfo? = null
    private var orientationListener: OrientationEventListener? = null
    private var configCallback: ComponentCallbacks? = null
    private var lastTargetRotation: Int = Surface.ROTATION_0
    private var settleChecksLeft = 0

    /**
     * 一次初始化是否还在路上（从发起到 cameraProvider 回话，都在主线程）。
     *
     * 这个窗口里再来一次 initialize 会在第一个 SurfaceTexture 上再盖一个，
     * 头一个就留在注册表里没人往里画——反复进出页面正好这么触发。
     */
    private var starting = false

    /// 上一次推给 Flutter 的 buffer 尺寸，避免重复事件
    @Volatile private var lastPushedW: Int = 0
    @Volatile private var lastPushedH: Int = 0

    /// 相机写进 SurfaceTexture 的原始尺寸（sensor 朝向，横向）。
    @Volatile private var bufW: Int = 0
    @Volatile private var bufH: Int = 0

    /// 纹理里画面摆正后的尺寸（设备自然朝向），绑定后固定不变。
    @Volatile private var previewW: Int = 0
    @Volatile private var previewH: Int = 0

    /// 界面相对设备自然朝向转了多少度，Dart 侧据此加 RotatedBox。
    @Volatile private var displayRotationDegrees: Int = 0

    private val cameraExecutor = Executors.newSingleThreadExecutor()

    /**
     * 推理单独一条线程：handDetect 是同步调用，跑在相机线程上会顶住取帧队列，
     * 预览直接开始掉帧。与 iOS 的 inferenceQueue 对应。
     */
    private val inferenceExecutor = Executors.newSingleThreadExecutor()

    /// 上一帧还在算就跳过这一帧——否则推理排队积压，相机开始丢帧。
    @Volatile private var inferenceBusy = false

    // 粗略计时：每 30 帧一行，用来在真机上看清帧率卡在哪一段。
    // 相机间隔与推理耗时分开记：前者是相机给帧的节奏（暗光下会自己降到
    // 20 出头），后者是推理的实际开销，两者哪个大，瓶颈就在哪。
    // 相机帧与推理帧要分开计数：推理跳帧时两者对不齐，共用一个计数器算出来
    // 的均值是错的。
    @Volatile private var statFrames = 0
    @Volatile private var statCameraMs = 0L
    @Volatile private var statPrepMs = 0L
    @Volatile private var statInferFrames = 0
    @Volatile private var statInferMs = 0L
    @Volatile private var statLastFrameAt = 0L

    private val mainHandler = Handler(Looper.getMainLooper())

    // ── FlutterPlugin ─────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pluginBinding = binding
        methodChannel = MethodChannel(binding.binaryMessenger, "hand_camera")
        methodChannel.setMethodCallHandler(this)
        landmarkChannel = EventChannel(binding.binaryMessenger, "hand_camera/landmarks")
        landmarkChannel.setStreamHandler(this)
        previewSizeChannel = EventChannel(binding.binaryMessenger, "hand_camera/preview_size")
        previewSizeChannel.setStreamHandler(previewSizeHandler)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        landmarkChannel.setStreamHandler(null)
        previewSizeChannel.setStreamHandler(null)
        pluginBinding = null
        releaseAll()
        // 两条非守护线程，attach/detach 反复发生的宿主（add-to-app 或
        // FlutterEngineGroup）不关就会每轮攒一对，攒到进程结束。
        cameraExecutor.shutdown()
        inferenceExecutor.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activityBinding = binding }
    override fun onDetachedFromActivity() { releaseAll(); activityBinding = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activityBinding = binding }
    override fun onDetachedFromActivityForConfigChanges() { activityBinding = null }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { landmarkSink = events }
    override fun onCancel(arguments: Any?) { landmarkSink = null }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> handleInitialize(call, result)
            "warmUp"     -> handleWarmUp(call, result)
            "dispose"    -> handleDispose(result)
            else         -> result.notImplemented()
        }
    }

    // ── 手部检测 ──────────────────────────────────────────────────────────────

    /**
     * 只加载并预热模型，不开相机。
     *
     * 失败只返回 false 不报错——预热是提前量，进页面时 [handleInitialize]
     * 还会再试一次。
     */
    private fun handleWarmUp(call: MethodCall, result: Result) {
        val ctx = pluginBinding?.applicationContext
            ?: return result.success(false)
        val modelPath = call.argument<String>("modelAssetPath") ?: defaultModelPath()
        inferenceExecutor.execute {
            val ok = try {
                setupDetector(ctx, modelPath); true
            } catch (e: Exception) {
                Log.w(TAG, "预热失败: ${e.message}"); false
            }
            mainHandler.post { result.success(ok) }
        }
    }

    /**
     * 加载两个模型并初始化核心库。
     *
     * 模型是全局单例，已经加载过就直接返回——启动时的预热常常已经做完了。
     *
     * 必须跑在 [inferenceExecutor] 上：Android 这边 LiteRT 的 GPU 加速器走
     * OpenGL，它的上下文属于建模型的那条线程，换条线程 invoke 就会报
     * "Node number N (LITERT_OPENGL) failed to invoke"。所以加载、预热、
     * 每帧检测三者必须同线程，不能各用各的。
     */
    private fun setupDetector(ctx: Context, modelAssetPath: String) {
        if (trackerReady) return
        if (!AircalcNative.isAvailable) {
            throw IllegalStateException("aircalc 原生核心不可用，请把 aircalc_native 包加为依赖")
        }
        // Dart 传来的是目录下任一文件，只取目录部分，在同目录找这两个模型。
        //
        // Android 上是 .tflite（LiteRT + GPU delegate），iOS/macOS 上是 .pte
        // （裸 Core ML，由 tools/convert_hand_models.py 从同一份
        // TFLite 转来）。两个后缀都试，是为了这个插件不必知道自己被编进了
        // 哪个后端——找到哪个用哪个。
        val dir = modelAssetPath.substringBeforeLast('/', "")
        val palm = readModel(ctx, dir, "hand_detector")
        val landmark = readModel(ctx, dir, "hand_landmarks_detector")

        val rc = AircalcNative.handInit(palm, landmark)
        trackerReady = rc == 0
        Log.i(TAG, "手部检测初始化 ${if (trackerReady) "成功" else "失败(rc=$rc)"}"
            + "（palm=${palm.size}B lm=${landmark.size}B）")
        if (!trackerReady) throw IllegalStateException("手部检测初始化失败 rc=$rc")

        // 预热接在同一条推理线程上排队，而不是另起一条：GPU 上下文认线程。
        // 相机不必等它——这个方法本身已经在 inferenceExecutor 上异步跑，
        // 预览照常起来，头几帧只是排在预热后面。
        inferenceExecutor.execute {
            val t0 = android.os.SystemClock.elapsedRealtime()
            AircalcNative.handWarmUp()
            Log.i(TAG, "手部检测预热 ${android.os.SystemClock.elapsedRealtime() - t0}ms")
        }
    }

    private fun defaultModelPath() =
        "flutter_assets/packages/hand_camera/assets/models/hand_detector.tflite"

    /** 在 [dir] 下按 .tflite → .pte 的顺序找 [name]，都没有则抛异常。 */
    private fun readModel(ctx: Context, dir: String, name: String): ByteArray {
        for (ext in listOf("tflite", "pte")) {
            try {
                return readAsset(ctx, "$dir/$name.$ext")
            } catch (_: java.io.FileNotFoundException) {
                // 下一个后缀
            }
        }
        throw java.io.FileNotFoundException("$dir/$name.{tflite,pte} 都不存在")
    }

    private fun readAsset(ctx: Context, path: String): ByteArray =
        ctx.assets.open(path).use { it.readBytes() }

    // ── 初始化 ────────────────────────────────────────────────────────────────

    private fun handleInitialize(call: MethodCall, result: Result) {
        val binding  = pluginBinding
            ?: return result.error("NOT_READY", "no engine binding", null)
        val activity = activityBinding?.activity
            ?: return result.error("NOT_READY", "no activity", null)
        if (starting) {
            return result.error("BUSY", "上一次初始化还没完成", null)
        }

        numHands    = call.argument<Int>("numHands") ?: 1
        minPresence = (call.argument<Double>("minHandPresenceConfidence") ?: 0.5).toFloat()
        val modelPath = call.argument<String>("modelAssetPath") ?: defaultModelPath()

        starting = true
        inferenceExecutor.execute {
            try {
                setupDetector(binding.applicationContext, modelPath)

                mainHandler.post {
                    // 相机还没起来就被 dispose 了（用户划走），没什么可绑的。
                    if (!starting) {
                        return@post result.error("CANCELLED", "初始化期间已被释放", null)
                    }
                    val entry = binding.textureRegistry.createSurfaceTexture()
                    textureEntry = entry
                    // Surface 由 Preview 用例在 setSurfaceProvider 里自己建，
                    // 这里只要把 SurfaceTexture 交出去。

                    val future = ProcessCameraProvider.getInstance(binding.applicationContext)
                    future.addListener({
                        if (!starting) {
                            return@addListener result.error(
                                "CANCELLED", "初始化期间已被释放", null)
                        }
                        try {
                            cameraProvider = future.get()
                            val initialRot = uiRotation()
                            lastTargetRotation = initialRot
                            val info = bindUseCases(
                                cameraProvider!!, activity as LifecycleOwner,
                                entry.surfaceTexture(), initialRot,
                            )
                            startOrientationListener()
                            starting = false

                            result.success(mapOf(
                                "textureId"         to entry.id(),
                                "sensorOrientation" to info.sensorOrientation,
                                "previewWidth"      to info.previewWidth,
                                "previewHeight"     to info.previewHeight,
                                "cameraWidth"       to info.previewWidth,
                                "cameraHeight"      to info.previewHeight,
                                "displayRotation"   to displayRotationDegrees,
                            ))
                        } catch (e: Exception) {
                            starting = false
                            result.error("CAMERA_ERROR", e.message, e.stackTraceToString())
                        }
                    }, ContextCompat.getMainExecutor(binding.applicationContext))
                }
            } catch (e: Exception) {
                starting = false
                mainHandler.post { result.error("INIT_ERROR", e.message, e.stackTraceToString()) }
            }
        }
    }

    data class CameraInfo(
        val sensorOrientation: Int,
        val previewWidth: Int,
        val previewHeight: Int,
    )

    /**
     * 把自动曝光的帧率区间钉在设备支持的最高固定档（通常是 30-30）。
     *
     * 不设的话 AE 会为了在暗光下多攒光而拉长曝光时间，帧率随光线掉到 20 甚至
     * 15——日志里「相机间隔 50ms」就是这么来的。推理只要 7ms，瓶颈全在出帧上，
     * 所以宁可暗一点也要稳住帧率。
     *
     * 区间从 CameraX 暴露的 camera2 characteristics 里挑，不写死：不同机型
     * 支持的档位不一样，钉一个不支持的会被底层忽略甚至绑定失败。
     */
    @OptIn(ExperimentalCamera2Interop::class)
    private fun pinFrameRate(
        builder: ImageAnalysis.Builder,
        provider: ProcessCameraProvider,
        selector: CameraSelector,
    ) {
        // 绑定之前就要拿到 CameraInfo：capture request 选项必须在 build() 前设。
        val info = selector.filter(provider.availableCameraInfos).firstOrNull() ?: return
        val ranges = try {
            Camera2CameraInfo.from(info)
                .getCameraCharacteristic(
                    android.hardware.camera2.CameraCharacteristics
                        .CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES
                )
        } catch (e: Exception) {
            Log.w(TAG, "取不到 AE 帧率区间: ${e.message}")
            null
        } ?: return

        Log.i(TAG, "AE 支持的帧率区间: ${ranges.joinToString { "${it.lower}-${it.upper}" }}")

        // 优先固定档（lower == upper），其次上限最高的那个：固定档不给 AE
        // 留下调的余地，浮动档在暗光下照样会掉到 lower。
        val best = ranges.filter { it.upper >= 30 }
            .maxByOrNull { (if (it.lower == it.upper) 1000 else 0) + it.lower }
            ?: ranges.maxByOrNull { it.lower }
            ?: return

        Log.i(TAG, "钉住帧率区间 ${best.lower}-${best.upper}")
        Camera2Interop.Extender(builder).setCaptureRequestOption(
            android.hardware.camera2.CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, best
        )
    }

    /**
     * 建并绑定 Preview 与 ImageAnalysis 两个用例。
     *
     * 两者的 targetRotation 不一样，理由见类头：Preview 钉 ROTATION_0，
     * ImageAnalysis 跟着界面走。
     */
    private fun bindUseCases(
        provider: ProcessCameraProvider,
        lifecycle: LifecycleOwner,
        st: SurfaceTexture,
        rotation: Int,
    ): CameraInfo {
        provider.unbindAll()

        // 分辨率写死给：setTargetAspectRatio 自 CameraX 1.3 起废弃，且个别
        // 机型会挑出 1952x1952 这种方图，三倍的工作量换不来任何东西。
        val resolution = ResolutionSelector.Builder()
            .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
            .setResolutionStrategy(
                ResolutionStrategy(
                    ANALYSIS_SIZE,
                    // 宁可低不可高：每帧代价随像素线性涨，而检测是在 192x192
                    // 上做的，多出来的分辨率进不了模型。
                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER,
                )
            )
            .build()

        val ctx = pluginBinding?.applicationContext

        val previewUseCase = Preview.Builder()
            .setResolutionSelector(resolution)
            // 钉住不动：纹理里的画面始终相对设备自然朝向摆正，尺寸恒定。
            .setTargetRotation(Surface.ROTATION_0)
            .build()
        previewUseCase.setSurfaceProvider { request: SurfaceRequest ->
            val res = request.resolution
            // buffer 保持相机给的尺寸（sensor 朝向），旋转在变换矩阵里。
            st.setDefaultBufferSize(res.width, res.height)
            bufW = res.width
            bufH = res.height
            val surface = Surface(st)
            previewSurface = surface
            recomputePreviewSize()
            request.provideSurface(surface, ContextCompat.getMainExecutor(ctx!!)) {
                surface.release()
            }
        }
        preview = previewUseCase

        val selector = CameraSelector.Builder()
            .requireLensFacing(CameraSelector.LENS_FACING_FRONT)
            .build()

        val analysisBuilder = ImageAnalysis.Builder()
            .setResolutionSelector(resolution)
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            // RGBA_8888：手部检测要彩色输入，拿到就能直接送进核心库，
            // 不必自己做 YUV 转换。
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
            .setTargetRotation(rotation)
        pinFrameRate(analysisBuilder, provider, selector)
        val analysisUseCase = analysisBuilder.build()
        analysisUseCase.setAnalyzer(cameraExecutor) { proxy -> processFrame(proxy) }
        analysis = analysisUseCase

        val camera = provider.bindToLifecycle(
            lifecycle, selector, previewUseCase, analysisUseCase)
        cameraInfoRef = camera.cameraInfo
        val so = camera.cameraInfo.sensorRotationDegrees
        val res = previewUseCase.resolutionInfo?.resolution
        if (bufW == 0 || bufH == 0) {
            bufW = res?.width ?: 640
            bufH = res?.height ?: 480
        }
        displayRotationDegrees = rotationDegrees(rotation)
        recomputePreviewSize()

        Log.i(TAG,
            "so=$so  res=${res?.width}x${res?.height}  " +
                "upright=${previewW}x${previewH}  display=${displayRotationDegrees}度")

        return CameraInfo(
            sensorOrientation = so,
            previewWidth = previewW,
            previewHeight = previewH,
        )
    }

    /**
     * 算出纹理里那幅画面的尺寸。
     *
     * 要点是 SurfaceTexture 的变换矩阵由相机给，它只把 sensor 朝向摆到设备的
     * *自然* 朝向，与 targetRotation 无关——所以这个尺寸是恒定的，不能拿界面
     * 朝向去算（那样横屏时宽高会被错误地对调，正是之前横屏预览乱掉的原因）。
     *
     * 同理也不能用 preview.resolutionInfo.rotationDegrees：走 SurfaceTexture
     * 这条路时变换已经应用掉了，那个字段报的是「还剩多少度没转」，恒为 0。
     * targetRotation 钉在 ROTATION_0，转过的角度就是 sensor 自己的安装角。
     */
    private fun recomputePreviewSize() {
        if (bufW == 0 || bufH == 0) return
        val sensor = try {
            cameraInfoRef?.sensorRotationDegrees ?: 90
        } catch (_: Throwable) { 90 }
        val rot = ((sensor % 360) + 360) % 360
        val w = if (rot % 180 == 0) bufW else bufH
        val h = if (rot % 180 == 0) bufH else bufW
        previewW = w
        previewH = h
        pushPreviewSize(w, h)
    }

    private fun rotationDegrees(rot: Int): Int = when (rot) {
        Surface.ROTATION_0   -> 0
        Surface.ROTATION_90  -> 90
        Surface.ROTATION_180 -> 180
        Surface.ROTATION_270 -> 270
        else -> 0
    }

    // ── 朝向 ──────────────────────────────────────────────────────────────────

    /**
     * 朝向监听，照官方 camera_android_camerax 的 DeviceOrientationManager：
     * 传感器事件与配置变更都只是「去重读一次」的触发器，真值在防抖之后读。
     *
     * 物理旋转过程中 Configuration.orientation 与 display.getRotation() 会有
     * 一段时间对不上，事件一到就读会读到中间态。更麻烦的是最后一个传感器
     * 事件可能早于配置落定，此后再没有触发器，朝向就永久停在错的值上——
     * 表现为预览被裁成一条。配置变更回调是「已经落定」的权威信号，官方实现
     * 正是靠它兜住这一点。
     */
    private fun startOrientationListener() {
        val ctx: Context = activityBinding?.activity ?: pluginBinding?.applicationContext ?: return
        orientationListener?.disable()
        orientationListener = object : OrientationEventListener(ctx) {
            override fun onOrientationChanged(deg: Int) {
                if (deg == ORIENTATION_UNKNOWN) return
                scheduleRotationCheck()
            }
        }.also { if (it.canDetectOrientation()) it.enable() }

        configCallback?.let { activityBinding?.activity?.unregisterComponentCallbacks(it) }
        configCallback = object : ComponentCallbacks {
            override fun onConfigurationChanged(newConfig: Configuration) {
                // 配置变更是「已经落定」的权威信号，也正是 Flutter 收到新尺寸
                // 的同一时刻：预览角度与分析用例的 targetRotation 都在这里立刻
                // 生效，不等防抖。
                //
                // 防抖是给传感器事件准备的——旋转过程中 Configuration 与
                // display.rotation 有一段时间对不上，事件一到就读会读到中间态。
                // 但配置变更时两者已经一致，没有再等 120 毫秒的理由：等，界面
                // 就已经转好了而预览还躺着（或者预览转了而关键点还在旧参考系
                // 里），几百毫秒的错位一眼可见。
                //
                // 万一某些机型在这个回调里 display.rotation 仍是中间态，下面
                // 那条防抖检查会在 120 毫秒后纠正回来，自愈。
                applyRotation(uiRotation())
                scheduleRotationCheck()
            }
            override fun onLowMemory() {}
        }
        activityBinding?.activity?.registerComponentCallbacks(configCallback!!)

        scheduleRotationCheck()
    }

    /**
     * 等朝向事件安静 [ROTATION_CHECK_DELAY_MS] 再读。
     *
     * 旋转时事件每 45 度来一发，每发都重置计时器，最后读到的通常已经落定。
     */
    private fun scheduleRotationCheck() {
        mainHandler.removeCallbacks(rotationCheck)
        mainHandler.postDelayed(rotationCheck, ROTATION_CHECK_DELAY_MS)
    }

    /**
     * 让朝向变化在两条链上同时生效。
     *
     *   预览   Dart 侧的 RotatedBox，靠 previewSize 事件里的 displayRotation
     *   坐标   ImageAnalysis 的 targetRotation，决定每帧 rotationDegrees
     *
     * 两者必须一起翻：只翻一边，那段时间里关键点和画面就不在同一个参考系
     * 里——手在左边，骨架画在上边。
     *
     * targetRotation 只影响之后的帧，在途的帧各自带着自己的 rotationDegrees，
     * 所以切换点上不会出现半帧错位。
     */
    private fun applyRotation(rot: Int) {
        if (rot == lastTargetRotation && rotationDegrees(rot) == displayRotationDegrees) return
        lastTargetRotation = rot
        analysis?.targetRotation = rot
        displayRotationDegrees = rotationDegrees(rot)
        pushPreviewSize(previewW, previewH)
        Log.i(TAG, "朝向 -> ${displayRotationDegrees}度（预览与坐标同时切换）")
    }

    private val rotationCheck = object : Runnable {
        override fun run() {
            val rot = uiRotation()
            if (rot != lastTargetRotation) {
                // 兜底：正常路径上配置变更回调已经处理过了，这里只在它没赶上
                // （只有传感器事件、没有配置变更）或那次读到中间态时纠正。
                applyRotation(rot)
                // 刚变过就再多查几次：单次读仍可能落在 Configuration 与
                // display 不一致的中间态，读到变化本身说明还没稳。
                settleChecksLeft = SETTLE_CHECKS
            } else {
                settleChecksLeft--
            }
            if (settleChecksLeft > 0) mainHandler.postDelayed(this, ROTATION_CHECK_DELAY_MS)
        }
    }

    /**
     * 界面当前的朝向，取 Surface.ROTATION_* 之一。
     *
     * Configuration.orientation 定竖屏还是横屏，display.getRotation() 定朝哪边，
     * 两者合起来才是界面「实际」所处的朝向，也就是 Dart 布局看到的那个。
     */
    private fun uiRotation(): Int {
        val ctx: Context = activityBinding?.activity ?: pluginBinding?.applicationContext
            ?: return Surface.ROTATION_0
        val rotation = displayRotation()
        return when (ctx.resources.configuration.orientation) {
            Configuration.ORIENTATION_PORTRAIT ->
                if (rotation == Surface.ROTATION_0 || rotation == Surface.ROTATION_90)
                    Surface.ROTATION_0 else Surface.ROTATION_180
            Configuration.ORIENTATION_LANDSCAPE ->
                if (rotation == Surface.ROTATION_0 || rotation == Surface.ROTATION_90)
                    Surface.ROTATION_90 else Surface.ROTATION_270
            else -> Surface.ROTATION_0
        }
    }

    private fun displayRotation(): Int = try {
        val activity = activityBinding?.activity
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            activity?.display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            activity?.windowManager?.defaultDisplay?.rotation ?: Surface.ROTATION_0
        }
    } catch (_: Throwable) {
        Surface.ROTATION_0
    }

    // ── 每帧 ──────────────────────────────────────────────────────────────────

    private fun processFrame(proxy: ImageProxy) {
        val rgba: ByteArray
        val w: Int
        val h: Int
        val rotDeg: Int
        val t0 = android.os.SystemClock.elapsedRealtime()
        if (statLastFrameAt != 0L) statCameraMs += t0 - statLastFrameAt
        statLastFrameAt = t0
        try {
            w = proxy.width
            h = proxy.height
            rotDeg = proxy.imageInfo.rotationDegrees
            rgba = packRgba(proxy)
        } catch (e: Exception) {
            Log.e(TAG, "取帧失败: ${e.message}")
            return
        } finally {
            // 立刻还给相机，不等推理——占着这个缓冲会顶住 CameraX 的队列。
            proxy.close()
        }
        statPrepMs += android.os.SystemClock.elapsedRealtime() - t0
        if (++statFrames >= 30) {
            val infer = if (statInferFrames > 0) statInferMs / statInferFrames else -1
            Log.i(TAG, "30 帧均值：相机间隔 ${statCameraMs / statFrames}ms  " +
                "取帧 ${statPrepMs / statFrames}ms  推理 ${infer}ms  " +
                "(推理 $statInferFrames/$statFrames 帧, ${w}x$h)")
            statFrames = 0; statCameraMs = 0; statPrepMs = 0
            statInferFrames = 0; statInferMs = 0
        }

        if (!trackerReady || inferenceBusy) return
        inferenceBusy = true
        val hands = numHands
        val presence = minPresence
        try {
            inferenceExecutor.execute {
                try {
                    val t1 = android.os.SystemClock.elapsedRealtime()
                    val flat = AircalcNative.handDetect(rgba, w, h, hands, presence, 0)
                    statInferMs += android.os.SystemClock.elapsedRealtime() - t1
                    statInferFrames++
                    // 即便没检出也要发——否则手移出画面时 Dart 侧的骨架会僵在原地。
                    val output = convertResults(flat, rotDeg)
                    mainHandler.post { landmarkSink?.success(output) }
                } catch (e: Throwable) {
                    Log.e(TAG, "handDetect failed: ${e.message}")
                } finally {
                    inferenceBusy = false
                }
            }
        } catch (_: RejectedExecutionException) {
            // 刚过完上面的判断、引擎就被拆了。unbind 不等在途的那一帧，
            // 这个窗口无论拆除顺序怎么排都存在；这里咽掉，否则会变成
            // CameraX 分析线程上的未捕获异常。
            inferenceBusy = false
        }
    }

    /**
     * 把一帧 RGBA 拷成紧凑的字节数组。
     *
     * 相机缓冲的 rowStride 常带对齐填充，不等于 w*4；直接整块拷会让每一行
     * 错位、整幅图斜掉，检测自然什么都找不到。没有填充时走一次整块拷贝，
     * 有填充才逐行——多数机型是前者。
     */
    private fun packRgba(proxy: ImageProxy): ByteArray {
        val plane = proxy.planes[0]
        val w = proxy.width
        val h = proxy.height
        val rowBytes = w * 4
        val out = ByteArray(rowBytes * h)
        val buf = plane.buffer
        if (plane.rowStride == rowBytes) {
            buf.get(out, 0, minOf(out.size, buf.remaining()))
            return out
        }
        for (row in 0 until h) {
            buf.position(row * plane.rowStride)
            buf.get(out, row * rowBytes, rowBytes)
        }
        return out
    }

    private fun pushPreviewSize(w: Int, h: Int) {
        if (w == 0 || h == 0) return
        lastPushedW = w
        lastPushedH = h
        previewSizeHandler.push(w, h, displayRotationDegrees)
    }

    /**
     * 核心库返回的扁平 float 数组 → Flutter 侧的字典数组，顺带把坐标摆正。
     *
     * 布局见 jni.rs 的 `flatten_hands`：每只手
     * [handedness(0=左,1=右), presence, 63 个归一化坐标, 63 个世界坐标]。
     * 用扁平数组而不是对象数组，是为了不在 JNI 边界上造上百个 Java 对象。
     */
    private fun convertResults(flat: FloatArray, rotDeg: Int): List<Map<String, Any?>> {
        val output = mutableListOf<Map<String, Any?>>()
        var base = 0
        while (base + SLOT <= flat.size) {
            val handedness = if (flat[base] < 0.5f) "Left" else "Right"
            val presence = flat[base + 1].toDouble()
            val lmBase = base + 2
            val wlmBase = lmBase + LANDMARKS * 3

            val landmarks = ArrayList<Map<String, Double>>(LANDMARKS)
            val worldLandmarks = ArrayList<Map<String, Double>>(LANDMARKS)
            for (j in 0 until LANDMARKS) {
                val k = j * 3
                landmarks.add(orientLandmark(
                    flat[lmBase + k], flat[lmBase + k + 1], flat[lmBase + k + 2], rotDeg))
                worldLandmarks.add(orientLandmark(
                    flat[wlmBase + k], flat[wlmBase + k + 1], flat[wlmBase + k + 2], rotDeg))
            }
            output.add(mapOf(
                "handedness"      to handedness,
                "handednessScore" to presence,
                "landmarks"       to landmarks,
                "worldLandmarks"  to worldLandmarks,
            ))
            base += SLOT
        }
        return output
    }

    /**
     * 把一个点从 sensor 坐标系摆到 display 坐标系，并做前置镜像。
     *
     * 这就是原先用像素旋转换来的东西——每帧 21 个点，而不是 30 万个像素。
     * [rotDeg] 是 CameraX 报的「把这帧转多少度才是正的」，顺时针。
     * 归一化坐标下绕中心顺时针转 θ：
     *   90° → (1-y, x)   180° → (1-x, 1-y)   270° → (y, 1-x)
     *
     * 世界坐标用同一套变换：模型看到的是未旋转的图，输出自然也在 sensor
     * 系里，转过来才与之前像素旋转时的行为一致。z 轴与旋转无关，原样带过。
     */
    private fun orientLandmark(x: Float, y: Float, z: Float, rotDeg: Int): Map<String, Double> {
        var nx: Float
        var ny: Float
        when (rotDeg) {
            90   -> { nx = 1f - y; ny = x }
            180  -> { nx = 1f - x; ny = 1f - y }
            270  -> { nx = y;      ny = 1f - x }
            else -> { nx = x;      ny = y }
        }
        // 前置摄像头镜像。以前做在像素上（Matrix.postScale(-1f, 1f)），现在
        // 做在坐标上；预览那一半由 Dart 侧 Transform.scale(x: -1) 负责。
        nx = 1f - nx
        return mapOf("x" to nx.toDouble(), "y" to ny.toDouble(), "z" to z.toDouble())
    }

    private fun handleDispose(result: Result) { releaseAll(); result.success(null) }

    private fun releaseAll() {
        starting = false
        mainHandler.removeCallbacks(rotationCheck)
        settleChecksLeft = 0
        orientationListener?.disable()
        orientationListener = null
        configCallback?.let { activityBinding?.activity?.unregisterComponentCallbacks(it) }
        configCallback = null
        analysis = null
        cameraInfoRef = null
        bufW = 0; bufH = 0
        previewW = 0; previewH = 0
        displayRotationDegrees = 0
        preview = null
        cameraProvider?.unbindAll()
        cameraProvider = null
        // Surface 的释放交给 provideSurface 的回调：CameraX 可能还在往里写，
        // 这里直接 release 会让它写进一个已销毁的 Surface。
        previewSurface = null
        textureEntry?.release()
        textureEntry = null
        // 模型不卸：核心库是全局单例，页面进出之间留着，下次进来省掉几百毫秒
        // 的加载与预热。真正的释放在进程结束时由系统回收。
    }

    private class PreviewSizeStreamHandler : EventChannel.StreamHandler {
        private var sink: EventChannel.EventSink? = null
        private var last: Map<String, Any>? = null
        private val main = Handler(Looper.getMainLooper())

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            sink = events
            last?.let { events?.success(it) }
        }
        override fun onCancel(arguments: Any?) { sink = null }

        /// [displayRotation] 是界面相对设备自然朝向的角度，Dart 侧据此
        /// 给纹理加 RotatedBox（预览尺寸本身不随旋转变）。
        fun push(w: Int, h: Int, displayRotation: Int) {
            val payload = mapOf(
                "width" to w,
                "height" to h,
                "displayRotation" to displayRotation,
            )
            last = payload
            main.post { sink?.success(payload) }
        }
    }
}
