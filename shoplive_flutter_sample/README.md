# shoplive_player

Fullscreen live/VOD player for Flutter, built on Shoplive Android SDK **3.0.3** (`cloud.shoplive:shoplive-player-sdk`).

Shoplive for Flutter ships as three packages:

| Package | Provides | Android dependency |
|---|---|---|
| `shoplive_core` | `Shoplive.initialize`, user, conversion events | `cloud.shoplive:shoplive-core` |
| `shoplive_player` | `ShoplivePlayer` (re-exports `shoplive_core`) | `cloud.shoplive:shoplive-player-sdk` |
| `shoplive_streamer` | `ShopliveStreamer` broadcast (re-exports `shoplive_core`) | `cloud.shoplive:shoplive-streamer-sdk` |

Apps that only play videos add `shoplive_player`, and streamer binaries stay out of the APK.

## Requirements

| | Minimum |
|---|---|
| Flutter / Dart | 3.22 / 3.4 |
| Android Gradle Plugin / Gradle | 8.7 / 8.9 |
| JDK | 17 |
| Android minSdk / compileSdk | 23 / 36 |
| iOS | 15.0 (Xcode with Swift 5.9 or later; set `platform :ios, '15.0'` in your Podfile) |

## Installation

```yaml
dependencies:
  shoplive_player: 3.0.3   # includes shoplive_core
```

> `shoplive_core`, `shoplive_player` and `shoplive_streamer` wrap the same SDK release and must use the same version. `shoplive_player` and `shoplive_streamer` pin `shoplive_core` to their own version. (Maintainers: publish `shoplive_core` first, then `shoplive_player` and `shoplive_streamer`.)

## Android: Maven repository setup

Shoplive Android SDK 3.x is served from `https://sdk.shoplive.cloud/maven-repo`.

**Why `cloud.shoplive` must come only from the Shoplive repository:** Shoplive Android SDK 3.0.3 is not published to Maven Central, so Gradle must find it in the Shoplive repository. The plugins pin the `cloud.shoplive` group to that repository with `exclusiveContent`, so an artifact with the same coordinates in another repository is never mixed in. (Up to 3.0.2, Maven Central hosted a conflicting `cloud.shoplive:shoplive-media3:1.10.1.2`; from 3.0.3 the player SDK depends on `androidx.media3` directly and no longer uses `shoplive-media3`.)

### (a) Default: automatic

The Shoplive plugins (`shoplive_core`, `shoplive_player`, `shoplive_streamer`) add the repository to `rootProject.allprojects` for you, using `exclusiveContent` for the `cloud.shoplive` group. Gradle fails to resolve a group that is declared `exclusiveContent` more than once. To avoid that, the first Shoplive plugin sets the root-project flag `shopliveMavenRepoConfigured` to `true` and the other plugins skip the declaration. The plugins check the flag's **value** (from `ext` or `gradle.properties`); only `true` counts. You do not need to add anything.

### (b) You declare the repository yourself (mirror/proxy, custom setup)

If your project declares the Shoplive repository itself, do both of the following:

1. Tell the plugins not to add their own declaration. Add this to `android/gradle.properties` (the value must be `true`; `false` or a missing value makes the plugins declare the repository again):

   ```properties
   shopliveMavenRepoConfigured=true
   ```

2. Declare the repository with `exclusiveContent` where your project declares repositories.

Groovy (`android/build.gradle`):

```groovy
allprojects {
    repositories {
        google()
        mavenCentral()
        exclusiveContent {
            forRepository { maven { url "https://sdk.shoplive.cloud/maven-repo" } }
            filter { includeGroup "cloud.shoplive" }
        }
    }
}
```

