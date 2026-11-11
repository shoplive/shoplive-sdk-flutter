// S-7 observation (SMV-1899): what the iOS SDK 3.0.5 does when the startPreview emulation starts without an accessKey.
// It records the facts and never judges them (TODO(SDP-VERIFY) S-7 stays until a developer confirms on a device).
// A separate file so the presented player cannot disturb ios_contract_test. Run:
// flutter test integration_test/ios_preview_observation_test.dart -d <simulator>
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shoplive_player/shoplive_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final player = ShoplivePlayer.instance;

  testWidgets('S-7 observation: startPreview before initialize', (_) async {
    final events = <String>[];
    final sub = player.events.listen((e) => events.add(switch (e) {
          ShoplivePlayerStateChanged(:final state, :final closeReason) => 'state:${state.name}${closeReason == null ? '' : '/${closeReason.name}'}',
          ShoplivePlayerErrorEvent(:final error) => 'error:${error.code}/${error.rawCode}',
          _ => e.runtimeType.toString(),
        }));
    Object? startResult = 'ok';
    try {
      await player.startPreview('observation-key');
    } catch (e) {
      startResult = e;
    }
    await Future<void>.delayed(const Duration(seconds: 4));
    final facts = 'start=$startResult isRunning=${await player.isRunning()} inPip=${await player.isInPictureInPicture()} '
        'state=${(await player.getState()).name} events=$events';
    debugPrint('S-7 OBSERVATION: $facts');
    await player.close();
    await Future<void>.delayed(const Duration(seconds: 1));
    await sub.cancel();
  });
}
