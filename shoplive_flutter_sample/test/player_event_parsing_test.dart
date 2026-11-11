import 'package:flutter_test/flutter_test.dart';
import 'package:shoplive_player/shoplive_player.dart';

void main() {
  ShoplivePlayerEvent p(Object? raw) => ShoplivePlayerEvent.fromWire(raw);

  // case: N-03
  test('nine event types', () {
    expect((p({'type': 'stateChanged', 'state': 'playing'}) as ShoplivePlayerStateChanged).state, ShoplivePlayerState.playing);
    expect((p({'type': 'campaignStatusChanged', 'status': 'ended'}) as ShopliveCampaignStatusChanged).status, ShopliveCampaignStatus.ended);
    final info = (p({'type': 'campaignInfoReceived', 'campaignKey': 'k', 'title': 't', 'status': null}) as ShopliveCampaignInfoReceived).info;
    expect([info.campaignKey, info.title, info.status], ['k', 't', null]);
    expect((p({'type': 'connectionStateChanged', 'state': 'reconnecting'}) as ShopliveConnectionStateChanged).state, ShopliveConnectionState.reconnecting);
    final pb = p({'type': 'playback', 'event': 'failed', 'timestampMs': 5, 'code': 7, 'message': 'x'}) as ShoplivePlaybackEvent;
    expect([pb.kind, pb.timestampMs, pb.code, pb.message], [ShoplivePlaybackEventKind.failed, 5, 7, 'x']);
    final err = (p({'type': 'error', 'error': {'code': 'CONNECTION_ISSUE', 'message': 'm', 'rawCode': null, 'recoverable': true}}) as ShoplivePlayerErrorEvent).error;
    expect([err.code, err.recoverable], ['CONNECTION_ISSUE', true]);
    final an = p({
      'type': 'analytics', 'campaignKey': 'k', 'isPlaying': true, 'isMuted': false, 'durationMs': 10,
      'campaign': {'title': 't', 'status': 'live'}, 'brand': null,
    }) as ShopliveAnalyticsEvent;
    expect([an.campaignKey, an.isPlaying, an.isMuted, an.durationMs, an.campaign!.status, an.brand], ['k', true, false, 10, ShopliveCampaignStatus.live, null]);
    final wc = p({'type': 'webCommandReceived', 'name': 'n', 'payload': {'a': 1}}) as ShopliveWebCommandReceived;
    expect([wc.name, wc.payload], ['n', {'a': 1}]);
    expect((p({'type': 'userNameUpdateRequested', 'payload': {'x': 'y'}}) as ShopliveUserNameUpdateRequested).payload, {'x': 'y'});
  });

  // case: N-03
  test('playback kinds incl. unknown', () {
    for (final k in ['requested', 'started', 'audioLoaded', 'rendering', 'buffering', 'rebufferingStarted', 'rebufferingEnded', 'ended']) {
      expect((p({'type': 'playback', 'event': k, 'timestampMs': null}) as ShoplivePlaybackEvent).kind.name, k);
    }
    expect((p({'type': 'playback', 'event': 'stalled'}) as ShoplivePlaybackEvent).kind, ShoplivePlaybackEventKind.unknown);
  });

  // case: B-02
  test('unknown enum values → unknown member (B-02)', () {
    expect((p({'type': 'stateChanged', 'state': 'zombie'}) as ShoplivePlayerStateChanged).state, ShoplivePlayerState.unknown);
  });

  // case: N-03, B-02
  test('unknown type / native unknown / malformed → ShoplivePlayerUnknownEvent (no throw)', () {
    expect((p({'type': 'unknown', 'rawType': 'newEvent'}) as ShoplivePlayerUnknownEvent).rawType, 'newEvent');
    expect((p({'type': 'brandNew'}) as ShoplivePlayerUnknownEvent).rawType, 'brandNew');
    expect(p({'type': 'error', 'error': {'code': 1}}), isA<ShoplivePlayerUnknownEvent>());
    expect(p({'type': 'campaignInfoReceived'}), isA<ShoplivePlayerUnknownEvent>());
    expect(p({'type': 'webCommandReceived', 'name': 'n'}), isA<ShoplivePlayerUnknownEvent>());
    expect(p('not a map'), isA<ShoplivePlayerUnknownEvent>());
    expect(p(null), isA<ShoplivePlayerUnknownEvent>());
  });

  // case: A4-1 (R-D1, SMV-1899) — closed + closeReason 3종
  test('stateChanged closed carries closeReason', () {
    for (final r in ['userAction', 'appRequest', 'accessKeyChanged']) {
      final e = p({'type': 'stateChanged', 'state': 'closed', 'closeReason': r}) as ShoplivePlayerStateChanged;
      expect([e.state, e.closeReason?.name], [ShoplivePlayerState.closed, r]);
    }
  });

  // case: A4-2 (R-D2, SMV-1899) — 미지 문자열·비문자열·null 값 → unknown, 키 없음 → null, closed 아닌 상태의 키 → null
  test('closeReason: unknown values, missing key, non-closed state', () {
    ShoplivePlayerStateChanged s(Map<String, Object?> m) => p({'type': 'stateChanged', ...m}) as ShoplivePlayerStateChanged;
    expect(s({'state': 'closed', 'closeReason': 'kicked'}).closeReason, ShopliveCloseReason.unknown);
    expect(s({'state': 'closed', 'closeReason': 3}).closeReason, ShopliveCloseReason.unknown);
    expect(s({'state': 'closed', 'closeReason': null}).closeReason, ShopliveCloseReason.unknown);
    expect(s({'state': 'closed'}).closeReason, isNull);
    expect(s({'state': 'playing', 'closeReason': 'userAction'}).closeReason, isNull);
    expect(s({'state': 'playing', 'closeReason': 'userAction'}).state, ShoplivePlayerState.playing);
  });

  // case: A4-4 (R-D4, SMV-1899) — ShoplivePlayerState enum 값·순서 불변(비파괴), 기존 생성자 호환
  test('ShoplivePlayerState values unchanged and the constructor stays compatible', () {
    expect(ShoplivePlayerState.values.map((v) => v.name).toList(), ['idle', 'loading', 'playing', 'paused', 'inAppPip', 'closed', 'unknown']);
    expect(ShopliveCloseReason.values.map((v) => v.name).toList(), ['userAction', 'appRequest', 'accessKeyChanged', 'unknown']);
    const legacy = ShoplivePlayerStateChanged(ShoplivePlayerState.closed);
    expect(legacy.closeReason, isNull);
  });

  // case: A1-3 (R-D3, SMV-1899) — shareRequested 전 필드 / 전부 null / 비문자열 필드는 그 필드만 null
  test('shareRequested parses ShopliveShareInfo', () {
    ShopliveShareInfo info(Map<String, Object?> m) => (p({'type': 'shareRequested', ...m}) as ShoplivePlayerShareRequested).info;
    final full = info({'url': 'https://s/1', 'campaignKey': 'k', 'title': 't', 'descriptionText': 'd', 'thumbnailUrl': 'https://s/p.png'});
    expect([full.url, full.campaignKey, full.title, full.descriptionText, full.thumbnailUrl], ['https://s/1', 'k', 't', 'd', 'https://s/p.png']);
    final empty = info({'url': null, 'campaignKey': null, 'title': null, 'descriptionText': null, 'thumbnailUrl': null});
    expect([empty.url, empty.campaignKey, empty.title, empty.descriptionText, empty.thumbnailUrl], everyElement(isNull));
    final missing = info({});
    expect([missing.url, missing.campaignKey, missing.title, missing.descriptionText, missing.thumbnailUrl], everyElement(isNull));
    final bad = info({'url': 1, 'campaignKey': 'k', 'title': true});
    expect([bad.url, bad.campaignKey, bad.title], [null, 'k', null]);
  });

  // case: E-1 (R6-D10, SMV-1899) — Android 3.0.6 PIP 권한 꺼짐(9511)은 코드 문자열 그대로 error 이벤트로 온다(브릿지 패스스루)
  test('PIP_DISABLED_BY_USER error event keeps code and rawCode', () {
    final err = (p({
      'type': 'error',
      'error': {'code': 'PIP_DISABLED_BY_USER', 'message': 'm', 'rawCode': 9511, 'recoverable': false},
    }) as ShoplivePlayerErrorEvent)
        .error;
    expect([err.code, err.rawCode, err.recoverable], ['PIP_DISABLED_BY_USER', 9511, false]);
  });
}
