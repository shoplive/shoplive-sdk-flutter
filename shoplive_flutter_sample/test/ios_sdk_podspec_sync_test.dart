// case: I-D-05 (DRAFT-flutter-sdk-302-ios) — iOS SDK 다운로드 설정 동기화 검사(모노레포 전용 테스트).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // 테스트 작업 디렉토리 = shoplive_flutter_sample. 형제 패키지가 없으면 실패한다(skip 아님).
  final repo = Directory.current.parent.path;
  final podspecs = {
    'shoplive_core': '$repo/shoplive_core/ios/shoplive_core.podspec',
    'shoplive_player': '$repo/shoplive_flutter_sample/ios/shoplive_player.podspec',
    'shoplive_streamer': '$repo/shoplive_streamer/ios/shoplive_streamer.podspec',
  };
  final versionPattern = RegExp(r"^shoplive_ios_sdk_version = '([^']+)'", multiLine: true);
  final artifactPattern = RegExp(r"'(\w+)' => '([0-9a-f]{64})'");

  test('the three podspecs pin the same Shoplive iOS SDK version', () {
    final versions = {
      for (final e in podspecs.entries) e.key: versionPattern.firstMatch(File(e.value).readAsStringSync())?.group(1),
    };
    expect(versions.values.toSet(), {'3.0.3'}, reason: '$versions');
  });

  test('each XCFramework is owned by exactly one podspec (shared ones by shoplive_core)', () {
    final owners = <String, String>{};
    for (final e in podspecs.entries) {
      for (final m in artifactPattern.allMatches(File(e.value).readAsStringSync())) {
        expect(owners.containsKey(m.group(1)), isFalse, reason: '${m.group(1)} declared twice');
        owners[m.group(1)!] = e.key;
      }
    }
    expect(owners, {
      'ShopliveCore': 'shoplive_core',
      'ShopLiveWebRTCHelperSDK': 'shoplive_core',
      'WebRTC': 'shoplive_core',
      'ShoplivePlayerSDK': 'shoplive_player',
      'ShopliveStreamerSDK': 'shoplive_streamer',
    });
  });

  test('shoplive_ios_sdk.rb copies are identical', () {
    final copies = [
      '$repo/shoplive_core/ios/shoplive_ios_sdk.rb',
      '$repo/shoplive_flutter_sample/ios/shoplive_ios_sdk.rb',
      '$repo/shoplive_streamer/ios/shoplive_ios_sdk.rb',
    ].map((p) => File(p).readAsStringSync()).toSet();
    expect(copies.length, 1);
  });

  test('podspecs and the installer are ASCII-only', () {
    for (final p in [...podspecs.values, '$repo/shoplive_core/ios/shoplive_ios_sdk.rb']) {
      expect(File(p).readAsStringSync().codeUnits.every((c) => c < 128), isTrue, reason: p);
    }
  });
}
