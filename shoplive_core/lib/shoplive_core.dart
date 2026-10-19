/// Shoplive 공통(core) Flutter 플러그인 — Android SDK 3.0.3 `cloud.shoplive:shoplive-core`.
///
/// 채널 계약: design.md rev2 §2.4 (DRAFT-flutter-sdk-302-android).
/// 공개 API만 export한다. `src/wire_enum.dart`와 MethodChannel 구현은 내부용이다
/// (shoplive_player·shoplive_streamer가 `package:shoplive_core/src/...`로 import — 공개 API 아님).
library shoplive_core;

export 'src/models/configuration.dart' show ShopliveConfiguration, ShopliveAttribution;
export 'src/models/conversion.dart' show ShopliveConversionData, ShopliveConversionProduct;
export 'src/models/user.dart'
    show ShopliveUser, ShopliveGuestUser, ShopliveTokenUser, ShopliveProfileUser, ShopliveGender;
export 'src/platform/shoplive_core_platform_interface.dart' show ShopliveCorePlatform;
export 'src/shoplive.dart' show Shoplive;
export 'src/shoplive_error.dart' show ShopliveError, ShoplivePlatformErrorCode;
