import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoplive_core/shoplive_core.dart';
import 'package:shoplive_core/src/platform/shoplive_core_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('shoplive_core');
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

  group('계약: 메서드명·인자 키 (design.md rev2 §2.4)', () {
    // case: U-07
    test('method names are the contract list', () {
      // Kotlin CoreContract.METHODS와 같은 목록(각 언어에서 고정, pair #16)
      expect(
        ['initialize', 'setUser', 'setStreamToken', 'logout', 'sendConversionEvent', 'getSdkVersion'],
        ShopliveCoreContract.methods,
      );
    });

    // case: B-03, N-01
    test('initialize minimal omits optional keys', () async {
      await Shoplive.initialize(const ShopliveConfiguration(accessKey: 'ak'));
      expect(calls.single.method, 'initialize');
      expect(calls.single.arguments, {'accessKey': 'ak'});
    });

    // case: N-01
    test('initialize full', () async {
      await Shoplive.initialize(const ShopliveConfiguration(
        accessKey: 'ak',
        allowedWebViewDomains: ['a.com'],
        attribution: ShopliveAttribution(utmSource: 's', utmContent: 't'),
        // 3.0.2 호출 호환: deprecated지만 wire로는 계속 보낸다(네이티브가 타입 검증 후 무시 — SMV-1749).
        // ignore: deprecated_member_use_from_same_package
        appVersion: '1.0',
      ));
      expect(calls.single.arguments, {
        'accessKey': 'ak',
        'allowedWebViewDomains': ['a.com'],
        'attribution': {'utmSource': 's', 'utmContent': 't'},
        'appVersion': '1.0',
      });
    });

    // case: N-01
    test('setUser guest / token / profile', () async {
      await Shoplive.setUser(const ShopliveUser.guest());
      await Shoplive.setUser(const ShopliveUser.token('jwt'));
      await Shoplive.setUser(const ShopliveUser.profile(
        id: 'u1',
        name: 'N',
        age: 30,
        gender: ShopliveGender.female,
        rank: 2,
        custom: {'tier': 'gold', 'tags': ['a']},
      ));
      await Shoplive.setUser(const ShopliveUser.profile(id: 'u2'));
      expect(calls.map((c) => c.method), everyElement('setUser'));
      expect(calls[0].arguments, {'type': 'guest'});
      expect(calls[1].arguments, {'type': 'token', 'jwt': 'jwt'});
      expect(calls[2].arguments, {
        'type': 'profile',
        'id': 'u1',
        'name': 'N',
        'age': 30,
        'gender': 'female',
        'rank': 2,
        'custom': {'tier': 'gold', 'tags': ['a']},
      });
      expect(calls[3].arguments, {'type': 'profile', 'id': 'u2'});
    });

    // case: N-01
    test('setStreamToken / logout', () async {
      await Shoplive.setStreamToken('t');
      await Shoplive.logout();
      expect(calls[0].method, 'setStreamToken');
      expect(calls[0].arguments, {'token': 't'});
      expect(calls[1].method, 'logout');
      expect(calls[1].arguments, isNull);
    });

    // case: B-06
    test('sendConversionEvent with products (empty product map, double price)', () async {
      await Shoplive.sendConversionEvent(const ShopliveConversionData(
        type: 'purchase',
        products: [
          ShopliveConversionProduct(productId: 'p1', purchaseQuantity: 2, purchaseUnitPrice: 1000),
          ShopliveConversionProduct(),
        ],
        orderId: 'o1',
        referrer: 'r',
        custom: {'x': true},
      ));
      expect(calls.single.method, 'sendConversionEvent');
      expect(calls.single.arguments, {
        'type': 'purchase',
        'products': [
          {'productId': 'p1', 'purchaseQuantity': 2, 'purchaseUnitPrice': 1000.0},
          <String, Object?>{},
        ],
        'orderId': 'o1',
        'referrer': 'r',
        'custom': {'x': true},
      });
    });

    // case: B-05
    test('sendConversionEvent empty products list is passed through', () async {
      await Shoplive.sendConversionEvent(const ShopliveConversionData(products: []));
      expect(calls.single.arguments, {'products': <Object?>[]});
    });

    // case: N-01
    test('getSdkVersion returns native string', () async {
      responder = (_) => '3.0.3';
      expect(await Shoplive.getSdkVersion(), '3.0.3');
      expect(calls.single.method, 'getSdkVersion');
    });
  });

  group('실패 경로', () {
    // case: CS-01
    test('PlatformException propagates unchanged (no swallowing)', () async {
      responder = (_) => throw PlatformException(code: ShoplivePlatformErrorCode.invalidArgument, message: 'id: expected String');
      await expectLater(
        Shoplive.setUser(const ShopliveUser.profile(id: 'u1')),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'INVALID_ARGUMENT')),
      );
    });

    // case: CS-01
    test('SDK_ERROR propagates', () async {
      responder = (_) => throw PlatformException(code: ShoplivePlatformErrorCode.sdkError);
      await expectLater(Shoplive.logout(), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'SDK_ERROR')));
    });

    // case: F-03
    test('getSdkVersion null reply is a PlatformException(SDK_ERROR)', () async {
      responder = (_) => null;
      await expectLater(
        Shoplive.getSdkVersion(),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'SDK_ERROR')),
      );
    });

    // case: F-05
    test('missing plugin propagates MissingPluginException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      await expectLater(Shoplive.logout(), throwsA(isA<MissingPluginException>()));
    });
  });

  // case: U-07
  test('platform error code constants match contract (design §2.2)', () {
    expect(ShoplivePlatformErrorCode.invalidArgument, 'INVALID_ARGUMENT');
    expect(ShoplivePlatformErrorCode.noHostScreen, 'NO_HOST_SCREEN');
    expect(ShoplivePlatformErrorCode.notRunning, 'NOT_RUNNING');
    expect(ShoplivePlatformErrorCode.sdkError, 'SDK_ERROR');
  });
}