Kotlin DSL (`android/build.gradle.kts`):

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        exclusiveContent {
            forRepository { maven { url = uri("https://sdk.shoplive.cloud/maven-repo") } }
            filter { includeGroup("cloud.shoplive") }
        }
    }
}
```

If your build resolves dependencies from `settings.gradle(.kts)` `dependencyResolutionManagement` (repositories mode `PREFER_SETTINGS`), put the same `exclusiveContent` block there and still set the flag. We have not verified this mode with Flutter builds. In Flutter's default mode (`PREFER_PROJECT`), project repositories win.

## iOS setup

- **Minimum iOS 15.** Set `platform :ios, '15.0'` in `ios/Podfile`. Flutter's template uses a lower value, and `pod install` fails with "higher minimum deployment target" until you change it.
- **The Shoplive iOS SDK is downloaded during `pod install`.** The plugins fetch the SDK 3.0.3 XCFrameworks from the GitHub release `https://github.com/shoplive/shoplive-sdk-ios/releases/tag/3.0.3`. Every zip is checked against its sha256; if a checksum does not match, `pod install` stops and nothing unverified is linked. The frameworks are unpacked into the plugin's `ios/Frameworks/` folder and reused by later installs, so only the first install downloads. Anything that evaluates the podspec downloads too: `pod install`, `flutter build ios` / `flutter run` (which run `pod install`) and `pod spec lint`.
  - Network: the first install needs access to `github.com` and its download host. `curl` honours `HTTPS_PROXY`, `ALL_PROXY` and `NO_PROXY`.
  - Mirror: set `SHOPLIVE_IOS_SDK_BASE_URL` to a server that serves `<base>/3.0.3/<Name>.xcframework.zip`.
  - Offline / CI: set `SHOPLIVE_IOS_SDK_DIR` to a folder that contains the five release zips (`ShopliveCore`, `ShoplivePlayerSDK`, `ShopliveStreamerSDK`, `ShopLiveWebRTCHelperSDK`, `WebRTC` `.xcframework.zip`). To avoid downloading on every CI run, cache the pub cache (key it by SDK version).
  - The plugin folder must be writable, because the frameworks have to live inside it. With a read-only pub cache, point `PUB_CACHE` at a writable folder and run `flutter pub get` again.
- If you run `pod install` yourself, use a UTF-8 locale (`export LANG=en_US.UTF-8`); CocoaPods fails otherwise.
- **Upgrading from 1.x:** run `flutter clean` once. Stale 1.x build products otherwise cause "'ShoplivePlayerPlugin' has different definitions in different modules".

## Usage

```dart
import 'package:shoplive_player/shoplive_player.dart';

// 1. Initialize once, e.g. in main()
await Shoplive.initialize(const ShopliveConfiguration(accessKey: 'YOUR_ACCESS_KEY'));
await Shoplive.setUser(const ShopliveUser.guest());

final player = ShoplivePlayer.instance;

// 2. Subscribe while the player is in use
player.events.listen((event) {
  switch (event) {
    case ShoplivePlayerStateChanged(:final state): print('state: $state');
    case ShoplivePlayerErrorEvent(:final error): print('error: ${error.code}');
    default: break;
  }
});
player.navigationRequests.listen((r) => openProductPage(r.url));
player.couponRequests.listen((r) async {
  final delivered = await r.respond(const ShopliveCouponResult(
    success: true, status: ShopliveResultStatus.hide, message: 'Coupon issued', alertType: ShopliveResultAlertType.toast));
  if (!delivered) {
    // already answered by the timeout fallback, by another listener, or after detach
  }
});

// 3. Start (configuration is merged on top of the current settings)
await player.start('CAMPAIGN_KEY',
    configuration: const ShoplivePlayerConfiguration(sound: ShopliveSoundOptions(muteOnStart: true)));
await player.setMuted(false);   // NOT_RUNNING if no session is running
await player.close();           // always succeeds
```

### Configuration

- `start(configuration:)` and `setConfiguration` **merge** the given fields on top of the current settings. Omitted fields keep their values. `getConfiguration()` returns the full current configuration.
- Settings made before the first `start`, or across a screen recreation, are kept and applied to the next player instance.
- `presentationStyle: pip` requires `pip.isInAppPipEnabled: true` in the merged configuration. Otherwise `start` fails with `INVALID_ARGUMENT`.
- `pip.isDragOutToCloseEnabled` (SDK 3.0.3+, Android and iOS): whether the in-app PIP window closes when dragged off the screen. Omitted keeps the current value (the SDK default is `true` on both platforms).
- `configuration.android` holds Android-only options.

