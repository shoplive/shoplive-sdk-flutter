// iOS: which SDK closed releases the plugin's player (SMV-1899 code cross-check M2). The SDK reports closed with its
// ShoplivePlayerView as the sender, so the plugin matches the closed by the delegate bridge that received it.
// Needs the network and the example default keys, like ios_smoke_start_test. Run:
// flutter test integration_test/ios_session_release_test.dart -d <simulator>
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shoplive_player/shoplive_player.dart';

const _accessKey = 'uv9CGthPzlvsInZerCw0'; // example default access key (example/lib/main.dart)
// HLS campaign of the SMV-1899 manual verification. On the simulator the player may stay in loading; the tests need no playing.
const _campaignKey = 'aca9cb6f566c';

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

  testWidgets('M2: closed of a preview in in-app PIP releases the player, and the next start opens a new one', (_) async {
    addTearDown(player.close);
    var mark = states.length;
    await player.startPreview(_campaignKey);
    await untilState(mark, ShoplivePlayerState.inAppPip, seconds: 20);
    await Future<void>.delayed(const Duration(seconds: 3)); // let the presentation and the PIP entry settle

    mark = states.length;
    await player.close();
    await untilState(mark, ShoplivePlayerState.closed, seconds: 10);
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

  testWidgets('M2 / A0-6: reload keeps the player, stop keeps the stopped screen until close', (_) async {
    addTearDown(player.close);
    var mark = states.length;
    await player.start(_campaignKey);
    await untilState(mark, ShoplivePlayerState.loading, seconds: 20);
    await Future<void>.delayed(const Duration(seconds: 2));

    // SDK reload = stop + play in the same view controller (fullscreen); its closed(appRequest) must not release the player.
    mark = states.length;
    await player.reload();
    await until('closed then loading after reload', () async {
      final after = states.skip(mark).toList();
      final closedAt = after.indexWhere((e) => e.state == ShoplivePlayerState.closed);
      return closedAt >= 0 && after.skip(closedAt + 1).any((e) => e.state == ShoplivePlayerState.loading);
    }, seconds: 15);
    final afterReload = 'isRunning=${await player.isRunning()} state=${(await player.getState()).name} states=${trace(mark)}';
    debugPrint('A0-6 RELOAD: $afterReload');
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
}
