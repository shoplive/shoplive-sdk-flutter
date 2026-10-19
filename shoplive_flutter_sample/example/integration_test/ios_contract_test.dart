// iOS bridge contract checks on a simulator (DRAFT-flutter-sdk-302-ios design D-10).
// Deterministic paths only: no network-dependent playback. Run: flutter test integration_test/ios_contract_test.dart -d <simulator>
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shoplive_player/shoplive_player.dart';
import 'package:shoplive_streamer/shoplive_streamer.dart' show ShopliveStreamer, ShopliveBroadcastState;

Matcher _platformError(String code) => throwsA(isA<PlatformException>().having((e) => e.code, 'code', code));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final player = ShoplivePlayer.instance;

  group('core', () {
    // case: N-01
    testWidgets('getSdkVersion returns the iOS SDK version', (_) async {
      expect(await Shoplive.getSdkVersion(), '3.0.3');
    });

    // case: F-04
    testWidgets('blank accessKey / profile id -> INVALID_ARGUMENT', (_) async {
      await expectLater(Shoplive.initialize(const ShopliveConfiguration(accessKey: ' ')), _platformError('INVALID_ARGUMENT'));
      await expectLater(Shoplive.setUser(const ShopliveUser.profile(id: '')), _platformError('INVALID_ARGUMENT'));
    });

    // case: N-01, I-B-01 (D-3: appVersion / profile.custom ignored on iOS; appVersion ignored on both since 3.0.3 — SMV-1749)
    testWidgets('initialize and setUser with Android-only fields succeed', (_) async {
      // ignore: deprecated_member_use
      await Shoplive.initialize(const ShopliveConfiguration(accessKey: 'uv9CGthPzlvsInZerCw0', appVersion: '1.0.0'));
      await Shoplive.setUser(const ShopliveUser.profile(id: 'u1', gender: ShopliveGender.female, custom: {'k': 'v'}));
      await Shoplive.setUser(const ShopliveUser.guest());
      await Shoplive.sendConversionEvent(const ShopliveConversionData(type: 'purchase', products: []));
    });
  });

  group('player without a session', () {
    // case: F-02, NR-01
    testWidgets('queries return defaults, close is a no-op, session commands are NOT_RUNNING', (_) async {
      expect(await player.getState(), ShoplivePlayerState.idle);
      expect(await player.isRunning(), isFalse);
      expect(await player.isMuted(), isFalse);
      expect(await player.getCurrentCampaign(), isNull);
      await player.close();
      await expectLater(player.play('k'), _platformError('NOT_RUNNING'));
      await expectLater(player.setMuted(true), _platformError('NOT_RUNNING'));
      await expectLater(player.enterPictureInPicture(), _platformError('NOT_RUNNING'));
    });

    // case: CFG-01, CFG-02, D-2
    testWidgets('setConfiguration merges and getConfiguration round-trips', (_) async {
      await player.setConfiguration(const ShoplivePlayerConfiguration(
        pip: ShoplivePipOptions(isInAppPipEnabled: true, padding: ShopliveInsets(top: 12)),
        sound: ShopliveSoundOptions(muteOnStart: true),
        appearance: ShopliveAppearanceOptions(indicatorColor: 0xFF00FF00),
        navigation: ShopliveNavigationOptions(shareScheme: 'app://share'),
        customParameters: {'a': 'b'},
        android: ShopliveAndroidPlayerOptions(isStatusBarVisible: false),
      ));
      await player.setResizeMode(ShopliveResizeMode.fit);
      final c = await player.getConfiguration();
      expect(c.pip!.isInAppPipEnabled, isTrue);
      expect(c.pip!.padding!.top, 12);
      expect(c.sound!.muteOnStart, isTrue);
      expect(c.appearance!.indicatorColor, 0xFF00FF00);
      expect(c.navigation!.shareScheme, 'app://share');
      expect(c.customParameters, {'a': 'b'});
      expect(c.type, ShoplivePlayerType.live);
      expect(await player.getResizeMode(), ShopliveResizeMode.fit);
      await player.setConfiguration(const ShoplivePlayerConfiguration(type: ShoplivePlayerType.preview));
      expect((await player.getConfiguration()).type, ShoplivePlayerType.preview);
      await player.setConfiguration(const ShoplivePlayerConfiguration(type: ShoplivePlayerType.live));
    });

    // case: D-2, IM-m1 — same type keeps the other fields (Android parity); a different type rebuilds from the preset
    testWidgets('type: same value keeps fields, different value switches preset', (_) async {
      await player.setConfiguration(const ShoplivePlayerConfiguration(type: ShoplivePlayerType.live));
      await player.setConfiguration(const ShoplivePlayerConfiguration(sound: ShopliveSoundOptions(muteOnStart: true)));
      await player.setConfiguration(const ShoplivePlayerConfiguration(type: ShoplivePlayerType.live));
      expect((await player.getConfiguration()).sound!.muteOnStart, isTrue);
      await player.setConfiguration(const ShoplivePlayerConfiguration(type: ShoplivePlayerType.preview));
      expect((await player.getConfiguration()).type, ShoplivePlayerType.preview);
      await player.setConfiguration(const ShoplivePlayerConfiguration(type: ShoplivePlayerType.live));
      expect((await player.getConfiguration()).type, ShoplivePlayerType.live);
    });

    // case: B-09, B-08, N-06
    testWidgets('validation errors', (_) async {
      await player.setConfiguration(const ShoplivePlayerConfiguration(pip: ShoplivePipOptions(isInAppPipEnabled: false)));
      await expectLater(
        player.start('k', playOptions: const ShoplivePlayOptions(presentationStyle: ShoplivePresentationStyle.pip)),
        _platformError('INVALID_ARGUMENT'),
      );
      await expectLater(player.setRequestTimeout(const Duration(milliseconds: 999)), _platformError('INVALID_ARGUMENT'));
      await player.setRequestTimeout(const Duration(seconds: 10));
      await expectLater(player.setResizeMode(ShopliveResizeMode.unknown), _platformError('INVALID_ARGUMENT'));
      expect(await const MethodChannel('shoplive_player').invokeMethod<bool>('respondFallback', {'requestId': 'nope'}), isFalse);
    });
  });

  group('streamer', () {
    // case: ST-01
    testWidgets('getState without a session is idle; blank key is INVALID_ARGUMENT', (_) async {
      expect(await ShopliveStreamer.instance.getState(), ShopliveBroadcastState.idle);
      await expectLater(ShopliveStreamer.instance.start(''), _platformError('INVALID_ARGUMENT'));
    });
  });
}
