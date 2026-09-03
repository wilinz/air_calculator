Pod::Spec.new do |s|
  s.name             = 'hand_camera'
  s.version          = '0.0.1'
  s.summary          = 'Camera capture + hand landmark detection.'
  s.description      = 'macOS 相机采集 + Flutter Texture；手部检测走 aircalc 原生核心。'
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{swift,h}'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '15.0'
  s.swift_version = '5.0'

  # 这里不构建任何原生代码，也不再 vendored libtensorflowlite_c-mac.dylib。
  #
  # 手部检测在 aircalc 原生核心里，那是 aircalc_native 包的 build hook 产出、由 Flutter
  # 打包的 Dart code asset；Swift 侧用 dlsym 解析入口（见 MwhNative.swift），
  # 与 iOS、Android 走同一份实现。
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }
end
