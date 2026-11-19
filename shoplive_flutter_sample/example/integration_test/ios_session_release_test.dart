// iOS: which SDK closed releases the plugin's player (SMV-1899 code cross-check M2). The SDK reports closed with its
// ShoplivePlayerView as the sender, so the plugin matches the closed by the delegate bridge that received it.
// Needs the network and the example default keys, like ios_smoke_start_test. Run:
// flutter test integration_test/ios_session_release_test.dart -d <simulator>
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shoplive_player/shoplive_player.dart';

const _accessKey = 'uv9CGthPzlvsInZerCw0'; // example default access key (example/lib/main.dart)
// HLS campaign of the SMV-1899 manual verification. On the simulator the player may stay in loading; the tests need no playing.
// A playable campaign with sound; override with --dart-define=SHOPLIVE_CAMPAIGN_KEY=<key> (G-02 needs playing).
const _campaignKey = String.fromEnvironment('SHOPLIVE_CAMPAIGN_KEY', defaultValue: 'aca9cb6f566c');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final player = ShoplivePlayer.instance;
  final states = <ShoplivePlayerStateChanged>[];
  late StreamSubscription<ShoplivePlayerEvent> sub;

  setUpAll(() async {
    await Shoplive.initialize(const ShopliveConfiguration(accessKey: _accessKey));
    sub = player.events.listen((e) {
      if (e is ShoplivePlayerStateChanged) states.add(e);
    });
  });
  tearDownAll(() => sub.cancel());

  String trace(int from) =>
      states.skip(from).map((e) => '${e.state.name}${e.closeReason == null ? '' : '/${e.closeReason!.name}'}').join(',');

  Future<void> until(String what, Future<bool> Function() done, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (await done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    fail('timed out after ${seconds}s waiting for $what (states: ${trace(0)})');
  }

  Future<void> untilState(int from, ShoplivePlayerState state, {int seconds = 30}) =>
      until('$state after #$from', () async => states.skip(from).any((e) => e.state == state), seconds: seconds);

  Future<PlatformException?> failureOf(Future<void> call) =>
      call.then<PlatformException?>((_) => null, onError: (Object e) => e as PlatformException);

  Iterable<ShoplivePlayerStateChanged> closedSince(int from) => states.skip(from).where((e) => e.state == ShoplivePlayerState.closed);

  testWidgets('M2: closed of a preview in in-app PIP releases the player, and the next start opens a new one', (_) async {
    addTearDown(player.close);
    var mark = states.length;
    await player.startPreview(_campaignKey, muteOnFullScreen: true);
    // SMV-2021 X-2: the SDK holds the delegate weakly - events after the adoption hop must still reach Dart.
    expect(await player.isRunning(), isTrue, reason: 'adopted when the Future completes (states: ${trace(mark)})');
    await untilState(mark, ShoplivePlayerState.inAppPip, seconds: 20);
    await Future<void>.delayed(const Duration(seconds: 3)); // let the presentation and the PIP entry settle
    expect(await player.isInPictureInPicture(), isTrue);

    mark = states.length;
    await player.close();
    await untilState(mark, ShoplivePlayerState.closed, seconds: 10); // delivered by the adopted session bridge
    final afterClose = 'state=${(await player.getState()).name} isRunning=${await player.isRunning()} states=${trace(mark)}';
    debugPrint('M2 PIP CLOSE: $afterClose');
    // Not on screen, so nothing dismisses it later: the closed itself must release it (before the fix getState stayed closed).
    expect(await player.getState(), ShoplivePlayerState.idle, reason: afterClose);
    expect(await player.isRunning(), isFalse);

    mark = states.length;
    await player.start(_campaignKey);
    await untilState(mark, ShoplivePlayerState.loading, seconds: 20);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(await player.isRunning(), isTrue);
    expect(states.skip(mark).where((e) => e.state == ShoplivePlayerState.closed), isEmpty,
        reason: 'no closed may follow the new start (states: ${trace(mark)})');

    mark = states.length;
    await player.close();
    await untilState(mark, ShoplivePlayerState.closed, seconds: 10);
    await until('release after the fullscreen close', () async => await player.getState() == ShoplivePlayerState.idle,
        seconds: 5);
  });

  testWidgets('G-02 / M2: reload sends no closed, stop keeps the stopped screen until close', (_) async {
    addTearDown(player.close);
    var mark = states.length;
    await player.start(_campaignKey);
    await untilState(mark, ShoplivePlayerState.playing, seconds: 30); // needs a playable campaign (see _campaignKey)

    // SDK 3.0.6 reload: loading -> playing in the same player, no closed (cross-check R-3: the order is asserted, not only
    // the absence of closed).
    mark = states.length;
    await player.reload();
    await untilState(mark, ShoplivePlayerState.playing, seconds: 30);
    final afterReload = 'isRunning=${await player.isRunning()} state=${(await player.getState()).name} states=${trace(mark)}';
    debugPrint('G-02 RELOAD: $afterReload');
    final reloaded = states.skip(mark).map((e) => e.state).toList();
    expect(closedSince(mark), isEmpty, reason: afterReload);
    expect(reloaded.indexOf(ShoplivePlayerState.loading), allOf(isNonNegative, lessThan(reloaded.lastIndexOf(ShoplivePlayerState.playing))),
        reason: afterReload);
    expect(await player.isRunning(), isTrue, reason: afterReload);
    await player.setMuted(true); // a session command still reaches the player (NOT_RUNNING otherwise)

    // stop in fullscreen: the SDK leaves the stopped screen to the app, so the plugin keeps it (closed, not running).
    mark = states.length;
    await player.stop();
    await untilState(mark, ShoplivePlayerState.closed, seconds: 10);
    final afterStop = 'state=${(await player.getState()).name} isRunning=${await player.isRunning()} states=${trace(mark)}';
    debugPrint('M2 STOP: $afterStop');
    expect(await player.isRunning(), isFalse);
    expect(await player.getState(), ShoplivePlayerState.closed, reason: afterStop);

    await player.close(); // the SDK dismisses the stopped screen; the plugin releases it on the dismissal
    await until('release after close of the stopped player', () async => await player.getState() == ShoplivePlayerState.idle,
        seconds: 5);
  });

  // case: P-08, P-10, U-3, X-7 (SMV-2021 D3) — while watching, startPreview changes nothing and each call ends with SDK_ERROR 9520.
  testWidgets('startPreview while watching ends with SDK_ERROR PREVIEW_IGNORED_WHILE_VIEWING and keeps the session', (_) async {
    addTearDown(player.close);
    var mark = states.length;
    await player.start(_campaignKey);
    await untilState(mark, ShoplivePlayerState.loading, seconds: 20);
    await Future<void>.delayed(const Duration(seconds: 2));
    final before = [await player.isRunning(), await player.isInPictureInPicture(), (await player.getCurrentCampaign())?.campaignKey];

    mark = states.length;
    // Two calls in a row (no await between): each Future gets its own 9520 (X-7).
    final calls = [failureOf(player.startPreview(_campaignKey)), failureOf(player.startPreview('other-key'))];
    final failures = await Future.wait(calls);
    for (final e in failures) {
      expect(e?.code, 'SDK_ERROR');
      final err = ShopliveError.tryParse(e!.details)!;
      expect([err.code, err.rawCode, err.recoverable], ['PREVIEW_IGNORED_WHILE_VIEWING', 9520, false]);
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    expect([await player.isRunning(), await player.isInPictureInPicture(), (await player.getCurrentCampaign())?.campaignKey], before);
    expect(closedSince(mark), isEmpty, reason: 'the watched session is untouched (states: ${trace(mark)})');
  });

  // case: P-04, T-04 (SMV-2021 D2) — the same key twice keeps the same preview: both Futures succeed, no closed.
  testWidgets('startPreview with the same key twice keeps the preview', (_) async {
    addTearDown(player.close);
    final mark = states.length;
    await Future.wait([player.startPreview(_campaignKey), player.startPreview(_campaignKey)]); // joined while waiting
    await untilState(mark, ShoplivePlayerState.inAppPip, seconds: 20);
    await player.startPreview(_campaignKey); // the adopted controller
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(await player.isInPictureInPicture(), isTrue);
    expect(closedSince(mark), isEmpty, reason: trace(mark));
  });

  // case: T-03 (SMV-2021 D8) — a close while startPreview waits for its hop wins: the Future succeeds and no preview stays.
  testWidgets('close while startPreview waits leaves no preview and the startPreview succeeds', (_) async {
    final mark = states.length;
    final preview = player.startPreview(_campaignKey);
    unawaited(player.close());
    await preview; // succeeds (D8)
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(await player.isRunning(), isFalse);
    expect(await player.isInPictureInPicture(), isFalse);
    expect(await player.getState(), ShoplivePlayerState.idle);
    expect(states.skip(mark).where((e) => e.state == ShoplivePlayerState.inAppPip), isEmpty, reason: trace(mark));
  });

  // case: T-03 × T-04 (cross-check R-1) — startPreview, a close, then startPreview again in one run loop: the later call wins,
  // so the preview stays (the close only cancels the call before it).
  testWidgets('startPreview after a close that came while an earlier startPreview waited keeps the preview', (_) async {
    addTearDown(player.close);
    final mark = states.length;
    final first = player.startPreview(_campaignKey);
    unawaited(player.close());
    final second = player.startPreview(_campaignKey);
    await Future.wait([first, second]);
    await untilState(mark, ShoplivePlayerState.inAppPip, seconds: 20);
    expect(await player.isInPictureInPicture(), isTrue, reason: trace(mark));
    expect(await player.isRunning(), isTrue, reason: trace(mark));
  });
}
