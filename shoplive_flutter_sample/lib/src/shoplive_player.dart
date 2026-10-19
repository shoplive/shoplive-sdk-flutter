import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shoplive_core/shoplive_core.dart';

import 'models/play_options.dart';
import 'models/player_configuration.dart';
import 'models/player_enums.dart';
import 'models/player_event.dart';
import 'models/player_request.dart';
import 'platform/shoplive_player_method_channel.dart';
import 'platform/shoplive_player_platform_interface.dart';
import 'wire.dart';

/// 풀스크린 플레이어(design.md rev2 §2.4). 모든 메서드는 실패 시 PlatformException
/// (INVALID_ARGUMENT / NO_HOST_SCREEN / NOT_RUNNING / SDK_ERROR)을 던진다.
typedef _C = ShoplivePlayerContract;

class ShoplivePlayer {
  ShoplivePlayer._();

  static final ShoplivePlayer instance = ShoplivePlayer._();

  /// 테스트 전용: 상태(요청 구독)가 분리된 새 인스턴스.
  @visibleForTesting
  factory ShoplivePlayer.createForTesting() => ShoplivePlayer._();


  ShoplivePlayerPlatform get _platform => ShoplivePlayerPlatform.instance;

  /// 이 플러그인 패키지(shoplive_player)의 버전. pubspec.yaml의 version과 같아야 한다(테스트로 고정).
  static const String pluginVersion = '3.0.3';

  /// 1.8.x `getPluginVersion()` 대응. 플러그인 자체 값이라 네이티브를 거치지 않는다.
  Future<String> getPluginVersion() async => pluginVersion;

  // ---- 제어 ----

  /// [configuration]은 현재 설정 위에 병합된다. 생략하면 현재 설정으로 시작한다(CFG-01).
  /// presentationStyle=pip인데 병합 결과 pip.isInAppPipEnabled가 false면 INVALID_ARGUMENT(B-09).
  Future<void> start(String campaignKey, {ShoplivePlayOptions? playOptions, ShoplivePlayerConfiguration? configuration}) {
    final args = <String, Object?>{'campaignKey': campaignKey};
    putIfNotNull(args, 'playOptions', playOptions?.toWire());
    putIfNotNull(args, 'configuration', configuration?.toWire());
    return _invokeVoid(_C.start, args);
  }

  Future<void> play(String campaignKey, {ShoplivePlayOptions? playOptions}) {
    final args = <String, Object?>{'campaignKey': campaignKey};
    putIfNotNull(args, 'playOptions', playOptions?.toWire());
    return _invokeVoid(_C.play, args);
  }

  Future<void> stop() => _invokeVoid(_C.stop);

  /// 실행 중이 아니어도 성공한다(멱등).
  Future<void> close() => _invokeVoid(_C.close);

  Future<void> reload() => _invokeVoid(_C.reload);

  Future<void> send(String command, [Map<String, Object?>? payload]) {
    final args = <String, Object?>{'command': command};
    putIfNotNull(args, 'payload', payload);
    return _invokeVoid(_C.send, args);
  }

  /// 시작 시 음소거는 configuration.sound.muteOnStart를 쓴다(비실행 중 setMuted는 NOT_RUNNING).
  Future<void> setMuted(bool muted) => _invokeVoid(_C.setMuted, {'muted': muted});

  Future<bool> isMuted() => _invokeRequired<bool>(_C.isMuted);

  Future<void> setResizeMode(ShopliveResizeMode mode) => _invokeVoid(_C.setResizeMode, {'mode': toWire(mode)});

  Future<ShopliveResizeMode> getResizeMode() async =>
      parseWireEnum(ShopliveResizeMode.values, await _invokeRequired<String>(_C.getResizeMode), unknown: ShopliveResizeMode.unknown);

  Future<void> setOverlayUI(ShopliveOverlayUIMode mode) => _invokeVoid(_C.setOverlayUI, {'mode': toWire(mode)});

  Future<ShopliveOverlayUIMode> getOverlayUI() async =>
      parseWireEnum(ShopliveOverlayUIMode.values, await _invokeRequired<String>(_C.getOverlayUI), unknown: ShopliveOverlayUIMode.unknown);

  Future<void> enterPictureInPicture() => _invokeVoid(_C.enterPictureInPicture);

