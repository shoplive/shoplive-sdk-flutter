import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoplive_player/shoplive_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('shoplive_player');
  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? responder;
  late ShoplivePlayer player;

  setUp(() {
    calls.clear();
    responder = null;
    player = ShoplivePlayer.createForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return responder?.call(call);
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('method names are the contract list (Kotlin PlayerContract.METHODS와 동일)', () {
    expect(ShoplivePlayerContract.methods, [
      'start', 'play', 'stop', 'close', 'reload', 'send', 'setMuted', 'isMuted', 'setResizeMode', 'getResizeMode',
      'setOverlayUI', 'getOverlayUI', 'enterPictureInPicture', 'exitPictureInPicture', 'isInPictureInPicture', 'getState',
      'getCurrentCampaign', 'isRunning', 'setConfiguration', 'getConfiguration', 'setRequestTimeout', 'respondCoupon',
      'respondCustomAction', 'respondFallback',
    ]);
  });

  // case: N-02, CFG-01
  test('start minimal / full', () async {
    await player.start('k');
    await player.start(
      'k',
      playOptions: const ShoplivePlayOptions(referrer: 'r', presentationStyle: ShoplivePresentationStyle.pip),
      configuration: const ShoplivePlayerConfiguration(
        pip: ShoplivePipOptions(
          isInAppPipEnabled: true,
          aspectRatio: ShoplivePipRatio.ratio9x16,
          padding: ShopliveInsets(top: 4),
          isDragOutToCloseEnabled: false,
        ),
        sound: ShopliveSoundOptions(muteOnStart: true),
        android: ShopliveAndroidPlayerOptions(enterOSPipOnBackPressed: true),
        customParameters: {'a': 'b'},
      ),
    );
    expect(calls[0].method, 'start');
    expect(calls[0].arguments, {'campaignKey': 'k'});
    expect(calls[1].arguments, {
      'campaignKey': 'k',
      'playOptions': {'referrer': 'r', 'presentationStyle': 'pip'},
      'configuration': {
        'pip': {'isInAppPipEnabled': true, 'aspectRatio': 'ratio9x16', 'padding': {'top': 4}, 'isDragOutToCloseEnabled': false},
        'sound': {'muteOnStart': true},
        'customParameters': {'a': 'b'},
        'android': {'enterOSPipOnBackPressed': true},
      },
    });
  });

  // case: N-02
  test('control methods and argument keys', () async {
    await player.play('k2');
    await player.stop();
    await player.close();
    await player.reload();
    await player.send('cmd', {'x': 1});
    await player.send('cmd2');
    await player.setMuted(true);
    await player.setResizeMode(ShopliveResizeMode.fit);
    await player.setOverlayUI(ShopliveOverlayUIMode.hidden);
    await player.enterPictureInPicture();
    await player.exitPictureInPicture();
    await player.setConfiguration(const ShoplivePlayerConfiguration(overlay: ShopliveOverlayOptions(ui: ShopliveOverlayUIMode.builtIn)));
    await player.setRequestTimeout(const Duration(seconds: 3));
    expect(calls.map((c) => [c.method, c.arguments]).toList(), [
      ['play', {'campaignKey': 'k2'}],
      ['stop', null],
      ['close', null],
      ['reload', null],
      ['send', {'command': 'cmd', 'payload': {'x': 1}}],
      ['send', {'command': 'cmd2'}],
      ['setMuted', {'muted': true}],
      ['setResizeMode', {'mode': 'fit'}],
      ['setOverlayUI', {'mode': 'hidden'}],
      ['enterPictureInPicture', null],
      ['exitPictureInPicture', null],
      ['setConfiguration', {'configuration': {'overlay': {'ui': 'builtIn'}}}],
      ['setRequestTimeout', {'timeoutMs': 3000}],
    ]);
  });

  // case: B-02
  test('getters parse wire values (unknown fallback)', () async {
    responder = (c) => switch (c.method) {
          'isMuted' => true,
          'isInPictureInPicture' => false,
          'isRunning' => true,
          'getResizeMode' => 'fit',
          'getOverlayUI' => 'somethingNew',
          'getState' => 'inAppPip',
          'getCurrentCampaign' => {'campaignKey': 'k', 'title': null, 'status': null},
          _ => null,
        };
    expect(await player.isMuted(), isTrue);
    expect(await player.isInPictureInPicture(), isFalse);
    expect(await player.isRunning(), isTrue);
    expect(await player.getResizeMode(), ShopliveResizeMode.fit);
    expect(await player.getOverlayUI(), ShopliveOverlayUIMode.unknown);
    expect(await player.getState(), ShoplivePlayerState.inAppPip);
    final c = (await player.getCurrentCampaign())!;
    expect(c.campaignKey, 'k');
    expect(c.title, isNull);
    expect(c.status, isNull);
  });

  // case: N-02
  test('getCurrentCampaign null', () async {
    expect(await player.getCurrentCampaign(), isNull);
  });

  // case: CFG-02
  test('getConfiguration parses full wire', () async {
    responder = (_) => {
          'type': 'live',
          'pip': {
            'isInAppPipEnabled': true, 'isOSPipEnabled': false, 'defaultPosition': 'bottomRight', 'scale': 0.4,
            'aspectRatio': 'ratio9x16', 'padding': {'left': 1, 'top': 2, 'right': 3, 'bottom': 4},
            'isDragOutToCloseEnabled': true,
          },
          'sound': {'muteOnStart': false, 'mixWithOthers': true},
          'appearance': {'indicatorColor': 0xFF0000FF},
          'navigation': {'actionOnNavigation': 'pip', 'shareScheme': null},
          'overlay': {'ui': 'builtIn'},
          'customParameters': {'a': 'b'},
          'android': {
            'enterOSPipOnBackPressed': false, 'isVolumeKeyEnabled': null, 'autoResumeOnFocusGained': true,
            'isStatusBarVisible': true, 'allowScreenCapture': true, 'closeWhenAppDestroyed': true,
          },
        };
    final c = await player.getConfiguration();
    expect(c.type, ShoplivePlayerType.live);
    expect(c.pip!.defaultPosition, ShoplivePipPosition.bottomRight);
    expect(c.pip!.scale, 0.4);
    expect(c.pip!.padding!.bottom, 4);
    expect(c.pip!.isDragOutToCloseEnabled, isTrue);
    expect(c.sound!.mixWithOthers, isTrue);
    expect(c.appearance!.indicatorColor, 0xFF0000FF);
    expect(c.navigation!.actionOnNavigation, ShopliveNavigationAction.pip);
    expect(c.navigation!.shareScheme, isNull);
    expect(c.overlay!.ui, ShopliveOverlayUIMode.builtIn);
    expect(c.customParameters, {'a': 'b'});
    expect(c.android!.isVolumeKeyEnabled, isNull);
    expect(c.android!.closeWhenAppDestroyed, isTrue);
  });

  // case: F-03
  test('null reply for bool/enum getter → PlatformException(SDK_ERROR)', () async {
    await expectLater(player.isMuted(), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'SDK_ERROR')));
    await expectLater(player.getState(), throwsA(isA<PlatformException>()));
  });

  // case: CS-01, NR-01
  test('PlatformException propagates (NOT_RUNNING / NO_HOST_SCREEN)', () async {
    responder = (c) => throw PlatformException(code: c.method == 'play' ? 'NOT_RUNNING' : 'NO_HOST_SCREEN');
    await expectLater(player.play('k'), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'NOT_RUNNING')));
    await expectLater(player.start('k'), throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'NO_HOST_SCREEN')));
  });

  // case: SMV-1749 PIP isDragOutToCloseEnabled — 생략 시 키 없음(현재 값 유지), 읽기 형식 오류는 null(던지지 않음)
  test('pip.isDragOutToCloseEnabled omitted / wrong type on read', () async {
    await player.setConfiguration(const ShoplivePlayerConfiguration(pip: ShoplivePipOptions(isInAppPipEnabled: true)));
    expect(calls.single.arguments, {
      'configuration': {
        'pip': {'isInAppPipEnabled': true},
      },
    });
    responder = (_) => {
          'pip': {'isDragOutToCloseEnabled': 'yes'},
        };
    expect((await player.getConfiguration()).pip!.isDragOutToCloseEnabled, isNull);
  });
}