### Coupon and custom-action requests

- With no listener on `couponRequests` / `customWebActionRequests`, requests are answered at once with the fallback result: `success: false, status: keep, alertType: toast`.
- With a listener, the SDK waits for `respond` up to the timeout (default 10 s; `setRequestTimeout` accepts 1–120 s). After that the fallback is sent.
- `respond` is valid once per request. It returns `false` when the request was already answered: by timeout, by another listener, or after the plugin was detached.
- Keep request listeners subscribed for the whole session. When every request listener is removed, pending requests are answered with the fallback result.

### Android: picture-in-picture

- In-app PIP works with the default `FlutterActivity` host. The plugin registers the host Activity as the `ViewTreeLifecycleOwner` so that the SDK keeps the player alive when it moves into the host screen. Nothing to change in `MainActivity`.
- For system PIP when the app goes to the background, add `android:supportsPictureInPicture="true"` to your host Activity in `AndroidManifest.xml` (the default Flutter `configChanges` already cover what the SDK checks). Without it the player reports `PIP_ACTIVITY_NOT_DECLARED` and stays in in-app PIP only.
- With a plain `FlutterActivity` host, the SDK does not register its system-PIP mode listener (it only does so for androidx `ComponentActivity` hosts). In-app PIP works, but behavior that depends on system-PIP enter/exit callbacks may be missing. Use `FlutterFragmentActivity` if you rely on system PIP.
- Add-to-app: if the PIP return host is a native Activity (not the Flutter one), make it an androidx `ComponentActivity` (e.g. `AppCompatActivity`); the plugin only patches the Activity the Flutter engine is attached to.
- `shoplive_core` declares `androidx.constraintlayout:constraintlayout:2.2.1` to override the `2.0.1` that the SDK pulls in through `material`. If your app pins an older ConstraintLayout with `force`/`strictly`, in-app PIP layout fails.

## iOS differences

The Dart API and channel contract are the same on both platforms. The iOS SDK differs in a few places:

| Topic | iOS behavior |
|---|---|
| `start` | The plugin creates the SDK player view controller and presents it over the top-most screen. Calling `start` while a session is open (fullscreen or in-app PIP) switches the campaign in the same player instead of opening a second one |
| `configuration.type` | `preview` / `live` select the SDK `.preview` / `.default` configuration preset and set the SDK `type` (3.0.3), then the other fields are applied |
| Ignored on iOS | `configuration.android.*`, `pip.aspectRatio`, `setUser(profile.custom)` - accepted and ignored (no iOS SDK counterpart). `initialize(appVersion:)` is ignored on both platforms since SDK 3.0.3 |
| Not exposed yet | iOS-only SDK options: `sound.autoResumeOnCallEnded`, `pip.fixedWidth` / `floatingOffset` / `windowProvider`, `appearance.allowScreenCapture`, loading images, chat fonts, `attribution.advertisingId` - the SDK defaults apply |
| Events | `playback` `failed`: `code` / `message` are `null`. `error`: `rawCode` is the SDK raw code (always set since SDK 3.0.3, same as Android). Streamer `stateChanged.isRehearsal` is `null` (the iOS SDK has no rehearsal flag) |
| Coupon / custom-action respond | `alertType` defaults to `toast` when omitted, same as Android (the SDK 3.0.3 initializer default `.alert` is not used) |
| `indicatorColor` | ARGB as an unsigned 32-bit value (`0xFF00FF00`), same on Android |
| Removed 1.x iOS options | `setKeepAspectOnTabletPortrait`, preview close events and the close-button handlers have no 3.x counterpart (`setEnabledPipSwipeOut`: closest is `pip.isDragOutToCloseEnabled`, SDK 3.0.3). The 1.x sample app's `CLICK_BACK_BUTTON` workaround (switch to in-app PIP) was app code; with 3.x, handle such commands from `webCommandReceived` if your app still needs it |

