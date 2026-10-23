# Shoplive SDK for Flutter

Flutter plugins and sample app for Shoplive SDK **3.0.3** (Android and iOS).

- Integration guide: https://developer.shoplive.cloud/mobile
- To use Shoplive, contact ask@shoplive.cloud.

## Packages

Shoplive for Flutter ships as three packages. All three wrap the same SDK release and must use the same version.

| Package | Folder | Provides | Native SDK |
|---|---|---|---|
| [`shoplive_core`](shoplive_core/README.md) | `shoplive_core/` | `Shoplive.initialize`, user, conversion events | Android `cloud.shoplive:shoplive-core` / iOS `ShopliveCore` |
| [`shoplive_player`](shoplive_flutter_sample/README.md) | `shoplive_flutter_sample/` | `ShoplivePlayer` live/VOD player (re-exports `shoplive_core`) | Android `cloud.shoplive:shoplive-player-sdk` / iOS `ShoplivePlayerSDK` |
| [`shoplive_streamer`](shoplive_streamer/README.md) | `shoplive_streamer/` | `ShopliveStreamer` broadcast (re-exports `shoplive_core`) | Android `cloud.shoplive:shoplive-streamer-sdk` / iOS `ShopliveStreamerSDK` |

Add only the package you need. An app that only plays videos adds `shoplive_player`, and the streamer binaries stay out of the app.

## Requirements

| | Minimum |
|---|---|
| Flutter / Dart | 3.22 / 3.4 |
| Android Gradle Plugin / Gradle | 8.7 / 8.9 |
| JDK | 17 |
| Android minSdk / compileSdk | 23 / 36 |
| iOS | 15.0 (Xcode with Swift 5.9 or later) |

## Installation

```yaml
dependencies:
  shoplive_player: 3.0.3     # player, includes shoplive_core
  # shoplive_streamer: 3.0.3 # broadcast, includes shoplive_core
```

Then do the platform setup:

- **Android:** The plugins add the Shoplive Maven repository (`https://sdk.shoplive.cloud/maven-repo`) for you. If your project declares the repository itself, follow "Android: Maven repository setup" in the package README.
- **iOS:** Set `platform :ios, '15.0'` in `ios/Podfile`. The plugins download the iOS SDK 3.0.3 XCFrameworks during `pod install` and verify each sha256. For proxy, mirror and offline CI options, see "iOS setup" in the package README.

## Quick start

```dart
import 'package:shoplive_player/shoplive_player.dart';

await Shoplive.initialize(const ShopliveConfiguration(accessKey: 'YOUR_ACCESS_KEY'));
await Shoplive.setUser(const ShopliveUser.guest());

final player = ShoplivePlayer.instance;
player.events.listen((event) { /* ShoplivePlayerEvent */ });
await player.start('CAMPAIGN_KEY');
```

For configuration, events, coupon and custom-action requests, PIP, error codes and known limitations, see the [`shoplive_player` README](shoplive_flutter_sample/README.md).

## Migrating from 1.x

3.x (since 3.0.2) is a rewrite. The 1.x Dart API, the Shortform API and `ShopLiveCommon` are removed. Class names change from `ShopLive*` to `Shoplive*`, and every method returns a `Future` that throws `PlatformException`.

- Use the migration table in the [`shoplive_player` README](shoplive_flutter_sample/README.md#migrating-from-1x).
- Run `flutter clean` once after you upgrade. Stale 1.x iOS build products otherwise cause "'ShoplivePlayerPlugin' has different definitions in different modules".

## Repository layout

| Path | Contents |
|---|---|
| `shoplive_core/` | `shoplive_core` plugin |
| `shoplive_flutter_sample/` | `shoplive_player` plugin |
| `shoplive_flutter_sample/example/` | Sample app for core, player and streamer, with iOS integration tests |
| `shoplive_streamer/` | `shoplive_streamer` plugin |
| `ios-tests/BridgeCoreTests/` | Swift package tests for the iOS bridge |

For local development, `pubspec_overrides.yaml` resolves `shoplive_core` from the sibling folder. Publish `shoplive_core` first, then `shoplive_player` and `shoplive_streamer`.

Releases are automated (GitHub Actions → **Release Flutter SDK**). Maintainers: see [RELEASING.md](RELEASING.md).

## Links

- Integration guide: https://developer.shoplive.cloud/mobile
- Android release notes: https://github.com/shoplive/shoplive-sdk-android/releases
- iOS release notes: https://github.com/shoplive/shoplive-sdk-ios/releases
- Contact: ask@shoplive.cloud