  Future<void> exitPictureInPicture() => _invokeVoid(_C.exitPictureInPicture);

  Future<bool> isInPictureInPicture() => _invokeRequired<bool>(_C.isInPictureInPicture);

  Future<ShoplivePlayerState> getState() async =>
      parseWireEnum(ShoplivePlayerState.values, await _invokeRequired<String>(_C.getState), unknown: ShoplivePlayerState.unknown);

  Future<ShopliveCampaignInfo?> getCurrentCampaign() async =>
      ShopliveCampaignInfo.tryParse(await _platform.invokeMethod<Object?>(_C.getCurrentCampaign));

  Future<bool> isRunning() => _invokeRequired<bool>(_C.isRunning);

  /// 현재 설정 위에 병합된다(CFG-01).
  Future<void> setConfiguration(ShoplivePlayerConfiguration configuration) =>
      _invokeVoid(_C.setConfiguration, {'configuration': configuration.toWire()});

  Future<ShoplivePlayerConfiguration> getConfiguration() async =>
      ShoplivePlayerConfiguration.fromWire(await _invokeRequired<Object>(_C.getConfiguration));

  /// 쿠폰·커스텀 요청 응답 대기 시간(기본 10초). 이후 들어오는 요청부터 적용. 0 이하는 INVALID_ARGUMENT.
  Future<void> setRequestTimeout(Duration timeout) => _invokeVoid(_C.setRequestTimeout, {'timeoutMs': timeout.inMilliseconds});

  // ---- 이벤트 ----

  Stream<ShoplivePlayerEvent>? _events;

  /// 플레이어 이벤트(design §2.5). 형식 오류·미지 이벤트는 [ShoplivePlayerUnknownEvent]로 온다(스트림을 끊지 않음).
  Stream<ShoplivePlayerEvent> get events => _events ??= _platform.events().map(ShoplivePlayerEvent.fromWire);

  // ---- 요청(design §2.7, X-10) ----

  late final StreamController<ShopliveNavigationRequest> _navigation = _requestController();
  late final StreamController<ShopliveCouponRequest> _coupons = _requestController();
  late final StreamController<ShopliveCustomWebActionRequest> _customActions = _requestController();
  StreamSubscription<Object?>? _nativeRequests;
  Timer? _cancelTimer;

  /// 상품·링크 이동 요청.
  Stream<ShopliveNavigationRequest> get navigationRequests => _navigation.stream;

  /// 쿠폰 받기 요청. 리스너가 없으면 즉시 폴백 응답, 있으면 [ShopliveCouponRequest.respond]를 기다리다 타임아웃 후 폴백.
  ///
  /// - 세션 동안 리스너를 유지하라 — 모든 요청 리스너가 사라지면 대기 중 요청은 폴백으로 끝난다.
  /// - 리스너가 여럿이면 **먼저 도착한 respond 하나만** 유효하다(나머지는 false).
  /// - 리스너가 동기적으로 throw하면 그 요청은 즉시 폴백 응답되고, 예외는 리스너의 Zone으로 전달된다.
  ///   async 리스너의 await 이후 예외는 잡지 않는다(응답하지 않으면 타임아웃 폴백).
  ///   `listen(...)`으로 등록한 onData만 보호한다 — 반환된 구독에 `onData`를 나중에 교체하면 그 핸들러의 예외는 보호되지 않는다.
  late final Stream<ShopliveCouponRequest> couponRequests =
      _GuardedRequestStream(_coupons.stream, (r) => _fallback(r.requestId));

  /// 커스텀 버튼 요청. 응답·예외 규칙은 [couponRequests]와 같다.
  late final Stream<ShopliveCustomWebActionRequest> customWebActionRequests =
      _GuardedRequestStream(_customActions.stream, (r) => _fallback(r.requestId));

  StreamController<T> _requestController<T>() =>
      StreamController<T>.broadcast(sync: true, onListen: _onRequestListen, onCancel: _onRequestCancel);

  bool get _anyRequestListener => _navigation.hasListener || _coupons.hasListener || _customActions.hasListener;

