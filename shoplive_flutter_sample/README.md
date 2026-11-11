# shoplive_player

Fullscreen live/VOD player for Flutter, built on Shoplive Android SDK **3.0.6** (`cloud.shoplive:shoplive-player-sdk`) and iOS SDK **3.0.5** (`ShoplivePlayerSDK`).

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

**Why `cloud.shoplive` must come only from the Shoplive repository:** Shoplive Android SDK 3.0.6 is not published to Maven Central, so Gradle must find it in the Shoplive repository. The plugins pin the `cloud.shoplive` group to that repository with `exclusiveContent`, so an artifact with the same coordinates in another repository is never mixed in. (Up to 3.0.2, Maven Central hosted a conflicting `cloud.shoplive:shoplive-media3:1.10.1.2`; from 3.0.3 the player SDK depends on `androidx.media3` directly and no longer uses `shoplive-media3`.)

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
- **The Shoplive iOS SDK is downloaded during `pod install`.** The plugins fetch the SDK 3.0.5 XCFrameworks from the GitHub release `https://github.com/shoplive/shoplive-sdk-ios/releases/tag/3.0.5`. Every zip is checked against its sha256; if a checksum does not match, `pod install` stops and nothing unverified is linked. The frameworks are unpacked into the plugin's `ios/Frameworks/` folder and reused by later installs, so only the first install downloads. Anything that evaluates the podspec downloads too: `pod install`, `flutter build ios` / `flutter run` (which run `pod install`) and `pod spec lint`.
  - Network: the first install needs access to `github.com` and its download host. `curl` honours `HTTPS_PROXY`, `ALL_PROXY` and `NO_PROXY`.
  - Mirror: set `SHOPLIVE_IOS_SDK_BASE_URL` to a server that serves `<base>/3.0.5/<Name>.xcframework.zip`.
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
    case ShoplivePlayerStateChanged(:final state, :final closeReason): print('state: $state reason: $closeReason');
    case ShoplivePlayerShareRequested(:final info): openShareSheet(info.url, info.title); // only with isCustomShareEnabled
    case ShoplivePlayerErrorEvent(:final error): print('error: ${error.code}');
    default: break; // without a default, every ShoplivePlayerEvent subtype must be listed
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

- `start(configuration:)` and `setConfiguration` **merge** the given fields on top of the current settings. Omitted fields keep their values. `getConfiguration()` returns the full configuration that the next `start` uses, except `overlay.ui`: a later `setOverlayUI` overrides it on the next `start`, so read that value with `getOverlayUI()`. A change made while a session is running reaches that session at a time that depends on the field. Android (SDK 3.0.6) applies `pip`, `sound.mixWithOthers`, `appearance`, `navigation` and the `android.*` options at once, and `sound.muteOnStart`, `overlay.ui` and `customParameters` from the next `start`, `play` or `reload`. iOS (SDK 3.0.5) applies `navigation.shareScheme`, `overlay.ui` and `sound.muteOnStart` at once and the other fields from the next `start`, `play` or `reload`. `type` applies from the next `start` on both platforms. A running player keeps the values you set with `setResizeMode` / `setOverlayUI` when you call `setConfiguration`.
- Settings made before the first `start`, or across a screen recreation, are kept and applied to the next player instance.
- Every `start` opens a new player session with the merged configuration. If a session is open (fullscreen or in-app PIP), it is closed first; its `closed` event is not delivered, and the new session's events follow. If the previous session was closed and the new one then fails to start, one `closed` state is sent instead. If the start fails before that (invalid argument, no host screen), the running session is left as it is. To switch campaigns inside the running session, use `play`; it keeps the session and uses the current settings. Android: a new `start` also closes other Shoplive player sessions in the app (a native player, or the player of another Flutter engine); those get `closed` with `appRequest`.
- `presentationStyle: pip` requires `pip.isInAppPipEnabled: true` in the merged configuration. Otherwise `start` fails with `INVALID_ARGUMENT`.
- `pip.isInAppPipEnabled` allows PIP requested while the app is in use (PIP button, back button, product navigation, `enterPictureInPicture()`, `startPreview`). `pip.isOSPipEnabled` allows PIP when the user leaves the app (home or recent apps). One does not turn the other off. On Android (SDK 3.0.5+), PIP from the fullscreen player and from an embedded player is the system PIP window.
- `android.backPressEntersPip` (Android only, SDK 3.0.6; the deprecated `enterOSPipOnBackPressed` reads and writes the same value): the system back button enters PIP only when it and `pip.isInAppPipEnabled` are both `true`. Otherwise back closes the session (`closed` with `userAction`). The default is `false`. iOS ignores it.
- `setResizeMode(ShopliveResizeMode.auto)` is the Android default since SDK 3.0.6: Android picks `fill` on phones and `fit` on tablets and unfolded foldables, and decides again when a foldable folds or unfolds. An explicit `fill` now stays `fill` on tablets too, and the system PIP window always uses `fill`. iOS has no such mode: `auto` is applied as `fill` and `getResizeMode()` returns `fill`.
- `pip.isDragOutToCloseEnabled` (SDK 3.0.3+, Android and iOS): whether the in-app PIP window closes when dragged off the screen. Omitted keeps the current value (the SDK default is `true` on both platforms).
- `configuration.android` holds Android-only options.

