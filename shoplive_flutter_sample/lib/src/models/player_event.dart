import 'package:flutter/foundation.dart';
import 'package:shoplive_core/shoplive_core.dart';

import '../wire.dart';
import 'player_enums.dart';

/// 캠페인 정보(getCurrentCampaign / campaignInfoReceived). status는 nullable(SDK @Nullable, design §2.6).
class ShopliveCampaignInfo {
  const ShopliveCampaignInfo({required this.campaignKey, this.title, this.status});

  final String campaignKey;
  final String? title;
  final ShopliveCampaignStatus? status;

  static ShopliveCampaignInfo? tryParse(Object? raw) {
    final m = asStringMap(raw);
    final key = m?['campaignKey'];
    if (m == null || key is! String) return null;
    return ShopliveCampaignInfo(campaignKey: key, title: asType<String>(m['title']), status: _status(m['status']));
  }
}

/// 공유 요청 정보([ShoplivePlayerShareRequested], SDK 3.0.4+ — SMV-1899). 필드 이름은 네이티브 `ShopliveShareInfo`와 같다.
/// 모든 필드는 nullable: 원천이 없으면 null이다(SDK가 지어 채우지 않음). iOS는 URL로 해석하지 못한 [url]·[thumbnailUrl]도 null로 준다(플랫폼 차이).
class ShopliveShareInfo {
  const ShopliveShareInfo({this.url, this.campaignKey, this.title, this.descriptionText, this.thumbnailUrl});

  /// 공유 링크: `navigation.shareScheme` → 없으면 웹이 보낸 공유 URL. 둘 다 없으면 null.
  final String? url;
  final String? campaignKey;
  final String? title;
  final String? descriptionText;
  final String? thumbnailUrl;

  /// 필드 형식 오류는 그 필드만 null(이벤트는 유지).
  static ShopliveShareInfo _fromWire(Map<String, Object?> m) => ShopliveShareInfo(
        url: asType<String>(m['url']),
        campaignKey: asType<String>(m['campaignKey']),
        title: asType<String>(m['title']),
        descriptionText: asType<String>(m['descriptionText']),
        thumbnailUrl: asType<String>(m['thumbnailUrl']),
      );
}

class ShopliveCampaign {
  const ShopliveCampaign({required this.status, this.title});

  final String? title;
  final ShopliveCampaignStatus status;
}

class ShopliveBrand {
  const ShopliveBrand({this.name, this.identifier, this.imageUrl});

  final String? name;
  final String? identifier;
  final String? imageUrl;
}

ShopliveCampaignStatus? _status(Object? raw) =>
    raw == null ? null : parseWireEnum(ShopliveCampaignStatus.values, raw, unknown: ShopliveCampaignStatus.unknown);

/// `shoplive_player/events` 이벤트(design.md rev2 §2.5).
sealed class ShoplivePlayerEvent {
  const ShoplivePlayerEvent();

  /// 네이티브 payload → 이벤트. **던지지 않는다**: 미지 type·형식 오류는 [ShoplivePlayerUnknownEvent](pair #15).
  static ShoplivePlayerEvent fromWire(Object? raw) {
    final m = asStringMap(raw);
    final type = m?['type'];
    if (m == null || type is! String) return const ShoplivePlayerUnknownEvent(rawType: '');
    final parsed = _parse(type, m);
    if (parsed == null) {
      debugPrint('ShoplivePlayer: malformed event payload type=$type');
      return ShoplivePlayerUnknownEvent(rawType: type);
    }
    return parsed;
  }

