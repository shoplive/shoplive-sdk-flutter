/// Shoplive 방송(streamer) Flutter 플러그인 — Android SDK 3.0.3 `cloud.shoplive:shoplive-streamer-sdk`.
///
/// 채널 계약: design.md rev2 §2.4·§2.5 (DRAFT-flutter-sdk-302-android). shoplive_core API를 함께 export한다.
library shoplive_streamer;

export 'package:shoplive_core/shoplive_core.dart';

export 'src/platform/shoplive_streamer_method_channel.dart' show ShopliveStreamerContract;
export 'src/platform/shoplive_streamer_platform_interface.dart' show ShopliveStreamerPlatform;
export 'src/shoplive_streamer.dart';