### Close reason

When the current session closes, `ShoplivePlayerStateChanged.state` is `closed` and `closeReason` tells why (SDK 3.0.4+, Android and iOS). For other states `closeReason` is `null`. `ShoplivePlayerState` itself is unchanged, so existing `state == ShoplivePlayerState.closed` checks keep working.

| `closeReason` | When |
|---|---|
| `userAction` | The viewer closed it (close button, dragging the in-app PIP window off the screen, system PIP close, back — on Android unless `android.backPressEntersPip` is on) |
| `appRequest` | Your app or the SDK closed it (`stop`, `close`, the stop inside `reload`, replacement by another broadcast, SDK internal stop). Also the `closed` the plugin sends when a replacing `start` fails |
| `accessKeyChanged` | `Shoplive.initialize` was called with a different access key; the player started with the old key closed. Start it again if needed (Android: `ShopliveUser.token` users call `setUser` again) |
| `unknown` | A reason this plugin version does not know |

```dart
player.events.listen((event) {
  if (event case ShoplivePlayerStateChanged(state: ShoplivePlayerState.closed, :final closeReason)) {
    if (closeReason == ShopliveCloseReason.accessKeyChanged) restartPlayerForNewKey();
  }
});
```

- `getState()` returns `closed` without a reason; use the event.
- When `start` replaces a session, the previous session's `closed` is not delivered (same as 3.0.3).
- `Shoplive.initialize` (core) and the player `closed` event use different channels, so their order in Dart is not guaranteed. Rely on `stateChanged`.

### Custom share

Set `navigation.isCustomShareEnabled: true` to handle sharing in your app (SDK 3.0.4+, Android and iOS). Tapping share in the player then does not open the SDK share sheet; `events` delivers one `ShoplivePlayerShareRequested` per share request instead. `false` or omitted keeps the SDK sheet.

```dart
await player.start('CAMPAIGN_KEY',
    configuration: const ShoplivePlayerConfiguration(navigation: ShopliveNavigationOptions(isCustomShareEnabled: true)));

player.events.listen((event) {
  if (event case ShoplivePlayerShareRequested(:final info)) {
    final url = info.url;            // shareScheme, otherwise the web share URL; null if neither exists
    if (url == null) return;         // share without a link, or ignore
    showMyShareSheet(url, subject: info.title);   // also: campaignKey, descriptionText, thumbnailUrl (all nullable)
  }
});
```

- **Keep a listener on `events` while the setting is on.** Without one, tapping share does nothing (the SDK sheet does not open either) and only a warning is logged. On Android, the next time the user leaves the app afterwards, system PIP is skipped once.
- `url` is `null` when there is no link; Android also sends an `error` event (`NOT_INITIALIZED_SHARE_URL`) in that case. iOS gives `null` for a value it cannot parse as a URL.
- Android: the fullscreen player runs in its own task. A share screen opened from the Flutter host Activity may, when closed, bring your app screen to the front instead of the broadcast. Switch to in-app PIP (`enterPictureInPicture()`) before opening it.
- iOS: the player is presented over the Flutter screen. Present your share sheet from the top-most view controller.
- A change while playing applies at once on Android and from the next `start`, `play` or `reload` on iOS.

