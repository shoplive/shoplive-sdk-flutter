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

  // case: G-16 (R6-I1, SMV-1899 D10) — declared before group('core') so it runs before any initialize: without an accessKey the
  // SDK fails with 9000 without network, and the Future ends once with SDK_ERROR carrying the ShopliveError wire.
  testWidgets('getCampaigns before initialize ends with SDK_ERROR NOT_INITIALIZED_ACCESS_KEY', (_) async {
    final e = await ShoplivePlayerAPI.getCampaigns().then<PlatformException?>((_) => null, onError: (Object e) => e as PlatformException);
    expect(e?.code, 'SDK_ERROR');
    final err = ShopliveError.tryParse(e!.details)!;
    expect([err.code, err.rawCode], ['NOT_INITIALIZED_ACCESS_KEY', 9000]);
  });

  // case: P-12, U-3 (SMV-2021 D7) — replaces the SMV-1899 S-7 observation: before initialize the SDK 3.0.6 refuses the preview
  // (9000 on the next main run loop) and the Future ends once with SDK_ERROR carrying it. Nothing opens, and the refusal is the
  // call's result only - it is not also sent as an error event.
  testWidgets('startPreview before initialize ends with SDK_ERROR NOT_INITIALIZED_ACCESS_KEY and opens nothing', (_) async {
    final errors = <ShopliveError>[];
    final sub = player.events.listen((e) {
      if (e is ShoplivePlayerErrorEvent) errors.add(e.error);
    });
    final e = await player.startPreview('not-initialized-key').then<PlatformException?>((_) => null, onError: (Object e) => e as PlatformException);
    expect(e?.code, 'SDK_ERROR');
    final err = ShopliveError.tryParse(e!.details)!;
    expect([err.code, err.rawCode, err.recoverable], ['NOT_INITIALIZED_ACCESS_KEY', 9000, false]);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(await player.isRunning(), isFalse);
    expect(await player.isInPictureInPicture(), isFalse);
    expect(await player.getState(), ShoplivePlayerState.idle);
    expect(errors, isEmpty);
    await sub.cancel();
  });

  // case: P-16 (SMV-2021 D1) — muteOnFullScreen is a Bool or omitted; anything else is rejected before the SDK
  testWidgets('startPreview muteOnFullScreen that is not a Bool is INVALID_ARGUMENT', (_) async {
    await expectLater(
      const MethodChannel('shoplive_player').invokeMethod<void>('startPreview', {'campaignKey': 'k', 'muteOnFullScreen': 'x'}),
      _platformError('INVALID_ARGUMENT'),
    );
    expect(await player.isRunning(), isFalse);
  });

  // case: G-6 (R6-I1) — 32-bit page/size like Android, rejected before the SDK call
  testWidgets('getCampaigns page out of 32-bit range is INVALID_ARGUMENT', (_) async {
    await expectLater(ShoplivePlayerAPI.getCampaigns(request: const ShopliveCampaignListRequest(page: 1 << 33)), _platformError('INVALID_ARGUMENT'));
  });

  group('core', () {
    // case: N-01
    testWidgets('getSdkVersion returns the iOS SDK version', (_) async {
      expect(await Shoplive.getSdkVersion(), '3.0.6');
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
      // case: C-05, C-02 (SMV-2021 D5) — SDK 3.0.6 defaults: resizeMode .default = auto (not unknown), muteOnFullScreen false
      expect(await player.getResizeMode(), ShopliveResizeMode.auto);
      expect((await player.getConfiguration()).sound!.muteOnFullScreen, isFalse);
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

    // case: C-01, C-04 (SMV-2021 D1·D4) — sound.muteOnFullScreen round-trips (omitted keeps it); pip.aspectRatio auto is accepted
    // (iOS validates the ratio but does not apply it, so getConfiguration has no aspectRatio)
    testWidgets('sound.muteOnFullScreen round-trips and pip.aspectRatio auto is accepted', (_) async {
      await player.setConfiguration(const ShoplivePlayerConfiguration(sound: ShopliveSoundOptions(muteOnFullScreen: true)));
      expect((await player.getConfiguration()).sound!.muteOnFullScreen, isTrue);
      await player.setConfiguration(const ShoplivePlayerConfiguration(sound: ShopliveSoundOptions(muteOnStart: false)));
      expect((await player.getConfiguration()).sound!.muteOnFullScreen, isTrue);
      await expectLater(
        const MethodChannel('shoplive_player').invokeMethod<void>('setConfiguration', {
          'configuration': {
            'sound': {'muteOnFullScreen': 'yes'},
          },
        }),
        _platformError('INVALID_ARGUMENT'),
      );
      await player.setConfiguration(const ShoplivePlayerConfiguration(sound: ShopliveSoundOptions(muteOnFullScreen: false)));
      expect((await player.getConfiguration()).sound!.muteOnFullScreen, isFalse);
      await player.setConfiguration(const ShoplivePlayerConfiguration(pip: ShoplivePipOptions(aspectRatio: ShoplivePipRatio.auto)));
      expect((await player.getConfiguration()).pip!.aspectRatio, isNull);
    });

    // case: C-05, S-04 (SMV-2021 D5) — auto (wire 'default') is SDK 3.0.6 .default and reads back as auto
    testWidgets('resizeMode auto stays auto on iOS', (_) async {
      await player.setResizeMode(ShopliveResizeMode.auto);
      expect(await player.getResizeMode(), ShopliveResizeMode.auto);
      await player.setResizeMode(ShopliveResizeMode.fill);
      expect(await player.getResizeMode(), ShopliveResizeMode.fill);
      await player.setResizeMode(ShopliveResizeMode.fit);
      expect(await player.getResizeMode(), ShopliveResizeMode.fit);
      await expectLater(player.setResizeMode(ShopliveResizeMode.unknown), _platformError('INVALID_ARGUMENT'));
    });

    // case: S-5 (R6-I1, SMV-1899 D11-d) — blank / whitespace key is rejected before the SDK
    testWidgets('startPreview blank key is INVALID_ARGUMENT', (_) async {
      await expectLater(player.startPreview(''), _platformError('INVALID_ARGUMENT'));
      await expectLater(player.startPreview('  '), _platformError('INVALID_ARGUMENT'));
      expect(await player.isRunning(), isFalse);
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

    // case: A2-4 (R-I1, SMV-1899) — isCustomShareEnabled round-trip, omitted keeps the value, key+null / non-Bool INVALID_ARGUMENT
    testWidgets('navigation.isCustomShareEnabled round-trips and validates', (_) async {
      await player.setConfiguration(const ShoplivePlayerConfiguration(navigation: ShopliveNavigationOptions(isCustomShareEnabled: true)));
      expect((await player.getConfiguration()).navigation!.isCustomShareEnabled, isTrue);
      await player.setConfiguration(const ShoplivePlayerConfiguration(navigation: ShopliveNavigationOptions(shareScheme: 'app://s')));
      expect((await player.getConfiguration()).navigation!.isCustomShareEnabled, isTrue);
      const channel = MethodChannel('shoplive_player');
      for (final bad in <Object?>[null, 'yes']) {
        await expectLater(
          channel.invokeMethod<void>('setConfiguration', {
            'configuration': {
              'navigation': {'isCustomShareEnabled': bad},
            },
          }),
          _platformError('INVALID_ARGUMENT'),
        );
      }
      expect((await player.getConfiguration()).navigation!.isCustomShareEnabled, isTrue); // rejected calls change nothing
      await player.setConfiguration(const ShoplivePlayerConfiguration(navigation: ShopliveNavigationOptions(isCustomShareEnabled: false)));
      expect((await player.getConfiguration()).navigation!.isCustomShareEnabled, isFalse);
    });

    // case: A3-2·A3-3·A3-6 (R-I1, SMV-1899) — button isHidden round-trip, unknown nativeImageName still succeeds, wrong types INVALID_ARGUMENT
    testWidgets('pip buttons round-trip and validate', (_) async {
      await player.setConfiguration(const ShoplivePlayerConfiguration(
        pip: ShoplivePipOptions(
          closeButton: ShopliveButtonOptions(isHidden: true),
          restoreButton: ShopliveButtonOptions(nativeImageName: 'sample_pip_restore'),
        ),
      ));
      var pip = (await player.getConfiguration()).pip!;
      expect(pip.closeButton!.isHidden, isTrue);
      expect(pip.restoreButton!.isHidden, isFalse);
      expect(pip.restoreButton!.nativeImageName, isNull); // write-only
      // An image name that does not resolve (or a Flutter asset path) is not an error: log + no image.
      for (final name in ['no_such_image', 'assets/close.png', '']) {
        await player.setConfiguration(ShoplivePlayerConfiguration(pip: ShoplivePipOptions(closeButton: ShopliveButtonOptions(nativeImageName: name))));
      }
      pip = (await player.getConfiguration()).pip!;
      expect(pip.closeButton!.isHidden, isTrue); // omitted isHidden keeps the value
      const channel = MethodChannel('shoplive_player');
      for (final bad in <Map<String, Object?>>[
        {'closeButton': null},
        {'closeButton': 'x'},
        {'restoreButton': {'isHidden': null}},
        {'restoreButton': {'isHidden': 'yes'}},
        {'closeButton': {'nativeImageName': 3}},
      ]) {
        await expectLater(
          channel.invokeMethod<void>('setConfiguration', {'configuration': {'pip': bad}}),
          _platformError('INVALID_ARGUMENT'),
        );
      }
      await player.setConfiguration(const ShoplivePlayerConfiguration(
        pip: ShoplivePipOptions(closeButton: ShopliveButtonOptions(isHidden: false), restoreButton: ShopliveButtonOptions(isHidden: false)),
      ));
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
