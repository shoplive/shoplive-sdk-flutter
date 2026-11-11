import 'models/configuration.dart';
import 'models/conversion.dart';
import 'models/user.dart';
import 'platform/shoplive_core_platform_interface.dart';

/// Shoplive core API(design.md rev2 §2.4 shoplive_core). 모든 메서드는 실패 시 PlatformException을 던진다.
///
/// 초기화 전 호출을 브릿지가 막지 않는다 — SDK 동작에 위임(F-01).
abstract final class Shoplive {
  static ShopliveCorePlatform get _platform => ShopliveCorePlatform.instance;

  static Future<void> initialize(ShopliveConfiguration configuration) =>
      _platform.initialize(configuration.toWire());

  /// 떠 있는 플레이어가 있으면 영상·창은 그대로 두고 웹 오버레이만 새 신원으로 다시 읽는다(`reload()` 불필요). 같은 값 재설정은 무동작.
  /// iOS는 [ShopliveUser.token]과 [ShopliveUser.profile]이 서로를 지운다(하나를 설정하면 다른 하나가 비워짐).
  static Future<void> setUser(ShopliveUser user) => _platform.setUser(user.toWire());

  static Future<void> setStreamToken(String token) => _platform.setStreamToken(token);

  /// 떠 있는 플레이어가 있으면 웹 오버레이만 게스트로 다시 읽는다([setUser]와 같은 규칙).
  static Future<void> logout() => _platform.logout();

  static Future<void> sendConversionEvent(ShopliveConversionData data) =>
      _platform.sendConversionEvent(data.toWire());

  static Future<String> getSdkVersion() => _platform.getSdkVersion();
}
