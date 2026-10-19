import 'package:meta/meta.dart';
import '../wire.dart';
import 'player_enums.dart';

/// 쿠폰·커스텀 액션 응답(design §2.4 respondCoupon/respondCustomAction). [status]는 계약상 필수.
class ShopliveCouponResult {
  const ShopliveCouponResult({required this.success, required this.status, this.message, this.alertType});

  final bool success;
  final ShopliveResultStatus status;
  final String? message;

  /// 생략하면 Android·iOS 모두 [ShopliveResultAlertType.toast].
  final ShopliveResultAlertType? alertType;

  @internal
  Map<String, Object?> toWire(String requestId) => _resultWire(requestId, success, status, message, alertType);
}

class ShopliveCustomActionResult {
  const ShopliveCustomActionResult({required this.success, required this.status, this.message, this.alertType});

  final bool success;
  final ShopliveResultStatus status;
  final String? message;

  /// 생략하면 Android·iOS 모두 [ShopliveResultAlertType.toast].
  final ShopliveResultAlertType? alertType;

  @internal
  Map<String, Object?> toWire(String requestId) => _resultWire(requestId, success, status, message, alertType);
}

Map<String, Object?> _resultWire(String requestId, bool success, Enum status, String? message, Enum? alertType) {
  final m = <String, Object?>{'requestId': requestId, 'success': success, 'status': toWire(status)};
  putIfNotNull(m, 'message', message);
  putIfNotNull(m, 'alertType', alertType == null ? null : toWire(alertType));
  return m;
}

typedef ShopliveRequestResponder<R> = Future<bool> Function(String requestId, R result);

/// 상품·링크 이동 요청. 응답 없음.
class ShopliveNavigationRequest {
  const ShopliveNavigationRequest({required this.url});
  final String url;
}

/// 쿠폰 받기 요청. [respond]는 1회만 유효하다(C-4).
///
/// [respond]가 false를 돌려주는 경우(사유는 구분하지 않음): 응답 대기 시간 초과로 이미 폴백 응답됨 /
/// 같은 요청에 이미 응답함(다른 리스너 포함) / 플러그인 엔진 detach 또는 요청 리스너 해제로 폴백 처리됨.
class ShopliveCouponRequest {
  ShopliveCouponRequest({required this.requestId, required this.couponId, required ShopliveRequestResponder<ShopliveCouponResult> responder})
      : _responder = responder;

  final String requestId;
  final String couponId;
  final ShopliveRequestResponder<ShopliveCouponResult> _responder;

  Future<bool> respond(ShopliveCouponResult result) => _responder(requestId, result);
}

/// 커스텀 버튼 요청. [respond]는 1회만 유효하며 false 사유는 [ShopliveCouponRequest]와 같다(C-4).
class ShopliveCustomWebActionRequest {
  ShopliveCustomWebActionRequest({
    required this.requestId,
    required this.id,
    required this.actionType,
    required this.payload,
    required ShopliveRequestResponder<ShopliveCustomActionResult> responder,
  }) : _responder = responder;

  final String requestId;
  final String id;
  final String actionType;
  final Object? payload;
  final ShopliveRequestResponder<ShopliveCustomActionResult> _responder;

  Future<bool> respond(ShopliveCustomActionResult result) => _responder(requestId, result);
}
