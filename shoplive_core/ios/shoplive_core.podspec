#
# shoplive_core - Flutter bridge for Shoplive iOS SDK 3.0.5 (DRAFT-flutter-sdk-302-ios design section 4; SMV-1749, SMV-1899).
# The SDK XCFrameworks are downloaded from the GitHub release at pod install, verified by sha256
# (SDK Package.swift constants) and vendored. Keep this file ASCII-only (pod install may run without a UTF-8 locale).
#
require 'yaml'
load File.join(__dir__, 'shoplive_ios_sdk.rb')

# YAML.safe_load(File.read(...)) instead of safe_load_file: works on the macOS system Ruby 2.6 (Psych 3.1).
pubspec = YAML.safe_load(File.read(File.join(__dir__, '..', 'pubspec.yaml')))

# Shoplive iOS SDK version - must be identical in the three Shoplive podspecs (checked by a test, I-D-05).
shoplive_ios_sdk_version = '3.0.5'
# XCFrameworks owned by this pod and their sha256 (https://github.com/shoplive/shoplive-sdk-ios/blob/3.0.5/Package.swift)
shoplive_ios_sdk_artifacts = {
  'ShopliveCore' => 'acf9e29efd58daf85d8d0ebbc4f4be3cd30f732874dc7c9c78870ddb88c27d24',
  'ShopLiveWebRTCHelperSDK' => 'e5d64f511edc10ee0ddb07f5e74dc7dcd606de0eb999010405bb55395b3388f8',
  'WebRTC' => '404db28c04852434a0736e44cd5c22c49e6a99ec6ca3f0d66a4b0da0626bb601',
}

ShopliveIosSdk.ensure!(pod_dir: __dir__, version: shoplive_ios_sdk_version, artifacts: shoplive_ios_sdk_artifacts)

Pod::Spec.new do |s|
  s.name             = 'shoplive_core'
  s.version          = pubspec['version']
  s.summary          = 'Shoplive core plugin for Flutter (initialize, user, conversion).'
  s.description      = 'Shoplive core plugin for Flutter (initialize, user, conversion). Built on Shoplive iOS SDK ' + shoplive_ios_sdk_version + '.'
  s.homepage         = 'https://github.com/shoplive/flutter-sdk-sample/tree/main/shoplive_core'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Shoplive' => 'ask@shoplive.cloud' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.vendored_frameworks = shoplive_ios_sdk_artifacts.keys.map { |name| "Frameworks/#{name}.xcframework" }
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
