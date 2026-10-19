/// Shoplive 플레이어(player) Flutter 플러그인 — Android SDK 3.0.3 `cloud.shoplive:shoplive-player-sdk`.
///
/// 채널 계약: design.md rev2 §2.4·§2.5·§2.7 (DRAFT-flutter-sdk-302-android). shoplive_core API를 함께 export한다.
library shoplive_player;

export 'package:shoplive_core/shoplive_core.dart';

export 'src/models/play_options.dart' show ShoplivePlayOptions;
export 'src/models/player_configuration.dart'
    show
        ShoplivePlayerConfiguration,
        ShoplivePipOptions,
        ShopliveInsets,
        ShopliveSoundOptions,
        ShopliveAppearanceOptions,
        ShopliveNavigationOptions,
        ShopliveOverlayOptions,
        ShopliveAndroidPlayerOptions;
export 'src/models/player_enums.dart';
export 'src/models/player_event.dart';
export 'src/models/player_request.dart';
export 'src/platform/shoplive_player_platform_interface.dart' show ShoplivePlayerPlatform;
export 'src/platform/shoplive_player_method_channel.dart' show ShoplivePlayerContract;
export 'src/shoplive_player.dart' show ShoplivePlayer;
