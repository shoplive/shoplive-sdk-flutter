import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shoplive_core/shoplive_core.dart';
// shoplive_core의 패키지 내부용 브릿지 헬퍼(고객 비보장 — pair #25).
import 'package:shoplive_core/shoplive_core_bridge.dart';

import 'platform/shoplive_streamer_method_channel.dart';
import 'platform/shoplive_streamer_platform_interface.dart';

/// 방송 상태(wire: design §2.3). 미지 값은 `unknown`(B-02).
enum ShopliveBroadcastState { idle, preview, connecting, live, reconnecting, ended, unknown }

/// 방송 화면(design.md rev2 §2.4 shoplive_streamer). 실패 시 PlatformException(INVALID_ARGUMENT / NO_HOST_SCREEN / SDK_ERROR).
class ShopliveStreamer {
  ShopliveStreamer._();

  static final ShopliveStreamer instance = ShopliveStreamer._();

  @visibleForTesting
  factory ShopliveStreamer.createForTesting() => ShopliveStreamer._();

  ShopliveStreamerPlatform get _platform => ShopliveStreamerPlatform.instance;

  /// 방송 키로 방송 화면을 연다. 호출마다 새 방송 세션을 만든다(ST-01).
  ///
  /// [webPageUrl]: 방송 화면에서 스와이프로 여는 웹페이지(SDK 3.0.3+, Android·iOS). null이면 웹페이지 없음(3.0.2와 같음).
  /// `http://`·`https://`로 시작(대소문자 무관)하고, userinfo·포트를 뺀 호스트가 비어 있지 않고, authority에 역슬래시가 없으며,
  /// 공백·제어문자가 없어야 한다 — 그 외는
  /// `PlatformException(INVALID_ARGUMENT)`. 그 밖의 검사는 SDK에 맡긴다(Android·iOS 같은 규칙).
  ///
  /// Call `Shoplive.setStreamToken` with the broadcaster token first. Without it the server returns no ingest
  /// address and the broadcast screen shows a "failed to start" retry dialog.
  Future<void> start(String campaignKey, {String? webPageUrl}) => _platform.invokeMethod<void>(
        ShopliveStreamerContract.start,
        {'campaignKey': campaignKey, if (webPageUrl != null) 'webPageUrl': webPageUrl},
      );

  /// 마지막 방송 세션의 상태. 세션이 없으면 idle.
  Future<ShopliveBroadcastState> getState() async {
    final raw = await _platform.invokeMethod<String>(ShopliveStreamerContract.getState);
    if (raw == null) {
      throw PlatformException(code: ShoplivePlatformErrorCode.sdkError, message: 'getState returned null');
    }
    return parseWireEnum(ShopliveBroadcastState.values, raw, unknown: ShopliveBroadcastState.unknown);
  }

  Stream<ShopliveStreamerEvent>? _events;

  /// 방송 이벤트. 형식 오류·미지 이벤트는 [ShopliveStreamerUnknownEvent](스트림을 끊지 않음).
  Stream<ShopliveStreamerEvent> get events => _events ??= _platform.events().map(ShopliveStreamerEvent.fromWire);
}

/// `shoplive_streamer/events` 이벤트(design §2.5).
sealed class ShopliveStreamerEvent {
  const ShopliveStreamerEvent();

  /// 던지지 않는다 — 미지·형식 오류는 [ShopliveStreamerUnknownEvent].
  static ShopliveStreamerEvent fromWire(Object? raw) {
    if (raw is! Map) return const ShopliveStreamerUnknownEvent(rawType: '');
    final type = raw['type'];
    if (type is! String) return const ShopliveStreamerUnknownEvent(rawType: '');
    switch (type) {
      case 'stateChanged':
        // isRehearsal은 선택 필드: iOS SDK에는 rehearsal 정보가 없어 키를 생략한다(DRAFT-flutter-sdk-302-ios D-1).
        final rehearsal = raw['isRehearsal'];
        if (rehearsal != null && rehearsal is! bool) return ShopliveStreamerUnknownEvent(rawType: type);
        return ShopliveStreamerStateChanged(
          state: parseWireEnum(ShopliveBroadcastState.values, raw['state'], unknown: ShopliveBroadcastState.unknown),
          isRehearsal: rehearsal as bool?,
        );
      case 'error':
        final error = ShopliveError.tryParse(raw['error']);
        return error == null ? ShopliveStreamerUnknownEvent(rawType: type) : ShopliveStreamerErrorEvent(error);
      case 'unknown':
        final rawType = raw['rawType'];
        return ShopliveStreamerUnknownEvent(rawType: rawType is String ? rawType : '');
      default:
        return ShopliveStreamerUnknownEvent(rawType: type);
    }
  }
}

class ShopliveStreamerStateChanged extends ShopliveStreamerEvent {
  const ShopliveStreamerStateChanged({required this.state, this.isRehearsal});
  final ShopliveBroadcastState state;

  /// 리허설 방송 여부. 플랫폼이 제공하지 않으면 null(iOS SDK 3.0.3은 제공하지 않음).
  final bool? isRehearsal;
}

class ShopliveStreamerErrorEvent extends ShopliveStreamerEvent {
  const ShopliveStreamerErrorEvent(this.error);
  final ShopliveError error;
}

class ShopliveStreamerUnknownEvent extends ShopliveStreamerEvent {
  const ShopliveStreamerUnknownEvent({required this.rawType});
  final String rawType;
}