  void _onRequestListen() {
    // 지연 cancel 대기 중이면 타이머만 철회하고 네이티브는 재구독하지 않는다(R2-m2)
    _cancelTimer?.cancel();
    _cancelTimer = null;
    _nativeRequests ??= _platform.requests().listen(
          _onNativeRequest,
          onError: (Object e) => debugPrint('ShoplivePlayer: requests stream error ${e.runtimeType}'),
        );
  }

  void _onRequestCancel() {
    if (_anyRequestListener) return;
    _cancelTimer?.cancel();
    _cancelTimer = Timer(Duration.zero, () {
      _cancelTimer = null;
      if (_anyRequestListener) return;
      final sub = _nativeRequests;
      _nativeRequests = null;
      sub?.cancel();
    });
  }

  void _onNativeRequest(Object? raw) {
    final m = asStringMap(raw);
    final type = m?['type'];
    if (m == null || type is! String) {
      debugPrint('ShoplivePlayer: malformed request dropped');
      return;
    }
    final requestId = m['requestId'];
    switch (type) {
      case 'navigation':
        final url = m['url'];
        if (url is String && _navigation.hasListener) _navigation.add(ShopliveNavigationRequest(url: url));
      case 'coupon':
        final couponId = m['couponId'];
        if (requestId is! String) return _drop(type);
        if (couponId is! String || !_coupons.hasListener) return _fallback(requestId);
        _coupons.add(ShopliveCouponRequest(requestId: requestId, couponId: couponId, responder: _respondCoupon));
      case 'customWebAction':
        final id = m['id'];
        final actionType = m['actionType'];
        if (requestId is! String) return _drop(type);
        if (id is! String || actionType is! String || !_customActions.hasListener) return _fallback(requestId);
        _customActions.add(ShopliveCustomWebActionRequest(
          requestId: requestId,
          id: id,
          actionType: actionType,
          payload: m['payload'],
          responder: _respondCustomAction,
        ));
      default:
        // 미지 요청: requestId가 있으면 응답 대기를 남기지 않도록 폴백
        if (requestId is String) _fallback(requestId);
    }
  }

  void _drop(String type) => debugPrint('ShoplivePlayer: request without requestId dropped (type=$type)');

  void _fallback(String requestId) {
    unawaited(_platform
        .invokeMethod<bool>(_C.respondFallback, {'requestId': requestId})
        .then<void>((_) {}, onError: (Object e) => debugPrint('ShoplivePlayer: respondFallback failed ${e.runtimeType}')));
  }

  Future<bool> _respondCoupon(String requestId, ShopliveCouponResult result) async =>
      await _platform.invokeMethod<bool>(_C.respondCoupon, result.toWire(requestId)) ?? false;

  Future<bool> _respondCustomAction(String requestId, ShopliveCustomActionResult result) async =>
      await _platform.invokeMethod<bool>(_C.respondCustomAction, result.toWire(requestId)) ?? false;

  // ---- invoke 헬퍼 ----

  Future<void> _invokeVoid(String method, [Map<String, Object?>? args]) => _platform.invokeMethod<void>(method, args);

  /// 계약상 값이 있어야 하는 반환. null이면 PlatformException(SDK_ERROR)(pair #15).
  Future<T> _invokeRequired<T extends Object>(String method) async {
    final value = await _platform.invokeMethod<T>(method);
    if (value == null) {
      throw PlatformException(code: ShoplivePlatformErrorCode.sdkError, message: '$method returned null');
    }
    return value;
  }
}

/// 요청 스트림 래퍼: 사용자 onData가 동기적으로 throw하면 해당 요청을 폴백 응답하고 예외를 다시 던진다(pair #22).
/// (broadcast 컨트롤러는 리스너 예외를 add 호출자가 아니라 구독 Zone으로 보내므로 add를 감싸서는 잡을 수 없다 — 실측.)
class _GuardedRequestStream<T> extends Stream<T> {
  _GuardedRequestStream(this._source, this._onListenerError);

  final Stream<T> _source;
  final void Function(T request) _onListenerError;

  @override
  bool get isBroadcast => true;

  @override
  StreamSubscription<T> listen(void Function(T event)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final guarded = onData == null
        ? null
        : (T event) {
            try {
              onData(event);
            } catch (_) {
              _onListenerError(event);
              rethrow;
            }
          };
    return _source.listen(guarded, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}