  static ShoplivePlayerEvent? _parse(String type, Map<String, Object?> m) {
    switch (type) {
      case 'stateChanged':
        final state = parseWireEnum(ShoplivePlayerState.values, m['state'], unknown: ShoplivePlayerState.unknown);
        // closeReason은 closed일 때만(SMV-1899 A4): 키 없음 = null, 미지·비문자열·null 값 = unknown. 다른 상태의 키는 무시.
        final closeReason = state == ShoplivePlayerState.closed && m.containsKey('closeReason')
            ? parseWireEnum(ShopliveCloseReason.values, m['closeReason'], unknown: ShopliveCloseReason.unknown)
            : null;
        return ShoplivePlayerStateChanged(state, closeReason: closeReason);
      case 'campaignStatusChanged':
        return ShopliveCampaignStatusChanged(
          parseWireEnum(ShopliveCampaignStatus.values, m['status'], unknown: ShopliveCampaignStatus.unknown),
        );
      case 'campaignInfoReceived':
        final info = ShopliveCampaignInfo.tryParse(m);
        return info == null ? null : ShopliveCampaignInfoReceived(info);
      case 'connectionStateChanged':
        return ShopliveConnectionStateChanged(
          parseWireEnum(ShopliveConnectionState.values, m['state'], unknown: ShopliveConnectionState.unknown),
        );
      case 'playback':
        return ShoplivePlaybackEvent(
          kind: parseWireEnum(ShoplivePlaybackEventKind.values, m['event'], unknown: ShoplivePlaybackEventKind.unknown),
          timestampMs: asType<int>(m['timestampMs']),
          code: asType<int>(m['code']),
          message: asType<String>(m['message']),
        );
      case 'error':
        final error = ShopliveError.tryParse(m['error']);
        return error == null ? null : ShoplivePlayerErrorEvent(error);
      case 'analytics':
        final key = m['campaignKey'];
        if (key is! String) return null;
        final campaign = asStringMap(m['campaign']);
        final brand = asStringMap(m['brand']);
        return ShopliveAnalyticsEvent(
          campaignKey: key,
          isPlaying: m['isPlaying'] == true,
          isMuted: m['isMuted'] == true,
          durationMs: asType<int>(m['durationMs']) ?? 0,
          campaign: campaign == null
              ? null
              : ShopliveCampaign(title: asType<String>(campaign['title']), status: _status(campaign['status']) ?? ShopliveCampaignStatus.unknown),
          brand: brand == null
              ? null
              : ShopliveBrand(
                  name: asType<String>(brand['name']),
                  identifier: asType<String>(brand['identifier']),
                  imageUrl: asType<String>(brand['imageUrl']),
                ),
        );
      case 'webCommandReceived':
        final name = m['name'];
        final payload = asStringMap(m['payload']);
        if (name is! String || payload == null) return null;
        return ShopliveWebCommandReceived(name: name, payload: payload);
      case 'userNameUpdateRequested':
        final payload = asStringMap(m['payload']);
        return payload == null ? null : ShopliveUserNameUpdateRequested(payload);
      case 'shareRequested':
        return ShoplivePlayerShareRequested(ShopliveShareInfo._fromWire(m));
      case 'unknown':
        return ShoplivePlayerUnknownEvent(rawType: asType<String>(m['rawType']) ?? '');
      default:
        return ShoplivePlayerUnknownEvent(rawType: type);
    }
  }
}

class ShoplivePlayerStateChanged extends ShoplivePlayerEvent {
  const ShoplivePlayerStateChanged(this.state, {this.closeReason});
  final ShoplivePlayerState state;

  /// [state]가 [ShoplivePlayerState.closed]일 때 닫힌 이유(SDK 3.0.4+). 다른 상태에서는 항상 null.
  /// closed인데 null이면 네이티브가 이유를 보내지 않은 경우다. `getState()`는 이유를 주지 않는다.
  final ShopliveCloseReason? closeReason;
}

class ShopliveCampaignStatusChanged extends ShoplivePlayerEvent {
  const ShopliveCampaignStatusChanged(this.status);
  final ShopliveCampaignStatus status;
}

class ShopliveCampaignInfoReceived extends ShoplivePlayerEvent {
  const ShopliveCampaignInfoReceived(this.info);
  final ShopliveCampaignInfo info;
}

class ShopliveConnectionStateChanged extends ShoplivePlayerEvent {
  const ShopliveConnectionStateChanged(this.state);
  final ShopliveConnectionState state;
}

