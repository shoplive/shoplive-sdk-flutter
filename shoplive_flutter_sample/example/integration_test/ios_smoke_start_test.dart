// Smoke: launch the sample app and tap "LivePlayer PLAY" (example default keys); the player view controller should
// appear and the app must not crash. A host script takes the simulator screenshot after "SMOKE_STARTED" is printed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shoplive_player/shoplive_player.dart';
import 'package:shoplive_player_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LivePlayer PLAY presents the player without crashing', (tester) async {
    final events = <ShoplivePlayerEvent>[];
    final sub = ShoplivePlayer.instance.events.listen(events.add);
    app.main();
    await tester.pumpAndSettle();
    await tester.tap(find.text('LivePlayer PLAY'));
    await tester.pump(const Duration(seconds: 2));
    debugPrint('SMOKE_STARTED');
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final running = await ShoplivePlayer.instance.isRunning();
    final state = await ShoplivePlayer.instance.getState();
    debugPrint('SMOKE_RESULT running=$running state=${state.name} events=${events.map((e) => e.runtimeType).toSet()}');
    expect(running, isTrue);
    // R-I2 (SMV-1899 A4-1, D6 non-regression): the current session's closed must reach Dart with closeReason appRequest -
    // the bridge's retired mark is set only on replacement, never on the current bridge.
    final closedBefore = events.length;
    await ShoplivePlayer.instance.close();
    List<ShoplivePlayerStateChanged> closedAfter() => events
        .skip(closedBefore)
        .whereType<ShoplivePlayerStateChanged>()
        .where((e) => e.state == ShoplivePlayerState.closed)
        .toList();
    for (var i = 0; i < 10 && closedAfter().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump(const Duration(seconds: 1)); // let a duplicate closed show up, if any
    final closed = closedAfter();
    debugPrint('SMOKE_CLOSED count=${closed.length} reasons=${closed.map((e) => e.closeReason?.name).toList()} '
        'eventsAfterClose=${events.skip(closedBefore).map((e) => e.runtimeType).toList()}');
    expect(closed.length, 1,
        reason: 'expected exactly one stateChanged(closed) within 10s after close() - 0 means the current bridge dropped it '
            '(D6 retired set on the wrong path?) or the SDK did not report it; >1 means a duplicate closed');
    expect(closed.single.closeReason, ShopliveCloseReason.appRequest, reason: 'close() is an app request (SMV-1899 A4)');
    await sub.cancel();
  });
}
