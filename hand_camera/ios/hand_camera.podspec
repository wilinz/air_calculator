Pod::Spec.new do |s|
  s.name             = 'hand_camera'
  s.version          = '0.0.1'
  s.summary          = 'Camera capture + hand landmark detection.'
  s.description      = 'iOS 相机采集 + Flutter Texture；手部检测走 aircalc 原生核心。'
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{swift,h}'
  s.dependency 'Flutter'
  # 多签名 Core ML 模型要求 iOS 18+。
  s.platform = :ios, '18.0'
  s.swift_version = '5.0'

  # 这里不构建任何原生代码。
  #
  # 手部检测在 aircalc 原生核心里，那是 aircalc_native 包的 build hook 产出、由 Flutter
  # 打包的 Dart code asset；Swift 侧用 dlsym 解析入口（见 MwhNative.swift），
  # 于是相机这条路径与 Dart 那边共用同一份库，而不是各自再打包一份。
  #
  # 也因此不再依赖 MediaPipeTasksVision——它只覆盖移动端，与 macOS/桌面
  # 走的 Rust 实现行为不一致。
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
