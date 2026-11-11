### Breaking
* `ShoplivePlayerEvent` has a new subtype, `ShoplivePlayerShareRequested`. A `switch` over `ShoplivePlayerEvent` without a `default` (or `_`) case must add it; code with a `default` case or `is` checks compiles unchanged. The native SDKs 3.0.4 made the same change.
* `ShopliveResizeMode` has a new value, `auto` (before `unknown`). A `switch` over `ShopliveResizeMode` without a `default` (or `_`) case must add it.
* Code that `implements` a public plugin class (for example a test double) must implement the new members: `ShoplivePlayerStateChanged.closeReason`, `ShoplivePipOptions.closeButton` / `restoreButton`, `ShopliveNavigationOptions.isCustomShareEnabled`, `ShopliveAndroidPlayerOptions.backPressEntersPip` and `ShoplivePlayer.startPreview`.

### Added
* Custom share: `ShopliveNavigationOptions.isCustomShareEnabled`. When `true`, tapping share in the player does not open the SDK share sheet; instead `events` delivers one `ShoplivePlayerShareRequested` per SDK share request, with `ShopliveShareInfo` (`url`, `campaignKey`, `title`, `descriptionText`, `thumbnailUrl`, all nullable). `false` or omitted keeps the SDK share sheet. Android and iOS.
* In-app PIP buttons: `ShoplivePipOptions.closeButton` and `restoreButton` take `ShopliveButtonOptions(isHidden:, nativeImageName:)`. `isHidden` hides the button (it wins over the image). `nativeImageName` is the name of an image in your app: an Android drawable resource name or an iOS Asset Catalog image name (not a Flutter asset path). A name that cannot be resolved does not fail the call; a warning is logged and that button is drawn as if no image was set. `getConfiguration()` returns only `isHidden`. See README.
* Close reason: `ShoplivePlayerStateChanged.closeReason` (`ShopliveCloseReason.userAction`, `appRequest`, `accessKeyChanged`; unknown values map to `unknown`) is set when `state` is `closed`, and is `null` for other states. `ShoplivePlayerState` is unchanged. `getState()` still returns `closed` without a reason. The `closed` the plugin sends itself when a replacing `start` fails has the reason `appRequest`.
* Android only: `ShopliveAndroidPlayerOptions.backPressEntersPip` (Android SDK 3.0.6 `PipOptions.backPressEntersPip`). The system back button enters PIP only when it and `pip.isInAppPipEnabled` are both `true`; otherwise back closes the session. `enterOSPipOnBackPressed` is deprecated and reads and writes the same value (if both are given, `backPressEntersPip` wins). iOS ignores it.
* `ShopliveResizeMode.auto` (Android SDK 3.0.6 `DEFAULT`): Android picks `fill` on phones and `fit` on tablets and unfolded foldables. iOS applies it as `fill` and `getResizeMode()` returns `fill`. On Android, `getResizeMode()` of a new player returns `auto` (3.0.3: `fill`).
* Campaign list: `ShoplivePlayerAPI.getCampaigns({request, cancelToken})` with `ShopliveCampaignListRequest` / `ShopliveCampaignListResponse` / `ShopliveCampaignListItem` / `ShopliveCampaignLifecycle` (sealed `ShopliveCampaignLifecycleStatus`, unknown server values keep their text) / `ShopliveCampaignMetrics`, times as UTC `DateTime`. `ShopliveCancelToken` cancels the native request and ends the call with `PlatformException(code: 'CANCELLED')` (`ShoplivePlatformErrorCode.cancelled`). SDK failures end with `SDK_ERROR` and the SDK error in `details` (`ShopliveError.tryParse(e.details)`). Android and iOS.
* Preview: `ShoplivePlayer.startPreview(campaignKey)` opens a muted preview window (in-app PIP) that unmutes when the viewer expands it. Android uses the SDK `ShoplivePlayer.startPreview` rules. iOS SDK 3.0.5 has no such call, so the plugin emulates the same decisions with the SDK preview presets; another key reopens the window at its default position, and a few cases differ (see README "Preview"). A blank key fails with `INVALID_ARGUMENT` on both platforms.