### In-app PIP buttons

`pip.closeButton` and `pip.restoreButton` take `ShopliveButtonOptions` (SDK 3.0.4+, Android and iOS; not applied to the system PIP window).

```dart
await player.setConfiguration(const ShoplivePlayerConfiguration(
  pip: ShoplivePipOptions(
    closeButton: ShopliveButtonOptions(nativeImageName: 'pip_close'),   // Android res/drawable/pip_close.xml, iOS Assets.xcassets "pip_close"
    restoreButton: ShopliveButtonOptions(isHidden: true),
  ),
));
```

- `isHidden: true` hides the button; it wins over the image. A hidden restore button means tapping the PIP window restores it. If you hide the close button and also set `isDragOutToCloseEnabled: false`, the viewer has no way to close the PIP window.
- `nativeImageName` is the name of an image **in your app's native resources**: an Android drawable resource name (`res/drawable/<name>`) or an iOS Asset Catalog image name. It is **not** a Flutter asset path. The button frame is 28 dp on Android and 24 pt on iOS; use a vector (Android vector drawable, iOS PDF/SVG) or an image of that size. Android drawables must not use theme attributes (`?attr/...`).
- A name that cannot be resolved, or `''`, does not fail `start` / `setConfiguration`: a warning is logged and that button is drawn as if no image was set: the SDK uses the server PIP asset, otherwise the SDK default close icon for the close button and no button at all for the restore button. If neither button has an image, the PIP looks as in 3.0.3. On Android, if the other button's image resolves, the SDK switches to the new layout for both buttons; iOS has no layout change.
- Android release builds with resource shrinking may remove drawables that only Dart refers to by name. Keep them in `res/raw/keep.xml`:

  ```xml
  <resources xmlns:tools="http://schemas.android.com/tools"
      tools:keep="@drawable/pip_close,@drawable/pip_restore" />
  ```

- `nativeImageName` is write-only: `getConfiguration()` returns only `isHidden` (`nativeImageName` is always `null`). Because omitted fields keep their values, passing the result of `getConfiguration()` back keeps the images.
- An image cannot be removed by passing `null` (omitted keeps the current value). Pass `''` to go back to no image (a warning is logged).

### Coupon and custom-action requests

- With no listener on `couponRequests` / `customWebActionRequests`, requests are answered at once with the fallback result: `success: false, status: keep, alertType: toast`.
- With a listener, the SDK waits for `respond` up to the timeout (default 10 s; `setRequestTimeout` accepts 1–120 s). After that the fallback is sent.
- `respond` is valid once per request. It returns `false` when the request was already answered: by timeout, by another listener, or after the plugin was detached.
- Keep request listeners subscribed for the whole session. When every request listener is removed, pending requests are answered with the fallback result.

### Preview

`startPreview(campaignKey)` opens a small muted preview window (in-app PIP) in one call. When the viewer expands it to fullscreen, the sound turns on.

```dart
await player.startPreview('CAMPAIGN_KEY');
```

- If a viewing session is showing (a player opened with `start`, or a preview the viewer expanded), nothing happens. If a preview with the same key is showing, it is kept (a stopped preview, or one without a window, starts again). Another key switches the preview to that campaign. `play(key)` in fullscreen turns a preview into a viewing session.
- Errors known when you call it end the `Future`: a blank key `INVALID_ARGUMENT`, no host screen `NO_HOST_SCREEN`, and on Android `SDK_ERROR` when the SDK did not start a preview (not initialized, or the window could not open; the SDK does not say which). A refused restart of a showing preview (Android) and errors after the start arrive as `error` events. Call it after `Shoplive.initialize`: on iOS an earlier call may not report an error at all (see Known limitations).
- The preview uses the SDK preview presets only. Values saved with `setConfiguration`, `setResizeMode` and `setOverlayUI` stay for the next `start`. A `setConfiguration` while the preview runs is merged on top of the preview's own settings, and its `type` is not changed.
- Android sends one `stateChanged` with the preview's current state right after the call, because the SDK reports the first states before the plugin can listen. iOS reports them as they happen.
- Android uses the SDK `ShoplivePlayer.startPreview` rules as they are. iOS SDK 3.0.5 has no such call, so the plugin emulates it with the SDK preview presets. The differences:
  - Another key closes the showing preview and opens a new one: the window comes back at its default position and you get `loading` → `inAppPip` again (no `closed` for the previous preview). Android keeps the window.
  - After `stop()` the iOS player is no longer running, so the next `startPreview` opens a new preview (a stopped player still on screen is closed first). Android ignores the call while the stopped window is still on screen.
  - iOS looks only at the player this plugin opened. Android also counts players opened by native code or another Flutter engine.
  - After the viewer expanded a preview, a later `play(key, playOptions: ShoplivePlayOptions(presentationStyle: ShoplivePresentationStyle.pip))` stays a viewing session on iOS (the next `startPreview` is ignored). On Android that `play` makes it a preview again.
  - A `play` with the same key and `keepWindowStateOnPlayExecuted: true` keeps the current form on iOS even in fullscreen. Android keeps it only while the preview is floating; in fullscreen it opens the in-app PIP the `presentationStyle` asks for.

