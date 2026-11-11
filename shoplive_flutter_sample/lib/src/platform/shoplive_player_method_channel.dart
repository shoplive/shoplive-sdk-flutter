import 'package:flutter/services.dart';

import 'shoplive_player_platform_interface.dart';

/// 채널·메서드 이름(계약 단일 출처 — Kotlin PlayerContract와 같은 목록).
abstract final class ShoplivePlayerContract {
  static const String methodChannel = 'shoplive_player';
  static const String eventsChannel = 'shoplive_player/events';
  static const String requestsChannel = 'shoplive_player/requests';

  static const String start = 'start';
  static const String play = 'play';
  static const String stop = 'stop';
  static const String close = 'close';
  static const String reload = 'reload';
  static const String send = 'send';
  static const String setMuted = 'setMuted';
  static const String isMuted = 'isMuted';
  static const String setResizeMode = 'setResizeMode';
  static const String getResizeMode = 'getResizeMode';
  static const String setOverlayUI = 'setOverlayUI';
  static const String getOverlayUI = 'getOverlayUI';
  static const String enterPictureInPicture = 'enterPictureInPicture';
  static const String exitPictureInPicture = 'exitPictureInPicture';
  static const String isInPictureInPicture = 'isInPictureInPicture';
  static const String getState = 'getState';
  static const String getCurrentCampaign = 'getCurrentCampaign';
  static const String isRunning = 'isRunning';
  static const String setConfiguration = 'setConfiguration';
  static const String getConfiguration = 'getConfiguration';
  static const String setRequestTimeout = 'setRequestTimeout';
  static const String respondCoupon = 'respondCoupon';
  static const String respondCustomAction = 'respondCustomAction';
  static const String respondFallback = 'respondFallback';
  static const String getCampaigns = 'getCampaigns';
  static const String cancelGetCampaigns = 'cancelGetCampaigns';

  static const List<String> methods = [
    start, play, stop, close, reload, send, setMuted, isMuted, setResizeMode, getResizeMode, setOverlayUI, getOverlayUI,
    enterPictureInPicture, exitPictureInPicture, isInPictureInPicture, getState, getCurrentCampaign, isRunning,
    setConfiguration, getConfiguration, setRequestTimeout, respondCoupon, respondCustomAction, respondFallback,
    getCampaigns, cancelGetCampaigns,
  ];
}

class MethodChannelShoplivePlayer extends ShoplivePlayerPlatform {
  final MethodChannel _methods = const MethodChannel(ShoplivePlayerContract.methodChannel);
  final EventChannel _events = const EventChannel(ShoplivePlayerContract.eventsChannel);
  final EventChannel _requests = const EventChannel(ShoplivePlayerContract.requestsChannel);

  @override
  Future<T?> invokeMethod<T>(String method, [Map<String, Object?>? arguments]) => _methods.invokeMethod<T>(method, arguments);

  @override
  Stream<Object?> events() => _events.receiveBroadcastStream();

  @override
  Stream<Object?> requests() => _requests.receiveBroadcastStream();
}
