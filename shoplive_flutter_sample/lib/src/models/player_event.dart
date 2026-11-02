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

/// 매핑 불가·미지·형식 오류 이벤트(N-03). [rawType]은 디버그 표시용.
class ShoplivePlayerUnknownEvent extends ShoplivePlayerEvent {
  const ShoplivePlayerUnknownEvent({required this.rawType});
  final String rawType;
}
