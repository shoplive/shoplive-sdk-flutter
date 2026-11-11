/// 채널 계약의 `PlatformException.code` 값(design.md rev2 §2.2). Dart API는 PlatformException을 그대로 전파한다.
abstract final class ShoplivePlatformErrorCode {
  /// 인자 누락·타입·미지 wire 값·범위·규칙 위반.
  static const String invalidArgument = 'INVALID_ARGUMENT';

  /// 플레이어/방송 화면을 띄울 앱 화면이 없음.
  static const String noHostScreen = 'NO_HOST_SCREEN';

  /// 실행 중인 플레이어 세션이 없음.
  static const String notRunning = 'NOT_RUNNING';

  /// SDK 호출 실패. getCampaigns의 SDK 실패는 `details`에 [ShopliveError] wire를 싣는다 — [ShopliveError.tryParse]로 읽는다.
  static const String sdkError = 'SDK_ERROR';

  /// 앱이 `ShopliveCancelToken`으로 취소한 요청(shoplive_player `ShoplivePlayerAPI.getCampaigns`).
  static const String cancelled = 'CANCELLED';
}

/// SDK Error 이벤트 payload(design.md rev2 §2.5 `error`).
///
/// [code]는 플랫폼별 값 공간이 다르므로 불투명 문자열이다(Android: SDK ErrorCode 상수명).
class ShopliveError {
  const ShopliveError({required this.code, required this.recoverable, this.message, this.rawCode});

  /// payload → ShopliveError. 계약 필수 필드(code·recoverable)가 없거나 형식이 다르면 null.
  /// 이벤트 스트림은 null을 받으면 unknown 이벤트로 폴백한다(스트림을 끊지 않음, pair #15).
  static ShopliveError? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final code = raw[_kCode];
    final recoverable = raw[_kRecoverable];
    if (code is! String || recoverable is! bool) return null;
    final message = raw[_kMessage];
    final rawCode = raw[_kRawCode];
    return ShopliveError(
      code: code,
      recoverable: recoverable,
      message: message is String ? message : null,
      rawCode: rawCode is int ? rawCode : null,
    );
  }

  static const String _kCode = 'code';
  static const String _kMessage = 'message';
  static const String _kRawCode = 'rawCode';
  static const String _kRecoverable = 'recoverable';

  final String code;
  final String? message;
  final int? rawCode;
  final bool recoverable;

  @override
  String toString() => 'ShopliveError(code: $code, rawCode: $rawCode, recoverable: $recoverable, message: $message)';
}