### Changed
* Calling `Shoplive.initialize` with a different access key closes viewer players started with the previous key: you get `stateChanged(closed)` with `closeReason: accessKeyChanged`. Start the player again if needed. Android: `ShopliveUser.token` users must call `Shoplive.setUser` again.
* Android: a new `start` (and a PIP `play`) also closes other Shoplive player sessions in the app, for example a native `ShoplivePlayer` or a player of another Flutter engine. Those sessions get `closed` with `appRequest`. The previous session of this plugin is still closed without a `closed` event, as before.
* Android: the system back button closes the player by default (SDK 3.0.6; it entered PIP before). Set `android.backPressEntersPip: true` with `pip.isInAppPipEnabled: true` to keep entering PIP.
* Android: `pip.isInAppPipEnabled` now allows PIP requested while the app is in use and `pip.isOSPipEnabled` allows PIP when the user leaves the app; one no longer turns the other off. PIP from the fullscreen player and from an embedded player is the system PIP window (SDK 3.0.5).
* Android: a fullscreen PIP request on a device where the user turned off picture-in-picture for the app sends an `error` event with `code` `PIP_DISABLED_BY_USER` (`rawCode` 9511); the screen does not change (SDK 3.0.6).
* Android: the default screen fit of a new player is `auto` (SDK 3.0.6). On tablets and unfolded foldables the default now fits the whole video, and an explicit `fill` stays `fill`.
* `Shoplive.setUser` / `logout` while a player is showing reload only the player's web overlay; the video and the window stay. `reload()` afterwards is not needed.
* A configuration change while a session is running reaches it at a time that depends on the field: Android applies `pip`, `sound.mixWithOthers`, `appearance`, `navigation` and `android.*` at once and `sound.muteOnStart`, `overlay.ui` and `customParameters` from the next `start`, `play` or `reload`; iOS applies `navigation.shareScheme`, `overlay.ui` and `sound.muteOnStart` at once and the rest from the next `start`, `play` or `reload`. Before, Android ignored it until the next `start`.
* iOS: `setConfiguration` while a session is running no longer resets the values set with `setResizeMode` / `setOverlayUI` on that player.
* iOS: changing `configuration.type` while a session is running now takes effect from the next `start` (3.0.3 applied it from the next `play` or `reload`).
* Android: sharing uses `navigation.shareScheme` before the web page's share URL (surrounding spaces are removed), the same as iOS.
* Android: web commands without data (for example `LOGIN_REQUIRED`, `CLICK_BACK_BUTTON`) arrive as `webCommandReceived` with an empty `payload` (`{}`), the same as iOS. `reload()` keeps the last play options.
* Android: the SDK 3.0.6 libraries are obfuscated and `shoplive-core` / `shoplive-player-sdk` must use the same version (the Flutter packages pin it). Check a release build of your app once after upgrading.
* iOS: downloads `ShoplivePlayerSDK` 3.0.5 and verifies the new sha256.

### Fixed
* iOS: a player that closes while it is not on screen (in-app PIP or system PIP closed by the user or by `close()`, a preview that ends by itself) is now released when its `closed` arrives: `getState()` returns `idle`, as after closing a fullscreen player. Before, it kept returning `closed` until the next `start`. A player stopped on screen (`stop()`, or the stop inside `reload()`) is still kept until `close()` or the next `start`.

### Known limitations
* `ShoplivePlayerAPI.getCampaigns` has no plugin wait limit. The native HTTP limits apply (Android 30 s per call, iOS 10 s without data); if the native side never answers, the `Future` may not complete. Add `Future.timeout` and call `ShopliveCancelToken.cancel()` (example in README "Campaign list").
* iOS: `startPreview` before `Shoplive.initialize` is not reported as an error. Without an access key the preview may open, then end with `closed` (`userAction`), and no `error` event arrives (iOS SDK 3.0.5 behavior, seen on the simulator). Call it after `initialize` has completed.
* Android: `startPreview` may end with `SDK_ERROR` although the SDK only ignored the call, when a viewing window the SDK cannot link to a player is showing.
* `reload()` sends `stateChanged(closed)` with `appRequest` and then `loading` on both platforms; the session goes on. Do not treat that `closed` as the end of the session (iOS checked on the simulator; a device check is pending).
* With `isCustomShareEnabled: true`, keep a listener on `ShoplivePlayer.instance.events`. Without one, tapping share does nothing (the SDK sheet does not open either) and only a warning is logged; on Android the next time the user leaves the app, system PIP is skipped once.
* Android: the fullscreen player runs in its own task. If you open your share screen from the Flutter host Activity, closing it may bring your app screen to the front instead of the broadcast. Switching to in-app PIP (`enterPictureInPicture()`) before opening the share screen is recommended.
* iOS: changing `configuration.type` rebuilds the configuration from the `.preview` / `.default` preset, so `isCustomShareEnabled` and the PIP button settings return to their defaults unless you pass them in the same call (Android keeps them).

