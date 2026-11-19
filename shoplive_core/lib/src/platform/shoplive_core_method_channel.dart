import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../shoplive_error.dart';
import 'shoplive_core_platform_interface.dart';

/// 채널 `shoplive_core` 메서드명(계약 단일 출처 — Kotlin CoreContract.METHODS와 같은 목록).
abstract final class ShopliveCoreContract {
  static const String initialize = 'initialize';
  static const String setUser = 'setUser';
  static const String setStreamToken = 'setStreamToken';
  static const String logout = 'logout';
  static const String sendConversionEvent = 'sendConversionEvent';
  static const String getSdkVersion = 'getSdkVersion';
  static const List<String> methods = [initialize, setUser, setStreamToken, logout, sendConversionEvent, getSdkVersion];
}

/// 채널 `shoplive_core` 구현. PlatformException은 그대로 전파한다.
class MethodChannelShopliveCore extends ShopliveCorePlatform {
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel(channelName);

  static const String channelName = 'shoplive_core';

  @override
  Future<void> initialize(Map<String, Object?> configuration) =>
      methodChannel.invokeMethod<void>(ShopliveCoreContract.initialize, configuration);

  @override
  Future<void> setUser(Map<String, Object?> user) => methodChannel.invokeMethod<void>(ShopliveCoreContract.setUser, user);

  @override
  Future<void> setStreamToken(String token) =>
      methodChannel.invokeMethod<void>(ShopliveCoreContract.setStreamToken, <String, Object?>{'token': token});

  @override
  Future<void> logout() => methodChannel.invokeMethod<void>(ShopliveCoreContract.logout);

  @override
  Future<void> sendConversionEvent(Map<String, Object?> data) =>
      methodChannel.invokeMethod<void>(ShopliveCoreContract.sendConversionEvent, data);

  @override
  Future<String> getSdkVersion() async {
    final version = await methodChannel.invokeMethod<String>(ShopliveCoreContract.getSdkVersion);
    if (version == null) {
      // 계약 위반도 PlatformException 규칙으로 노출한다(pair #15)
      throw PlatformException(code: ShoplivePlatformErrorCode.sdkError, message: 'getSdkVersion returned null');
    }
    return version;
  }
}