### Campaign list

`ShoplivePlayerAPI.getCampaigns` returns the campaigns of the access key set with `Shoplive.initialize` (Android and iOS).

```dart
final token = ShopliveCancelToken();
try {
  final page = await ShoplivePlayerAPI.getCampaigns(
    request: const ShopliveCampaignListRequest(statuses: [ShopliveCampaignListStatus.onAir], size: 20),
    cancelToken: token,
  ).timeout(const Duration(seconds: 15), onTimeout: () {
    token.cancel(); // cancels the native request
    throw TimeoutException('getCampaigns');
  });
  for (final c in page.campaigns) {
    // c.campaignKey, c.title, c.scheduledAt (UTC), c.lifecycle.status, c.metrics
  }
} on PlatformException catch (e) {
  if (e.code == ShoplivePlatformErrorCode.cancelled) return;
  final error = ShopliveError.tryParse(e.details); // SDK_ERROR: tell causes apart by error?.rawCode
}
```

- `page` below 1 and `size` outside 1–20 are corrected by the SDK, not rejected. `page` and `size` must fit in 32 bits.
- Times are UTC `DateTime`s. `lifecycle.status` is `ShopliveCampaignLifecycleReserved`, `Ready`, `OnAir` or `Closed`, or `ShopliveCampaignLifecycleUnknown` with the server text for a status this version does not know. `metrics` is set only for on-air and closed campaigns; when `showUserCount` is `false`, do not show the counts.
- Each call ends exactly once: the response, `SDK_ERROR` (the SDK error is in `details`; `rawCode` -200 unknown key, -201 expired key, -510 invalid argument, 9000 not initialized, 9900 network, 9901 parsing), `CANCELLED`, or `INVALID_ARGUMENT`.
- Calls are independent and may complete in any order. Use the result of your latest request.
- A cancelled token stays cancelled: a new call with it ends with `CANCELLED` at once. One token can cancel several calls.
- The plugin sets no wait limit. The native HTTP limits apply (Android: 30 s for the whole call; iOS: 10 s without data). If the native side never answers, the `Future` may not complete, so add `Future.timeout` with the cancel token as above.

### Android: picture-in-picture

- In-app PIP works with the default `FlutterActivity` host. The plugin registers the host Activity as the `ViewTreeLifecycleOwner` so that the SDK keeps the player alive when it moves into the host screen. Nothing to change in `MainActivity`.
- For system PIP when the app goes to the background, add `android:supportsPictureInPicture="true"` to your host Activity in `AndroidManifest.xml` (the default Flutter `configChanges` already cover what the SDK checks). Without it the player reports `PIP_ACTIVITY_NOT_DECLARED` and stays in in-app PIP only.
- If the user turned off picture-in-picture for your app in the system settings, every fullscreen PIP request (PIP button, back with `backPressEntersPip`, `enterPictureInPicture()`) sends an `error` event with `code` `PIP_DISABLED_BY_USER` (`rawCode` 9511), and the screen does not change (SDK 3.0.6). An embedded player reports `PIP_ENTER_FAILED` (9514) instead.
- With a plain `FlutterActivity` host, the SDK does not register its system-PIP mode listener (it only does so for androidx `ComponentActivity` hosts). In-app PIP works, but behavior that depends on system-PIP enter/exit callbacks may be missing. Use `FlutterFragmentActivity` if you rely on system PIP.
- Add-to-app: if the PIP return host is a native Activity (not the Flutter one), make it an androidx `ComponentActivity` (e.g. `AppCompatActivity`); the plugin only patches the Activity the Flutter engine is attached to.
- `shoplive_core` declares `androidx.constraintlayout:constraintlayout:2.2.1` to override the `2.0.1` that the SDK pulls in through `material`. If your app pins an older ConstraintLayout with `force`/`strictly`, in-app PIP layout fails.

