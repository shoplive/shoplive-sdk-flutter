import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoplive_streamer/shoplive_streamer.dart';
import 'package:shoplive_streamer/src/platform/shoplive_streamer_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('shoplive_streamer');
  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? responder;

  setUp(() {
    calls.clear();
    responder = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return responder?.call(call);
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  // case: U-07
  test('contract names (Kotlin StreamerContract와 동일)', () {
    expect(ShopliveStreamerContract.methods, ['start', 'getState']);
    expect(ShopliveStreamerContract.eventsChannel, 'shoplive_streamer/events');
  });

  // case: N-05
  test('start sends campaignKey', () async {
    await ShopliveStreamer.instance.start('k');
    expect(calls.single.method, 'start');
    expect(calls.single.arguments, {'campaignKey': 'k'});
  });

  // case: SMV-1749 webPageUrl — null이면 키 생략(3.0.2 와이어 그대로), 값은 그대로 전달(검증은 네이티브)
  test('start webPageUrl omitted / given', () async {
    await ShopliveStreamer.instance.start('k', webPageUrl: null);
    await ShopliveStreamer.instance.start('k', webPageUrl: 'https://shop.example.com');
    expect(calls[0].arguments, {'campaignKey': 'k'});
    expect(calls[1].arguments, {'campaignKey': 'k', 'webPageUrl': 'https://shop.example.com'});
  });

  // case: B-02
  test('getState parses wire and unknown', () async {
    responder = (_) => 'reconnecting';
    expect(await ShopliveStreamer.instance.getState(), ShopliveBroadcastState.reconnecting);
    responder = (_) => 'brandNew';
    expect(await ShopliveStreamer.instance.getState(), ShopliveBroadcastState.unknown);
  });

  // case: F-03
  test('getState null → PlatformException(SDK_ERROR)', () async {
    await expectLater(ShopliveStreamer.instance.getState(), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'SDK_ERROR')));
  });

  // case: F-02
  test('PlatformException propagates (NO_HOST_SCREEN)', () async {
    responder = (_) => throw PlatformException(code: 'NO_HOST_SCREEN');
    await expectLater(ShopliveStreamer.instance.start('k'), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'NO_HOST_SCREEN')));
  });

  group('event parsing', () {
    ShopliveStreamerEvent p(Object? raw) => ShopliveStreamerEvent.fromWire(raw);

    // case: N-05
    test('stateChanged / error', () {
      final s = p({'type': 'stateChanged', 'state': 'live', 'isRehearsal': true}) as ShopliveStreamerStateChanged;
      expect([s.state, s.isRehearsal], [ShopliveBroadcastState.live, true]);
      final e = (p({'type': 'error', 'error': {'code': 'UNKNOWN', 'message': null, 'rawCode': 3, 'recoverable': false}}) as ShopliveStreamerErrorEvent).error;
      expect([e.code, e.message, e.rawCode, e.recoverable], ['UNKNOWN', null, 3, false]);
    });

    // case: B-02
    // case: D-1 (DRAFT-flutter-sdk-302-ios) — iOS SDK에는 rehearsal 정보가 없어 키가 생략된다
    test('stateChanged without isRehearsal (iOS) → isRehearsal null', () {
      final s = p({'type': 'stateChanged', 'state': 'live'}) as ShopliveStreamerStateChanged;
      expect(s.state, ShopliveBroadcastState.live);
      expect(s.isRehearsal, isNull);
      final n = p({'type': 'stateChanged', 'state': 'idle', 'isRehearsal': null}) as ShopliveStreamerStateChanged;
      expect(n.isRehearsal, isNull);
    });

    test('unknown / malformed never throw', () {
      expect((p({'type': 'unknown', 'rawType': 'x'}) as ShopliveStreamerUnknownEvent).rawType, 'x');
      expect(p({'type': 'zzz'}), isA<ShopliveStreamerUnknownEvent>());
      expect(p({'type': 'error', 'error': 'bad'}), isA<ShopliveStreamerUnknownEvent>());
      expect(p({'type': 'stateChanged', 'state': 'live', 'isRehearsal': 'yes'}), isA<ShopliveStreamerUnknownEvent>());
      expect(p(42), isA<ShopliveStreamerUnknownEvent>());
    });
  });

  // case: N-05
  test('events stream maps via platform', () async {
    final fake = _FakePlatform();
    ShopliveStreamerPlatform.instance = fake;
    final got = <ShopliveStreamerEvent>[];
    final sub = ShopliveStreamer.createForTesting().events.listen(got.add);
    fake.controller.add({'type': 'stateChanged', 'state': 'ended', 'isRehearsal': false});
    await Future<void>.delayed(Duration.zero);
    expect((got.single as ShopliveStreamerStateChanged).state, ShopliveBroadcastState.ended);
    await sub.cancel();
    ShopliveStreamerPlatform.instance = MethodChannelShopliveStreamer();
  });
}

class _FakePlatform extends ShopliveStreamerPlatform {
  final controller = StreamController<Object?>.broadcast();

  @override
  Future<T?> invokeMethod<T>(String method, [Map<String, Object?>? arguments]) async => null;

  @override
  Stream<Object?> events() => controller.stream;
}
