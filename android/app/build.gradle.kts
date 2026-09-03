import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 签名配置从 android/local.properties 读取（该文件被 .gitignore 忽略，不入库）。
// release 缺配置时回退到 debug 签名，保证 `flutter run --release` 仍可用。
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.reader(Charsets.UTF_8).use { reader ->
        localProperties.load(reader)
    }
}

// 构建期把 platform_models/android/ 的权重拷到 assets/models/，让 Flutter
// 在打 flutter_assets 之前看到正确的 .pte 文件。脚本缺源会 fail-fast。
val copyPlatformModels = tasks.register<Exec>("copyPlatformModelsAndroid") {
    val projRoot = file("../..")
    workingDir = projRoot
    commandLine("bash", "tool/copy_platform_models.sh", "android")
    // 输入输出声明让 gradle 增量构建生效
    inputs.dir(projRoot.resolve("platform_models/android"))
        .withPropertyName("platformModels")
        .skipWhenEmpty(false)
    // 手部检测的权重归 hand-track 仓所有，与它的转换脚本放在一起；
    // 两个仓并排 checkout。
    inputs.dir(projRoot.resolve("../hand-track/models/android"))
        .withPropertyName("handModels")
        .skipWhenEmpty(false)
    outputs.files(
        projRoot.resolve("assets/models/prefix_enc.tflite"),
        projRoot.resolve("assets/models/decoder.tflite"),
        projRoot.resolve("assets/models/vocab.json"),
        projRoot.resolve("hand_camera/assets/models/hand_detector.tflite"),
        projRoot.resolve("hand_camera/assets/models/hand_landmarks_detector.tflite"),
    )
}

// 让所有读 assets/models/ 的 task 在它之后跑：
//   - preBuild：保险起见，整个 build 链最早期挂一份
//   - compileFlutterBuild{Debug,Profile,Release}：flutter_tools 在这一步把 pubspec
//     assets 打成 flutter_assets，是真正消费 .pte 的环节，必须显式 dependsOn 才能
//     满足 Gradle 8+ 的严格依赖校验
tasks.matching {
    it.name == "preBuild" || it.name.startsWith("compileFlutterBuild")
}.configureEach {
    dependsOn(copyPlatformModels)
}

android {
    namespace = "com.wilinz.air_calculator"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wilinz.air_calculator"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24  // CameraX 与 ExecuTorch 运行时都从 API 24 起
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 只出 arm64。推理运行时（LiteRT 的 AAR 与我们自编的静态库）只备了
        // arm64-v8a 一份，别的 ABI 在 build hook 那步就会因为找不到构件而挂；
        // 而且模型本身近 200MB，多打一个 ABI 没有意义。
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    // 推理运行时是静态链接进 libmwh.so 的（见 air_calculator-rs 的 build.rs），
    // 不该再有独立的 ExecuTorch .so 出现在 lib/arm64-v8a/ 下。这里保留这份
    // 排除清单当护栏：哪天误引入一个自带预编译 .so 的插件，几十 MB 会悄悄
    // 进包而构建不报任何错。
    // 新增模式时的查法：构建后 unzip -l <apk> 'lib/arm64-v8a/*'。
    packaging {
        jniLibs {
            excludes += setOf(
                "**/libexecutorch*.so",       // libexecutorch.so / libexecutorch_core.so / libexecutorch_ffi.so
                "**/libextension_*.so",       // libextension_module.so / libextension_data_loader.so / libextension_tensor.so / libextension_threadpool.so
                "**/libxnnpack_backend.so",
                "**/libXNNPACK.so",
                "**/libpthreadpool.so",
                "**/libcpuinfo.so",
                "**/libcustom_ops.so",
                "**/libquantized_*.so",       // libquantized_kernels.so / libquantized_ops_aot_lib.so
                "**/liboptimized_kernels.so",
                "**/libportable_kernels.so",
                "**/libcoreml_backend.so",
                "**/libmps_backend.so",
                "**/libvulkan_backend.so",
            )
        }
    }

    signingConfigs {
        create("release") {
            if (localProperties["storeFile"] != null) {
                storeFile = file(localProperties["storeFile"] as String)
                storePassword = localProperties["storePassword"] as String
                keyAlias = localProperties["keyAlias"] as String
                keyPassword = localProperties["keyPassword"] as String
            } else {
                println("Release build signing not configured. Use debug signing.")
            }
        }
        getByName("debug") {
            storeFile = file("../debug-store-file/debug.keystore")
            storePassword = "android"
        }
    }

    buildTypes {
        debug {
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
            }
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
            }
            // 有 release 签名配置时用正式签名，否则回退到 debug 签名让 `flutter run --release` 可用。
            signingConfig = if (localProperties["storeFile"] != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 相机与手部检测都在 hand_camera 插件里，它自带 CameraX 依赖。
    // 本模块原先那份 MediaPipe + CameraX 的实现（handdetector 包）已删除，
    // tasks-vision 连同它的 native 库一起从包里去掉。
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
