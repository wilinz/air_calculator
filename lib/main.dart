import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'i18n/app_translations.dart';
import 'pages/formula_editor_page.dart';
import 'package:hand_camera/hand_camera.dart';
import 'services/mathwriting_recognition_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? bootError;
  FlutterError.onError = (details) {
    bootError ??= 'FlutterError: ${details.exceptionAsString()}';
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    bootError ??= 'Uncaught: $error\n$stack';
    return true;
  };

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  try {
    // 不再需要初始化 flutter_rust_bridge：Rust 核心库是 mwh 包 build hook
    // 产出的 code asset，符号由 Dart 运行时直接解析，没有需要提前打开的库。
    final initialLocale = await LocaleService.loadInitialLocale();
    runApp(AirCalculatorApp(initialLocale: initialLocale));

    // 识别模型的 Core ML 编译只在首次安装后发生一次（结果进应用的 Caches
    // 目录，跨启动保留），但那一次要几秒。放在这里趁用户还在浏览界面时
    // 做掉，而不是等进了编辑页、写完第一个公式才开始。
    //
    // 不 await：初始化与预热都在后台，卡住启动反而更糟。
    unawaited(MathWritingRecognitionService.instance.init());
    // 手部检测的两个模型同理，也在启动时预热，免得用户进空中书写页时
    // 才开始编译。只加载模型，不启动相机。
    unawaited(HandCamera.warmUp());
  } catch (e, st) {
    final msg = bootError != null
        ? 'Boot failed: $e\n$st\n\n--- earlier ---\n$bootError'
        : 'Boot failed: $e\n$st';
    runApp(_BootErrorApp(message: msg));
  }
}

class _BootErrorApp extends StatelessWidget {
  final String message;
  const _BootErrorApp({required this.message});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Text(
                  message,
                  style: const TextStyle(
                      color: Colors.redAccent,
                      fontFamily: 'Courier',
                      fontSize: 12),
                ),
              ),
            ),
          ),
        ),
      );
}

class AirCalculatorApp extends StatelessWidget {
  final Locale initialLocale;
  const AirCalculatorApp({super.key, required this.initialLocale});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'app_title'.tr,
      debugShowCheckedModeBanner: false,
      translations: AppTranslations(),
      locale: initialLocale,
      fallbackLocale: LocaleService.fallbackLocale,
      supportedLocales: LocaleService.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1976D2),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const FormulaEditorPage(isStandalone: true),
    );
  }
}