## 3.0.3

Built on Shoplive SDK 3.0.3 (Android `cloud.shoplive:shoplive-player-sdk:3.0.3`, iOS `ShoplivePlayerSDK` 3.0.3). Depends on `shoplive_core` 3.0.3. No Dart breaking change.

### Added
* `ShoplivePipOptions.isDragOutToCloseEnabled`: whether the in-app PIP window closes when dragged off the screen (Android and iOS). Omitted keeps the current value (the SDK default is `true` on both platforms); `getConfiguration()` returns it.

### Fixed
* `start` while a session is open (or after `close`) now opens a new player with the configuration of that call. Before, Android reused the started SDK player, which ignores new settings (for example, a `live` start after an in-app PIP `preview` session opened as a preview with a black screen). iOS used to switch campaigns in the same controller; it now closes it and presents a new one, the same as Android. Use `play` to switch campaigns while keeping the current settings.

### Changed
* `ShoplivePlayerType.preview` on iOS also sets the SDK 3.0.3 `ShoplivePlayerConfiguration.type`, in addition to selecting the `.preview` preset.
* Error events: `rawCode` is now always set on iOS too. Android player errors use the SDK 3.0.3 shared error type (`cloud.shoplive.core`). Every 3.0.2 player error code name still exists there, and the event keys (`code`, `message`, `rawCode`, `recoverable`) are unchanged. SDK 3.0.3 adds new codes, so keep treating `code` as an opaque string.
* Coupon / custom-action results: an omitted `alertType` now means `toast` on both platforms. iOS already did this; Android used to pass no value (the web default). SDK 3.0.3 changed its own initializer default to `alert`; the plugin does not use it. The fallback result is unchanged (`success: false, status: keep, alertType: toast`).
* iOS: downloads `ShoplivePlayerSDK` 3.0.3 and verifies the new sha256.

## 3.0.2

Rewrite on Shoplive Android SDK 3.0.2 (`cloud.shoplive:shoplive-player-sdk:3.0.2`).

### BREAKING
* Removed the whole 1.x Dart API: `ShopLivePlayer`, `ShopLiveCommon`, their data and event classes, and all `ShopLive*` names.
* Removed Shortform (`shoplive_shortform.dart`); it does not exist in SDK 3.x.
* Split into three packages: `shoplive_core` (initialize/user/conversion), `shoplive_player` (this package, re-exports core) and `shoplive_streamer` (broadcast).
* New channel contract. The method channel is `shoplive_player`, and events come on `shoplive_player/events` and `shoplive_player/requests` as typed maps. The 10 per-event channels of 1.x are gone.
* Every method now returns a `Future` and throws `PlatformException` (`INVALID_ARGUMENT`, `NO_HOST_SCREEN`, `NOT_RUNNING`, `SDK_ERROR`). Previously `void` methods swallowed errors.
* Class names changed from `ShopLive*` to `Shoplive*`. See the migration table in README.
* 1.8.x APIs without an SDK 3.0.2 equivalent are removed: `closeButtonConfig` (`ShopLiveCloseButtonConfig`), `hidePreview`, the `previewClose` stream and its close reasons, and the preview options `pipRadius`, `enableSwipeOut`, `pipMaxSize`. `setResizeMode` keeps only `fill` / `fit` (no `auto` / `centerCrop`). See the migration table in README.
* `getPluginVersion()` is kept as `ShoplivePlayer.instance.getPluginVersion()`; `getSdkVersion()` moved to `Shoplive.getSdkVersion()`. `sendDownloadCouponResult` / `sendCustomActionResult` are replaced by `respond` on the request objects.