## Errors

Every API returns a `Future` and fails with `PlatformException`. The codes are:

| `code` | Meaning |
|---|---|
| `INVALID_ARGUMENT` | Missing or blank required value, wrong type, unknown enum value, out-of-range value, or a value rejected by SDK validation |
| `NO_HOST_SCREEN` | No foreground screen to show the player or broadcast UI (Android: no Activity; iOS: no foreground window/root view controller) |
| `NOT_RUNNING` | A session command was sent while no player session is running |
| `SDK_ERROR` | The SDK call failed. `details` contains the exception class name and, when available, the SDK error code |

A method the platform does not implement fails with `MissingPluginException`. Event streams never throw on unexpected payloads. Unknown or malformed events arrive as `…UnknownEvent`, and unknown enum values map to `unknown`.

## Migrating from 1.x

3.x (since 3.0.2) is a rewrite. The 1.x Dart API (up to 1.8.14), the Shortform API and `ShopLiveCommon` have been removed. Rows marked 1.8.x cover APIs added in 1.7.1–1.8.14.

| 1.x | 3.x |
|---|---|
| `ShopLiveCommon.setAccessKey` / `setAuth(ShopLiveCommonAuth)` | `Shoplive.initialize(ShopliveConfiguration(accessKey: …, attribution: …))` |
| `ShopLiveCommon.setUtmSource/Medium/Campaign/Content` | `ShopliveConfiguration.attribution` (`ShopliveAttribution`) |
| `ShopLiveCommon.setAuthToken(jwt)` | `Shoplive.setUser(ShopliveUser.token(jwt))` |
| `ShopLiveCommon.setUser(ShopLiveCommonUser)` | `Shoplive.setUser(ShopliveUser.profile(id: …))`. `id` is required |
| guest (`guestUid`) | `Shoplive.setUser(const ShopliveUser.guest())` |
| `ShopLiveCommon.clearAuth` | `Shoplive.logout()` |
| `ShopLivePlayer.play(ShopLivePlayerData)` | `ShoplivePlayer.instance.start(campaignKey, playOptions: …, configuration: …)`. Use `play` to switch campaigns while running |
| `showPreview(ShopLivePlayerPreviewData)` (≤1.7) / `showPreview(campaignKey)` + `setPreviewOption(...)` (1.8.x) | `start(campaignKey, playOptions: ShoplivePlayOptions(presentationStyle: ShoplivePresentationStyle.pip), configuration: ShoplivePlayerConfiguration(type: ShoplivePlayerType.preview, pip: ShoplivePipOptions(isInAppPipEnabled: true)))`. Preview UI details depend on SDK 3.x; check them on a device |
| Share handling (the 1.x Android bridge overrode `handleShare` and ran the SDK default share after 100 ms) | No share handler in SDK 3.x. Set `configuration.navigation.shareScheme` |
| `setShareScheme` | `configuration.navigation.shareScheme` |
| `setNextActionOnHandleNavigation` | `configuration.navigation.actionOnNavigation` |
| `setEnterPipModeOnBackPressed` | `configuration.android.enterOSPipOnBackPressed` |
| `setMuteWhenPlayStart` | `configuration.sound.muteOnStart` |
| `setMixWithOthers` | `configuration.sound.mixWithOthers` |
| `addParameter` / `removeParameter` | `configuration.customParameters`. The map is replaced as a whole |
| `startPictureInPicture` / `stopPictureInPicture` | `enterPictureInPicture` / `exitPictureInPicture` |
| `sendCommandMessage` | `send(command, payload)` |
| `useCloseButton`, `setEndpoint`, tablet aspect ratio, transparent status bar | No equivalent in SDK 3.x |
| 1.8.x `setPreviewOption` margins / `position` | `configuration.pip.padding` (`ShopliveInsets`) / `configuration.pip.defaultPosition` (`ShoplivePipPosition`) |
| 1.8.x `setPreviewOption` `pipRadius`, `enableSwipeOut`, `pipMaxSize` | `enableSwipeOut`: closest is `configuration.pip.isDragOutToCloseEnabled` (SDK 3.0.3, check on a device). `pipRadius`, `pipMaxSize`: no equivalent (closest: `pip.scale`, `pip.aspectRatio`) |
| 1.8.x `closeButtonConfig` (`ShopLiveCloseButtonConfig`) | No equivalent in SDK 3.x |
| 1.8.x `hidePreview()` | No separate API. `close()` ends the session (whether it matches 1.8.x hide-only behavior is unverified) |
| 1.8.x `previewClose` stream and its `reason` (`close_button`, `swipe_out`, `broadcast_ended`, `programmatic`) | No equivalent event. `stateChanged(closed)` tells that it closed, `campaignStatusChanged(ended)` that the broadcast ended; the close reason is not available |
| 1.8.x `setResizeMode(auto / centerCrop / fit)` | `setResizeMode(ShopliveResizeMode.fill / fit)`. `auto` and `centerCrop` do not exist in SDK 3.x; `centerCrop` users should try `fill` (closest, check on a device) |
| 1.8.x `sendDownloadCouponResult` / `sendCustomActionResult` | `couponRequests` / `customWebActionRequests` and `request.respond(...)` |
| 1.8.x `getSdkVersion()` | `Shoplive.getSdkVersion()` |
| 1.8.x `getPluginVersion()` | `ShoplivePlayer.instance.getPluginVersion()` (or `ShoplivePlayer.pluginVersion`) |
| `ShopLiveActionType` `show` / `hide` / `keep` (≤1.7: sent as 0/1/2 and matched to the SDK's `PIP`/`KEEP`/`CLOSE` order on Android) | `configuration.navigation.actionOnNavigation`: `show` → `ShopliveNavigationAction.pip`, `hide` → `.keep`, `keep` → `.close` (the actual Android 1.x behavior). In 1.8.x the Android bridge always fell back to `pip`. iOS 1.x mapping is unverified |
| 10 event streams (`handleNavigation`, `handleDownloadCoupon`, `changeCampaignStatus`, `campaignInfo`, `handleCustomAction`, `changedPlayerStatus`, `userInfo`, `error`, `receivedCommand`, `log`) | `events` (sealed `ShoplivePlayerEvent`) plus `navigationRequests`, `couponRequests` and `customWebActionRequests` |
| `log` stream | No confirmed equivalent. `webCommandReceived` / `analytics` may cover some uses (unverified) |
| `ShopLive*` class names | `Shoplive*` |
| Methods returning `void` (errors were swallowed) | Methods return a `Future` and throw `PlatformException` |
| Shortform (`shoplive_shortform.dart`) | Removed |

## Known limitations

- **iOS: deferred presentation reports success early.** If `start` is called while another screen transition is running, the player is presented when that transition ends; `start` has already returned success, so a later presentation failure is not reported (only logged).
- **Nullable settings cannot be reset from Dart.** `navigation.shareScheme` and `android.isVolumeKeyEnabled` cannot be set back to `null`: an omitted field keeps its current value.
- **Sessions do not survive an engine restart.** After the Flutter engine is detached and attached again (add-to-app, multiple engines), the new plugin instance cannot control or observe a session that the previous engine left open (for example with `closeWhenAppDestroyed: false`). Requests from that session are answered with the fallback result.
- **Only synchronous listener errors are handled.** If a request listener throws synchronously, that request is answered with the fallback result immediately. Errors thrown after an `await` in an async listener are not caught. If you never respond, the request falls back when the timeout expires.
- **Silent SDK rejections cannot be detected.** If the launch Activity is gone or is not a `LifecycleOwner`, the SDK rejects `start` with a log message only. `start` still completes successfully.
- Calling `Shoplive.initialize` more than once (hot restart, multiple engines) behaves however the SDK does. The bridge does not guard it.

## Links

- Android release notes: https://github.com/shoplive/shoplive-sdk-android/releases
- iOS release notes: https://github.com/shoplive/shoplive-sdk-ios/releases
- Contact: ask@shoplive.cloud
