# shoplive_core

Shared Shoplive API for Flutter, built on Shoplive Android SDK **3.0.3** (`cloud.shoplive:shoplive-core`): initialization, user, and conversion events.
It is re-exported by `shoplive_player` and `shoplive_streamer`. Add it directly only if you use neither.

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
  shoplive_core: 3.0.3
```

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
import 'package:shoplive_core/shoplive_core.dart';

await Shoplive.initialize(const ShopliveConfiguration(
  accessKey: 'YOUR_ACCESS_KEY',
  attribution: ShopliveAttribution(utmSource: 'app'),
));
await Shoplive.setUser(const ShopliveUser.profile(id: 'user-1', name: 'Jane', gender: ShopliveGender.female));
await Shoplive.sendConversionEvent(const ShopliveConversionData(
  type: 'purchase',
  orderId: 'order-1',
  products: [ShopliveConversionProduct(productId: 'p1', purchaseQuantity: 1, purchaseUnitPrice: 9900)],
));
await Shoplive.logout();
```

- Required strings (`accessKey`, profile `id`, `jwt`, stream token) must not be blank.
- The bridge does not track initialization state. Calls made before `initialize` behave however the SDK does.
- `package:shoplive_core/shoplive_core_bridge.dart` is for internal use by the Shoplive packages only. It is not a supported API.

## Errors

Every API returns a `Future` and fails with `PlatformException`. The codes are:

| `code` | Meaning |
|---|---|
| `INVALID_ARGUMENT` | Missing or blank required value, wrong type, unknown enum value, out-of-range value, or a value rejected by SDK validation |
| `NO_HOST_SCREEN` | No foreground screen to show the player or broadcast UI (Android: no Activity; iOS: no foreground window/root view controller) |
| `NOT_RUNNING` | A session command was sent while no player session is running |
| `SDK_ERROR` | The SDK call failed. `details` contains the exception class name and, when available, the SDK error code |

A method the platform does not implement fails with `MissingPluginException`. Event streams never throw on unexpected payloads. Unknown or malformed events arrive as `…UnknownEvent`, and unknown enum values map to `unknown`.

## Migration from 1.x

`ShopLiveCommon` is replaced by `Shoplive` (`initialize` / `setUser` / `logout`). See the `shoplive_player` README for the full table.

## Known limitations

- Calling `Shoplive.initialize` more than once (hot restart, multiple engines) behaves however the SDK does. The bridge does not guard it.