### Behavior changes
* `configuration.appearance.indicatorColor` takes an unsigned 32-bit ARGB value such as `0xFF00FF00` (previously rejected on Android as out of range) and `getConfiguration` returns it unsigned.
* iOS: see README "iOS differences" (ignored Android-only fields, `type` presets, nullable playback/error fields, default `alertType`).
* Custom web actions are no longer answered with success automatically. Without a listener, or without a `respond` before the timeout (default 10 s, configurable 1–120 s), the SDK receives `success: false, status: keep, alertType: toast`.
* Coupon requests now have a response protocol: `couponRequests` + `respond`. In 1.x, coupon requests were never answered.
* Share handling changed: the 1.x Android bridge overrode `handleShare` and ran the SDK default share after a 100 ms delay. SDK 3.x has no share handler, so configure sharing with `configuration.navigation.shareScheme`.
* Removed the hard-coded transparent status bar, tablet aspect ratio and audio-focus mute. Use `ShoplivePlayerConfiguration` (`android.isStatusBarVisible`, `sound.*`); there is no equivalent for the tablet aspect ratio or the transparent status bar.
* The 1.x `log` event has no confirmed 3.x replacement. `webCommandReceived` / `analytics` may cover some uses (unverified).
* Event payload numbers are no longer converted from integral doubles to integers. Integers arrive as `int`, other numbers as `double`.
* `showPreview` is replaced by `start` with `presentationStyle: pip` and `configuration.type: preview` (see README).
* Configuration given to `start` / `setConfiguration` is merged on top of the current settings, and `getConfiguration` is new.
* `close` always succeeds. Session commands (`play`, `stop`, `reload`, `send`, `setMuted`, `enter/exitPictureInPicture`) throw `NOT_RUNNING` when no session is running.

### In-app PIP on Flutter hosts
* Fixed: playback stopped (HLS) or the WebRTC session closed, sometimes with a native crash, right after switching from fullscreen to in-app PIP when the host is the default `FlutterActivity`. SDK 3.0.2 moves the player view into the host screen and re-binds it to the host lifecycle only when the host's decor view has a `ViewTreeLifecycleOwner`. `FlutterActivity` does not register one, so the player stayed bound to the closing fullscreen Activity. The plugin now registers the host Activity as the `ViewTreeLifecycleOwner` when none is set. No change is needed in your `MainActivity`; hosts that already register one (for example `FlutterFragmentActivity`) are left untouched.
* Fixed: `ClassCastException` in the ConstraintLayout solver during the PIP transition. The SDK pulls `constraintlayout:2.0.1` through `material:1.9.0`; `shoplive_core` now declares `constraintlayout:2.2.1`, so Gradle resolves the fixed version (unless your app pins an older one).
* To let in-app PIP continue as system PIP when the app goes to the background, declare `android:supportsPictureInPicture="true"` on your host Activity. Otherwise the player reports `PIP_ACTIVITY_NOT_DECLARED`.

### Known limitations
* Nullable settings (`navigation.shareScheme`, `android.isVolumeKeyEnabled`) cannot be reset to `null` from Dart.
* After the Flutter engine is detached and attached again, a session left open by the previous engine cannot be controlled. Its requests are answered with the fallback result.
* Only synchronous request-listener exceptions trigger an immediate fallback. Errors after an `await` are not caught.
* If the SDK silently rejects `start` (launch Activity gone or not a `LifecycleOwner`), it only logs; `start` still completes.

### Requirements
* Flutter 3.22 / Dart 3.4 or later.
* Android: AGP 8.7, Gradle 8.9, JDK 17, minSdk 23, compileSdk 36.
* Android SDK artifacts come from `https://sdk.shoplive.cloud/maven-repo`. The `cloud.shoplive` group is restricted to that repository with `exclusiveContent`, because Maven Central hosts a conflicting `shoplive-media3:1.10.1.2`. See README.
* iOS 15.0 (Shoplive iOS SDK 3.0.2, XCFrameworks downloaded and sha256-verified during `pod install` - see README "iOS setup"). Set `platform :ios, '15.0'` in your Podfile. When you run `pod install` manually, use a UTF-8 locale.
* Upgrading from 1.x: run `flutter clean` once; stale 1.x iOS build products otherwise fail with "'ShoplivePlayerPlugin' has different definitions in different modules".

## 1.9.0
* Update Shoplive iOS/Android SDK to 1.9.0. Android artifacts resolve from `https://sdk.shoplive.cloud/maven-repo`, with ExoPlayer `2.19.1.20`. Minimum iOS is 15.0
* Remove the shortform API and the Shoplive shortform SDK dependency

## 1.8.14
* Add `ShopLivePlayer.setResizeMode()` — passes through the native `setResizeMode` API for the live player (`ShopLiveResizeMode.auto` / `centerCrop` / `fit`)
* Update Shoplive iOS/Android SDK to 1.8.13

