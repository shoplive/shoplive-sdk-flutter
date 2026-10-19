## 3.0.3

Built on Shoplive SDK 3.0.3 (Android `cloud.shoplive:shoplive-core:3.0.3`, iOS `ShopliveCore` 3.0.3). No Dart breaking change.

### Changed
* `ShopliveConfiguration.appVersion` is deprecated and ignored on both platforms: SDK 3.0.3 reads the app version itself (Android removed the field). The value is still type-checked (`INVALID_ARGUMENT` if not a string) and a warning is logged.
* Error `code` strings are the SDK 3.0.3 constant names, passed through unchanged. Android 3.0.3 removed `NOT_INITIALIZED_CONFIG` and `NOT_INITIALIZED_CAMPAIGN_KEY` and added new codes (for example `AUTHENTICATION_FAILED` and `PIP_*`); treat `code` as an opaque string.
* `ShopliveError.rawCode` is set on both platforms (iOS SDK 3.0.3 now provides it for every code).
* Android: the `exclusiveContent` guard for the `cloud.shoplive` group stays; SDK 3.0.3 is not on Maven Central, and the `shoplive-media3` conflict of 3.0.2 no longer applies. The `constraintlayout:2.2.1` pin is unchanged.
* iOS: downloads the SDK 3.0.3 XCFrameworks (`ShopliveCore`, `ShopLiveWebRTCHelperSDK`, `WebRTC`) and verifies the new sha256 values.

## 3.0.2

* Declares `androidx.constraintlayout:constraintlayout:2.2.1`. The SDK pulls `2.0.1` through `material:1.9.0`, whose solver throws `ClassCastException` during the in-app PIP transition; Gradle now resolves the fixed version.

First release of `shoplive_core`, built on Shoplive Android SDK 3.0.2 (`cloud.shoplive:shoplive-core:3.0.2`).

### BREAKING (from shoplive_player 1.x)
* Replaces 1.x `ShopLiveCommon` (`setAccessKey`, `setAuth`, `setAuthToken`, `setUser`, `setUtm*`, `clearAuth`) with `Shoplive.initialize`, `setUser`, `setStreamToken`, `logout`, `sendConversionEvent` and `getSdkVersion`.
* Every method returns a `Future` and throws `PlatformException` (`INVALID_ARGUMENT`, `SDK_ERROR`).
* Required strings (`accessKey`, profile `id`, `jwt`, stream token) must not be blank. Profile `id` is now required.

### Known limitations
* The bridge does not guard repeated `initialize` calls (hot restart, multiple engines); the SDK decides what happens.

### Requirements
* Flutter 3.22 / Dart 3.4 or later.
* Android: AGP 8.7, Gradle 8.9, JDK 17, minSdk 23, compileSdk 36.
* Android SDK artifacts come from `https://sdk.shoplive.cloud/maven-repo`. The `cloud.shoplive` group is restricted to that repository with `exclusiveContent`, because Maven Central hosts a conflicting `shoplive-media3:1.10.1.2`. See README.
* iOS 15.0 (Shoplive iOS SDK 3.0.2, XCFrameworks downloaded and sha256-verified during `pod install` - see README "iOS setup"). Set `platform :ios, '15.0'` in your Podfile. When you run `pod install` manually, use a UTF-8 locale.
* Upgrading from 1.x: run `flutter clean` once; stale 1.x iOS build products otherwise fail with "'ShoplivePlayerPlugin' has different definitions in different modules".
