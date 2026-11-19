import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'shoplive_player_method_channel.dart';

/// shoplive_player 플랫폼 인터페이스. 인자·이벤트는 wire Map.
abstract class ShoplivePlayerPlatform extends PlatformInterface {
  ShoplivePlayerPlatform() : super(token: _token);

  static final Object _token = Object();

  static ShoplivePlayerPlatform _instance = MethodChannelShoplivePlayer();

  static ShoplivePlayerPlatform get instance => _instance;

  static set instance(ShoplivePlayerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<T?> invokeMethod<T>(String method, [Map<String, Object?>? arguments]);

  /// `shoplive_player/events` 원시 스트림.
  Stream<Object?> events();

  /// `shoplive_player/requests` 원시 스트림. 구독 = 네이티브 sink 존재.
  Stream<Object?> requests();
}