## iOS differences

The Dart API and channel contract are the same on both platforms. The iOS SDK differs in a few places:

| Topic | iOS behavior |
|---|---|
| `start` | The plugin creates the SDK player view controller and presents it over the top-most screen. Calling `start` while a session is open (fullscreen or in-app PIP) closes it and presents a new player, as on Android |
| `configuration.type` | `preview` / `live` select the SDK `.preview` / `.default` configuration preset and set the SDK `type` (3.0.3), then the other fields are applied. Changing `type` resets the fields you do not pass in the same call to the preset, including `navigation.isCustomShareEnabled` and the PIP buttons (Android keeps them). A change while a session is running applies from the next `start` (3.0.3 applied it from the next `play` or `reload`) |
| `setResizeMode(auto)` | Applied as `fill` (the iOS SDK has no window-size mode). `getResizeMode()` returns `fill` |
| `startPreview` | Emulated by the plugin with the SDK preview presets. See "Preview" for the differences |
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
| `SDK_ERROR` | The SDK call failed. `details` contains the exception class name and, when available, the SDK error code. For `getCampaigns`, `details` is the SDK error (`code`, `message`, `rawCode`, `recoverable`): read it with `ShopliveError.tryParse(e.details)` |
| `CANCELLED` | A `ShoplivePlayerAPI.getCampaigns` call was cancelled with its `ShopliveCancelToken` |

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
| `showPreview(ShopLivePlayerPreviewData)` (≤1.7) / `showPreview(campaignKey)` + `setPreviewOption(...)` (1.8.x) | `startPreview(campaignKey)` (since 3.0.4; see "Preview"). For your own preview settings: `start(campaignKey, playOptions: ShoplivePlayOptions(presentationStyle: ShoplivePresentationStyle.pip), configuration: ShoplivePlayerConfiguration(type: ShoplivePlayerType.preview, pip: ShoplivePipOptions(isInAppPipEnabled: true)))`. Preview UI details depend on SDK 3.x; check them on a device |
| Share handling (the 1.x Android bridge overrode `handleShare` and ran the SDK default share after 100 ms) | `configuration.navigation.shareScheme` for the link; since 3.0.4, `navigation.isCustomShareEnabled` + `ShoplivePlayerShareRequested` to show your own share screen |
| `setShareScheme` | `configuration.navigation.shareScheme` |
| `setNextActionOnHandleNavigation` | `configuration.navigation.actionOnNavigation` |
| `setEnterPipModeOnBackPressed` | `configuration.android.backPressEntersPip` (Android; back enters PIP only when `pip.isInAppPipEnabled` is also `true`) |
| `setMuteWhenPlayStart` | `configuration.sound.muteOnStart` |
| `setMixWithOthers` | `configuration.sound.mixWithOthers` |
| `addParameter` / `removeParameter` | `configuration.customParameters`. The map is replaced as a whole |
| `startPictureInPicture` / `stopPictureInPicture` | `enterPictureInPicture` / `exitPictureInPicture` |
| `sendCommandMessage` | `send(command, payload)` |
| `useCloseButton`, `setEndpoint`, tablet aspect ratio, transparent status bar | No equivalent in SDK 3.x |
| 1.8.x `setPreviewOption` margins / `position` | `configuration.pip.padding` (`ShopliveInsets`) / `configuration.pip.defaultPosition` (`ShoplivePipPosition`) |
| 1.8.x `setPreviewOption` `pipRadius`, `enableSwipeOut`, `pipMaxSize` | `enableSwipeOut`: closest is `configuration.pip.isDragOutToCloseEnabled` (SDK 3.0.3, check on a device). `pipRadius`, `pipMaxSize`: no equivalent (closest: `pip.scale`, `pip.aspectRatio`) |
| 1.8.x `closeButtonConfig` (`ShopLiveCloseButtonConfig`) | Since 3.0.4: `configuration.pip.closeButton` (`ShopliveButtonOptions`: hide it or use an app image) for the in-app PIP window |
| 1.8.x `hidePreview()` | No separate API. `close()` ends the session (whether it matches 1.8.x hide-only behavior is unverified) |
| 1.8.x `previewClose` stream and its `reason` (`close_button`, `swipe_out`, `broadcast_ended`, `programmatic`) | No equivalent event. `stateChanged(closed)` tells that it closed, `campaignStatusChanged(ended)` that the broadcast ended; since 3.0.4 `closeReason` tells why (`userAction`, `appRequest`, `accessKeyChanged`) |
| 1.8.x `setResizeMode(auto / centerCrop / fit)` | `setResizeMode(ShopliveResizeMode.fill / fit)`. The 3.0.4 `ShopliveResizeMode.auto` is not the 1.8.x `auto` (server aspect): it picks `fill` or `fit` by window size on Android and is `fill` on iOS. 1.8.x `auto` and `centerCrop` users should try `fill` (closest, check on a device) |
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

