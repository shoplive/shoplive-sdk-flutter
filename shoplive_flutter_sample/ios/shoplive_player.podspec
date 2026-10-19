#
# shoplive_player - Flutter bridge for Shoplive iOS SDK 3.0.3 (DRAFT-flutter-sdk-302-ios design section 4; SMV-1749).
# The SDK XCFrameworks are downloaded from the GitHub release at pod install, verified by sha256
# (SDK Package.swift constants) and vendored. Keep this file ASCII-only (pod install may run without a UTF-8 locale).
#
require 'yaml'
load File.join(__dir__, 'shoplive_ios_sdk.rb')

# YAML.safe_load(File.read(...)) instead of safe_load_file: works on the macOS system Ruby 2.6 (Psych 3.1).
pubspec = YAML.safe_load(File.read(File.join(__dir__, '..', 'pubspec.yaml')))

# Shoplive iOS SDK version - must be identical in the three Shoplive podspecs (checked by a test, I-D-05).
shoplive_ios_sdk_version = '3.0.3'
# XCFrameworks owned by this pod and their sha256 (https://github.com/shoplive/shoplive-sdk-ios/blob/3.0.3/Package.swift)
shoplive_ios_sdk_artifacts = {
  'ShoplivePlayerSDK' => '2696ca66c4e285b6061ac892d23063e29ceb4bb3be5d07609fdf88bc03cc50eb',
}

ShopliveIosSdk.ensure!(pod_dir: __dir__, version: shoplive_ios_sdk_version, artifacts: shoplive_ios_sdk_artifacts)

Pod::Spec.new do |s|
  s.name             = 'shoplive_player'
  s.version          = pubspec['version']
  s.summary          = 'Shoplive player plugin for Flutter (live/VOD fullscreen player).'
  s.description      = 'Shoplive player plugin for Flutter (live/VOD fullscreen player). Built on Shoplive iOS SDK ' + shoplive_ios_sdk_version + '.'
  s.homepage         = 'https://github.com/shoplive/flutter-sdk-sample/tree/main/shoplive_flutter_sample'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Shoplive' => 'ask@shoplive.cloud' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  # Same version as this pod (the three packages are released together). ShopliveCore, ShopLiveWebRTCHelperSDK and
  # WebRTC are vendored by shoplive_core.
  s.dependency 'shoplive_core', s.version.to_s
  s.vendored_frameworks = shoplive_ios_sdk_artifacts.keys.map { |name| "Frameworks/#{name}.xcframework" }
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