## 1.8.13
* Update Shoplive iOS/Android SDK to 1.8.11

## 1.8.12
* Bump version to v1.8.12

## 1.8.11
* Bump version to v1.8.11

## 1.8.10
* Bump version to v1.8.10

## 1.8.9
* Bump version to v1.8.9

## 1.8.8
* Bump version to v1.8.8

## 1.8.4
* Bump version to v1.8.4

## 1.8.2
* Bump version to v1.8.2

## 1.8.0
* Bump version to v1.8.0

## 1.7.9
* Bump version to v1.7.9

## 1.7.5
* Bump version to v1.7.5

## 1.7.4
* Bump version to v1.7.4

## 1.7.3
* Bump version to v1.7.3

## 1.7.2
* Bump version to v1.7.2

## 1.7.1
* Bump version to v1.7.1

## 1.7.0+2
* Bump version to v1.7.0+2

## 1.7.0+1
* Revert a streamer feature
* Bump version to v1.7.0+1

## 1.7.0
* Add a streamer feature
* Bump version to v1.7.0

## 1.6.6
* Bump version to v1.6.6

## 1.6.5+1
* Bump version to v1.6.5+1

## 1.6.5
* Bump version to v1.6.5

## 1.6.2
* Bump version to v1.6.2

## 1.5.15+1
* Bump version to v1.5.15+1

## 1.5.15
* Bump version to v1.5.15

## 1.5.14+3
* Add a startPictureInPicture
* Add a stopPictureInPicture

## 1.5.14+2
* Add a showPreview

## 1.5.14+1
* Remove a jfrog

## 1.5.14
* Bump version to v1.5.14

## 1.5.13
* Bump version to v1.5.13

## 1.5.12
* Bump version to v1.5.12

## 1.5.11+3
* Bump version to v1.5.11+3

## 1.5.11+2
* Bump version to v1.5.11+2

## 1.5.11+1
* Bump version to v1.5.11+1

## 1.5.11
* Bump version to v1.5.11

## 1.5.7
* Bump version to v1.5.7
* Add a iOS Privacy manifest

## 1.5.6+1
* Bump version to v1.5.6+1

## 1.5.6
* Bump version to v1.5.6

## 1.5.4
* Bump version to v1.5.4

## 1.5.3
* Bump version to v1.5.3

## 1.5.2+1
* Add a shortform
* Migration player api

## 1.5.2
* Bump version to v1.5.2

## 1.5.1
* Bump version to v1.5.1

## 1.5.0+1
* Add a keep annotation

## 1.5.0
* Bump version to v1.5.0

## 1.4.9
* Bump version to v1.4.9

## 1.4.8
* Bump version to v1.4.8

## 1.4.7
* Bump version to v1.4.7

## 1.4.6
* Bump version to v1.4.6

## 1.4.5
* Bump version to v1.4.5

## 1.4.4
* Bump version to v1.4.4

## 1.4.3
* Bump version to v1.4.3

## 1.4.2
* Bump version to v1.4.2
* Fix to crash ios 13.x 

## 1.4.1
* Bump version to v1.4.1

## 1.4.0
* Bump version to v1.4.0

## 1.3.3
* Add to feature setMixWithOthers, feature useCloseButton
* Fix a player status

## 1.3.1+4
* Fix a android parsing issue

## 1.3.1+3
* Fix a android parsing issue

## 1.3.1+2
* Fix a parsing issue

## 1.3.1+1
* Fix a parsing issue

## 1.3.1
* Updated so that even if the PIP conversion interface (startPictureInPicture, stopPictureInPicture) is called simultaneously several times, it only works once.
* When the share button is clicked and there is no set URL, an error code will be delivered to the onError Handler.
* Fixed an issue that could affect the lifecycle of customer's app when switching to PIP after launching Shoplive Player with a deep link.
* Applied an animation to make the chat input window appear more natural.
* Fixed the issue where the chat input window covered the chat message.
* Animation images are now available for broadcasting. (gif, apng, webp, etc.)

## 1.3.0+6
* Fix ios user parameter.

## 1.3.0+5
* Fix a user parameter.
* Change Future<void> to void function.

## 1.3.0+4
* Change PlayerStatus to enum status. 

## 1.3.0+3
* Change CREATE to CREATED. Change CREATE to CREATED.

## 1.3.0+2
* Fix a minor update.

## 1.3.0+1
* Fix a ios player status listener.

## 1.3.0
* Initial release.