- **`reload()` sends `closed` before it plays again.** On both platforms you get `stateChanged(closed)` with `appRequest`, then `loading` and `playing`, and the session goes on. Do not treat that `closed` as the end of the session. (iOS: checked on the simulator, device check pending.)
- **`getCampaigns` has no plugin wait limit.** The native HTTP limits apply (Android 30 s per call, iOS 10 s without data), but if the native side never answers, the `Future` may not complete. Use `Future.timeout` and `ShopliveCancelToken.cancel()` (see "Campaign list").
- **iOS: `startPreview` before `Shoplive.initialize` is not reported as an error.** Without an access key the preview may open, then end with `closed` (`userAction`), and no `error` event arrives (iOS SDK 3.0.5 behavior, seen on the simulator). Call `startPreview` after `initialize` has completed.
- **Android: `startPreview` may end with `SDK_ERROR` although the SDK only ignored the call.** If a viewing window that the SDK cannot link to a player is showing, the SDK returns a player that did not start, and the plugin cannot tell this from a failed start.
- **Custom share needs a listener.** With `isCustomShareEnabled: true` and no listener on `events`, tapping share does nothing (only a warning is logged); on Android the next exit from the app skips system PIP once.
- **Android: share screen and the fullscreen task.** A share screen opened from the Flutter host Activity may bring your app to the front instead of the broadcast when it closes. Switch to in-app PIP before opening it.
- **iOS: changing `configuration.type` resets new fields.** `isCustomShareEnabled` and the PIP buttons return to the preset unless you pass them in the same call (Android keeps them).
- **iOS: deferred presentation reports success early.** If `start` is called while another screen transition is running, the player is presented when that transition ends; `start` has already returned success, so a later presentation failure is not reported (only logged).
- **Nullable settings cannot be reset from Dart.** `navigation.shareScheme` and `android.isVolumeKeyEnabled` cannot be set back to `null`: an omitted field keeps its current value. For PIP button images, pass `nativeImageName: ''` (logs a warning) to go back to no image.
- **Sessions do not survive an engine restart.** After the Flutter engine is detached and attached again (add-to-app, multiple engines), the new plugin instance cannot control or observe a session that the previous engine left open (for example with `closeWhenAppDestroyed: false`). Requests from that session are answered with the fallback result.
- **Only synchronous listener errors are handled.** If a request listener throws synchronously, that request is answered with the fallback result immediately. Errors thrown after an `await` in an async listener are not caught. If you never respond, the request falls back when the timeout expires.
- **Silent SDK rejections cannot be detected.** If the launch Activity is gone or is not a `LifecycleOwner`, the SDK rejects `start` with a log message only. `start` still completes successfully.
- Calling `Shoplive.initialize` more than once (hot restart, multiple engines) behaves however the SDK does. The bridge does not guard it.

## Links

- Android release notes: https://github.com/shoplive/shoplive-sdk-android/releases
- iOS release notes: https://github.com/shoplive/shoplive-sdk-ios/releases
- Contact: ask@shoplive.cloud
