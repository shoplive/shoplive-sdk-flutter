// getCampaigns (SMV-1899 D10): 모델 파싱·요청 wire·취소·동시 호출·오류 전파. 네이티브는 MethodChannel mock으로 대신한다.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoplive_player/shoplive_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('shoplive_player');
  final calls = <MethodCall>[];
  final pending = <String, Completer<Object?>>{};

  Map<String, Object?> item({int id = 1, Object? status = 'onAir', Map<String, Object?>? metrics}) => {
        'campaignId': id, 'campaignKey': 'k$id', 'title': null, 'description': 'd', 'campaignUrl': 'https://u/$id',
        'rerun': true, 'archiveStream': false, 'privateLive': true, 'scheduledAt': 1700000000123, 'scheduledEndAt': null,
        'posterUrl': null,
        'lifecycle': {'status': status, 'rehearsal': true, 'startedAt': null, 'closingAt': 5, 'endedAt': null},
        'metrics': metrics,
      };

  setUp(() {
    calls.clear();
    pending.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      if (call.method == 'getCampaigns') {
        final c = Completer<Object?>();
        pending[(call.arguments as Map)['requestId'] as String] = c;
        return c.future;
      }
      return Future.value(true);
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  String lastId() => (calls.lastWhere((c) => c.method == 'getCampaigns').arguments as Map)['requestId'] as String;

  // case: G-6 (R6-D4) — 모두 named 시그니처(Q1), 기본 요청은 statuses []만, 지정 필드는 wire 이름으로
  test('request wire and named signature', () async {
    unawaited(ShoplivePlayerAPI.getCampaigns());
    unawaited(ShoplivePlayerAPI.getCampaigns(
      request: const ShopliveCampaignListRequest(
        page: 2, size: 20,
        statuses: [ShopliveCampaignListStatus.onAir, ShopliveCampaignListStatus.closed],
        order: ShopliveCampaignListOrder.ascending,
      ),
    ));
    final a = calls[0].arguments as Map, b = calls[1].arguments as Map;
    expect(a['request'], {'statuses': <String>[]});
    expect(b['request'], {'page': 2, 'size': 20, 'statuses': ['onAir', 'closed'], 'order': 'ascending'});
    expect(a['requestId'], isNot(b['requestId']));
  });

  // case: G-1·G-2·G-3·G-4·G-5 (R6-D3) — 전 필드, null, ms → UTC DateTime, 큰 id, lifecycle 4종 + 미지 원문, metrics
  test('response parsing', () async {
    final f = ShoplivePlayerAPI.getCampaigns();
    pending[lastId()]!.complete({
      'campaigns': [
        item(id: 1 << 40, metrics: {'userCount': 1 << 40, 'adoreCount': null, 'showUserCount': false}),
        item(status: 'reserved'),
        item(status: 'ready'),
        item(status: 'closed'),
        {...item(status: 'unknown'), 'lifecycle': {'status': 'unknown', 'unknownStatus': 'PAUSED', 'rehearsal': false}},
        {...item(status: 'unknown'), 'lifecycle': {'status': 'unknown', 'rehearsal': false}},
        {...item(), 'lifecycle': {'status': 'brandNew', 'rehearsal': false}},
      ],
      'hasMore': true,
    });
    final r = await f;
    expect(r.hasMore, isTrue);
    final first = r.campaigns.first;
    expect([first.campaignId, first.campaignKey, first.title, first.description, first.campaignUrl],
        [1 << 40, 'k${1 << 40}', null, 'd', 'https://u/${1 << 40}']);
    expect([first.rerun, first.archiveStream, first.privateLive, first.posterUrl, first.scheduledEndAt], [true, false, true, null, null]);
    expect(first.scheduledAt, DateTime.fromMillisecondsSinceEpoch(1700000000123, isUtc: true));
    expect(first.scheduledAt!.isUtc, isTrue);
    expect(first.lifecycle.status, const ShopliveCampaignLifecycleOnAir());
    expect([first.lifecycle.rehearsal, first.lifecycle.startedAt, first.lifecycle.endedAt], [true, null, null]);
    expect(first.lifecycle.closingAt, DateTime.fromMillisecondsSinceEpoch(5, isUtc: true));
    expect([first.metrics!.userCount, first.metrics!.adoreCount, first.metrics!.showUserCount], [1 << 40, null, false]);
    expect(r.campaigns[1].metrics, isNull);
    expect(r.campaigns.skip(1).map((c) => c.lifecycle.status).toList(), [
      const ShopliveCampaignLifecycleReserved(),
      const ShopliveCampaignLifecycleReady(),
      const ShopliveCampaignLifecycleClosed(),
      const ShopliveCampaignLifecycleUnknown('PAUSED'),
      const ShopliveCampaignLifecycleUnknown(null),
      const ShopliveCampaignLifecycleUnknown('brandNew'),
    ]);
    expect(() => r.campaigns.add(first), throwsUnsupportedError);
  });

  // case: G-14 (R6-D3) — 필수 필드가 틀리면 항목만 빼지 않고 전체를 SDK_ERROR로
  test('malformed response fails as SDK_ERROR', () async {
    for (final raw in <Object?>[
      null,
      {'campaigns': 'x', 'hasMore': true},
      {'campaigns': [item()], 'hasMore': null},
      {'campaigns': [{...item(), 'campaignKey': 1}], 'hasMore': false},
      {'campaigns': [{...item(), 'lifecycle': null}], 'hasMore': false},
      {'campaigns': [{...item(), 'lifecycle': {'status': 'ready'}}], 'hasMore': false},
    ]) {
      final f = ShoplivePlayerAPI.getCampaigns();
      pending[lastId()]!.complete(raw);
      await expectLater(f, throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'SDK_ERROR')), reason: '$raw');
    }
  });

  // case: G-7 (R6-D7) — 네이티브 SDK_ERROR는 그대로, details는 ShopliveError.tryParse로 읽는다
  test('native SDK_ERROR propagates with ShopliveError details', () async {
    final f = ShoplivePlayerAPI.getCampaigns();
    pending[lastId()]!.completeError(PlatformException(
      code: 'SDK_ERROR', message: 'Failed to fetch campaign list.',
      details: {'code': 'CUSTOM_ACCOUNT_NOT_FOUND', 'message': 'Failed to fetch campaign list.', 'rawCode': -200, 'recoverable': false},
    ));
    final e = await f.then<PlatformException?>((_) => null, onError: (Object e) => e as PlatformException);
    expect(e!.code, ShoplivePlatformErrorCode.sdkError);
    final err = ShopliveError.tryParse(e.details)!;
    expect([err.code, err.rawCode, err.recoverable], ['CUSTOM_ACCOUNT_NOT_FOUND', -200, false]);
  });

  // case: G-8·G-9 (R6-D5) — 호출 전 취소: 네이티브를 부르지 않고 CANCELLED
  test('already cancelled token: no native call, CANCELLED', () async {
    final token = ShopliveCancelToken()..cancel();
    await expectLater(ShoplivePlayerAPI.getCampaigns(cancelToken: token),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', ShoplivePlatformErrorCode.cancelled)));
    expect(calls, isEmpty);
  });

  // case: G-8·G-9 (R6-D5) — 진행 중 취소: 즉시 CANCELLED + cancelGetCampaigns(같은 id), 뒤늦은 네이티브 회신은 버림
  test('cancel in flight: CANCELLED at once, native cancel, late reply dropped', () async {
    final token = ShopliveCancelToken();
    final f = ShoplivePlayerAPI.getCampaigns(cancelToken: token);
    final id = lastId();
    token.cancel();
    token.cancel(); // 여러 번 불러도 한 번
    await expectLater(f, throwsA(isA<PlatformException>().having((e) => e.code, 'code', ShoplivePlatformErrorCode.cancelled)));
    expect(token.isCancelled, isTrue);
    final cancels = calls.where((c) => c.method == 'cancelGetCampaigns').toList();
    expect(cancels.length, 1);
    expect(cancels.single.arguments, {'requestId': id});
    pending[id]!.completeError(PlatformException(code: 'CANCELLED')); // 네이티브가 원 회신을 CANCELLED로 끝냄 — 미처리 오류 없이 버려짐
    pending[id] = Completer(); // 같은 Completer 재사용 방지
    await Future<void>.delayed(Duration.zero);
  });

  // case: G-8 (R6-D5) — 토큰 하나로 여러 호출을 취소, 끝난 호출은 취소하지 않는다(리스너 해제)
  test('one token cancels every pending call, finished calls are left alone', () async {
    final token = ShopliveCancelToken();
    final done = ShoplivePlayerAPI.getCampaigns(cancelToken: token);
    final doneId = lastId();
    expect(token.listenerCount, 1);
    pending[doneId]!.complete({'campaigns': <Object?>[], 'hasMore': false});
    expect((await done).campaigns, isEmpty);
    expect(token.listenerCount, 0); // 끝난 호출은 토큰에서 떨어진다(오래 사는 토큰이 끝난 호출을 붙잡지 않게 — 교차검증 L1)
    final a = ShoplivePlayerAPI.getCampaigns(cancelToken: token);
    final b = ShoplivePlayerAPI.getCampaigns(cancelToken: token);
    token.cancel();
    final cancelled = throwsA(isA<PlatformException>().having((e) => e.code, 'code', ShoplivePlatformErrorCode.cancelled));
    await expectLater(a, cancelled);
    await expectLater(b, cancelled);
    final cancelledIds = calls.where((c) => c.method == 'cancelGetCampaigns').map((c) => (c.arguments as Map)['requestId']).toList();
    expect(cancelledIds.length, 2);
    expect(cancelledIds, isNot(contains(doneId)));
  });

  // case: G-10 (R6-D6) — 동시 호출은 독립, 역순 도착에도 각자 자기 결과
  test('concurrent calls complete independently in reverse order', () async {
    final a = ShoplivePlayerAPI.getCampaigns();
    final idA = lastId();
    final b = ShoplivePlayerAPI.getCampaigns();
    final idB = lastId();
    pending[idB]!.complete({'campaigns': [item(id: 2)], 'hasMore': false});
    pending[idA]!.complete({'campaigns': [item(id: 1)], 'hasMore': true});
    expect((await b).campaigns.single.campaignId, 2);
    expect((await a).campaigns.single.campaignId, 1);
  });
}
