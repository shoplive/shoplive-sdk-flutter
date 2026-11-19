import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'shoplive_streamer_method_channel.dart';

/// shoplive_streamer 플랫폼 인터페이스.
abstract class ShopliveStreamerPlatform extends PlatformInterface {
  ShopliveStreamerPlatform() : super(token: _token);

  static final Object _token = Object();

  static ShopliveStreamerPlatform _instance = MethodChannelShopliveStreamer();

  static ShopliveStreamerPlatform get instance => _instance;

  static set instance(ShopliveStreamerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<T?> invokeMethod<T>(String method, [Map<String, Object?>? arguments]);

  /// `shoplive_streamer/events` 원시 스트림.
  Stream<Object?> events();
}