class ShoplivePlaybackEvent extends ShoplivePlayerEvent {
  const ShoplivePlaybackEvent({required this.kind, this.timestampMs, this.code, this.message});
  final ShoplivePlaybackEventKind kind;
  final int? timestampMs;

  /// [kind]가 failed일 때만.
  final int? code;
  final String? message;
}

class ShoplivePlayerErrorEvent extends ShoplivePlayerEvent {
  const ShoplivePlayerErrorEvent(this.error);
  final ShopliveError error;
}

class ShopliveAnalyticsEvent extends ShoplivePlayerEvent {
  const ShopliveAnalyticsEvent({
    required this.campaignKey,
    required this.isPlaying,
    required this.isMuted,
    required this.durationMs,
    this.campaign,
    this.brand,
  });
  final String campaignKey;
  final bool isPlaying;
  final bool isMuted;
  final int durationMs;
  final ShopliveCampaign? campaign;
  final ShopliveBrand? brand;
}

class ShopliveWebCommandReceived extends ShoplivePlayerEvent {
  const ShopliveWebCommandReceived({required this.name, required this.payload});
  final String name;
  final Map<String, Object?> payload;
}

class ShopliveUserNameUpdateRequested extends ShoplivePlayerEvent {
  const ShopliveUserNameUpdateRequested(this.payload);
  final Map<String, Object?> payload;
}

// TODO(SDP-VERIFY): 요확인 — 아래 문서 주석 'url null' 줄: iOS에서 url이 nil일 때 error 이벤트가 함께 오는지(Android는 NOT_INITIALIZED_SHARE_URL 1건) · 근거 SMV-1899
// TODO(SDP-VERIFY): 요확인 — 아래 문서 주석 'Android 공유 화면 띄우기' 줄: 공유 전 in-App PIP 전환 패턴이 공유 화면 종료 뒤 방송 복귀를 보장하는지 실측 · 근거 SMV-1899
// TODO(SDP-VERIFY): 요확인 — 아래 문서 주석 'iOS 시트 위치' 줄: share_plus 등 앱 공유 시트가 .overFullScreen 플레이어 위에 표시되는지 실측 · 근거 SMV-1899
/// 시청자가 공유 버튼을 눌렀다(SDK 3.0.4+, SMV-1899) — 앱이 [info]로 공유 화면을 띄운다.
///
/// `navigation.isCustomShareEnabled: true`로 시작한 세션에서만 오고, 이때 SDK 기본 공유 시트는 뜨지 않는다.
/// false·생략이면 이 이벤트 없이 기본 시트가 뜬다. SDK가 알린 1건을 1건으로 전달한다(브릿지는 합치거나 늘리지 않음).
/// - **events를 구독하지 않으면 공유는 아무 반응이 없다**(기본 시트도 뜨지 않음 — 경고 로그만). 켤 때는 반드시 구독한다.
/// - url null: 링크가 없으면 url이 null로 온다 — 링크 없이 처리하거나 무시한다. Android는 error 이벤트(NOT_INITIALIZED_SHARE_URL)도 함께 온다.
/// - Android 공유 화면 띄우기: 풀스크린 플레이어는 별도 태스크라, 앱 화면에서 띄운 공유 화면을 닫으면 방송 대신 앱 화면이 앞에 올 수 있다.
///   공유 전에 `enterPictureInPicture()`로 in-App PIP로 바꾼 뒤 띄우는 방식을 권장한다.
/// - iOS 시트 위치: 플레이어는 Flutter 화면 위에 표시되므로 공유 시트는 최상위 화면 기준으로 띄운다.
class ShoplivePlayerShareRequested extends ShoplivePlayerEvent {
  const ShoplivePlayerShareRequested(this.info);
  final ShopliveShareInfo info;
}

/// 매핑 불가·미지·형식 오류 이벤트(N-03). [rawType]은 디버그 표시용.
class ShoplivePlayerUnknownEvent extends ShoplivePlayerEvent {
  const ShoplivePlayerUnknownEvent({required this.rawType});
  final String rawType;
}
