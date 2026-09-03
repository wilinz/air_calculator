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

import android.util.Log

/**
 * aircalc 原生核心的手部检测入口。
 *
 * 与 iOS/macOS 的 [AircalcNative.swift] 对应：库并不由这个插件编译，它是 mwh 包
 * build hook 产出、由 Flutter 打包的 Dart code asset；相机这条路径与 Dart
 * 共用同一份，而不是各自打包一份。
 *
 * 这也是为了统一三端——原先 Android 与 iOS 走 MediaPipe SDK、只有 macOS 走
 * Rust，行为有差异，桌面端也无从复用。
 */
object AircalcNative {
    /** 库是否可用。为 false 时插件退化成无检测模式，而不是崩溃。 */
    @JvmStatic
    var isAvailable: Boolean = false
        private set

    init {
        isAvailable = try {
            // Flutter 把 code asset 作为普通 .so 放进 jniLibs，
            // System.loadLibrary 会在 lib/<abi>/ 下找到它。
            System.loadLibrary("aircalc")
            true
        } catch (e: UnsatisfiedLinkError) {
            Log.e("HandCamera", "找不到 aircalc code asset，请把 aircalc_native 包加为依赖: ${e.message}")
            false
        }
    }

    /** 初始化手部检测。两个模型都是内存中的字节。成功返回 0。 */
    @JvmStatic
    external fun handInit(palm: ByteArray, landmark: ByteArray): Int

    /** 是否已初始化。 */
    @JvmStatic
    external fun handReady(): Boolean

    /**
     * 预热：跑一次空推理，把 XNNPACK 的子图与线程池建起来。
     *
     * 必须在后台线程调——同步跑要几百毫秒，放在初始化链路里会让相机等它。
     */
    @JvmStatic
    external fun handWarmUp()

    /**
     * 在一帧上检测手部。
     *
     * @param pixels w*h*4 字节
     * @param format 0 = RGBA，1 = BGRA
     * @return 扁平数组，每只手 [handedness(0=左,1=右), presence, 63 个归一化坐标,
     *         63 个世界坐标]；空数组表示未检出。
     */
    @JvmStatic
    external fun handDetect(
        pixels: ByteArray,
        width: Int,
        height: Int,
        numHands: Int,
        minPresence: Float,
        format: Int,
    ): FloatArray

    /** 释放资源。重复调用安全。 */
    @JvmStatic
    external fun handDestroy()
}
