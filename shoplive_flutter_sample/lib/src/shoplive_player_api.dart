import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shoplive_core/shoplive_core.dart';

import 'models/campaign_list.dart';
import 'platform/shoplive_player_method_channel.dart';
import 'platform/shoplive_player_platform_interface.dart';

/// Shoplive 서버 조회 API — 네이티브 Android·iOS `ShoplivePlayerAPI`와 같은 이름(SMV-1899 D10). 세션과 무관하다.
/// `Shoplive.initialize`로 accessKey를 정한 뒤 부른다.
abstract final class ShoplivePlayerAPI {
  /// 방송 목록을 조회한다. Future는 다음 중 하나로 정확히 1번 끝난다:
  /// - 성공: [ShopliveCampaignListResponse]
  /// - 실패: `PlatformException(code: 'SDK_ERROR')` — `details`는 [ShopliveError] wire라 `ShopliveError.tryParse(e.details)`로 읽고,
  ///   원인은 `rawCode`로 구분한다(-200 없는 키, -201 만료, -510 잘못된 인자, 9000 미초기화, 9900 네트워크, 9901 파싱)
  /// - 취소: [cancelToken]을 취소하면 네이티브 요청을 취소하고 `PlatformException(code: 'CANCELLED')`로 바로 끝난다. 그 뒤 도착한 응답은 버린다.
  /// - 인자 형식 오류: `INVALID_ARGUMENT`
  ///
  /// 플러그인은 대기 상한을 두지 않는다 — 무응답 상한은 네이티브 HTTP 설정(Android 호출 전체 30초, iOS 유휴 10초)을 따르고, 네이티브가
  /// 끝내 응답하지 않으면 끝나지 않을 수 있다. 필요하면 `Future.timeout`과 [ShopliveCancelToken.cancel]을 함께 쓴다.
  /// 동시 호출은 서로 독립이고 도착 순서는 보장하지 않는다 — 최신 요청의 결과를 고르는 것은 앱 몫이다.
  static Future<ShopliveCampaignListResponse> getCampaigns({
    ShopliveCampaignListRequest request = const ShopliveCampaignListRequest(),
    ShopliveCancelToken? cancelToken,
  }) {
    if (cancelToken?.isCancelled ?? false) return Future.error(_cancelled());
    final id = '$_idPrefix-${++_seq}';
    final completer = Completer<ShopliveCampaignListResponse>();
    void onCancel() {
      if (completer.isCompleted) return;
      completer.completeError(_cancelled());
      unawaited(_platform
          .invokeMethod<bool>(ShoplivePlayerContract.cancelGetCampaigns, {'requestId': id})
          .then<void>((_) {}, onError: (Object e) => debugPrint('ShoplivePlayerAPI: cancelGetCampaigns failed ${e.runtimeType}')));
    }

    cancelToken?._listeners.add(onCancel);
    _platform.invokeMethod<Object?>(ShoplivePlayerContract.getCampaigns, {'requestId': id, 'request': request.toWire()}).then(
      (raw) {
        if (completer.isCompleted) return; // 취소 뒤 도착 — 버린다
        final response = ShopliveCampaignListResponse.tryParse(raw);
        if (response == null) {
          completer.completeError(
              PlatformException(code: ShoplivePlatformErrorCode.sdkError, message: '${ShoplivePlayerContract.getCampaigns} returned malformed data'));
        } else {
          completer.complete(response);
        }
      },
      onError: (Object e, StackTrace s) {
        if (!completer.isCompleted) completer.completeError(e, s);
      },
    );
    return completer.future.whenComplete(() => cancelToken?._listeners.remove(onCancel));
  }

  static ShoplivePlayerPlatform get _platform => ShoplivePlayerPlatform.instance;

  /// 요청 id. 아이솔레이트마다 다른 접두사를 둔다 — 핫 리스타트 뒤에도 네이티브에 남은 이전 아이솔레이트의 미완료 id와 겹치지 않게
  /// (네이티브 플러그인은 핫 리스타트에 detach되지 않는다 — SMV-1899 D10-e).
  static final String _idPrefix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  static int _seq = 0;

  static PlatformException _cancelled() =>
      PlatformException(code: ShoplivePlatformErrorCode.cancelled, message: '${ShoplivePlayerContract.getCampaigns} cancelled');
}

/// [ShoplivePlayerAPI.getCampaigns] 취소 토큰. 하나를 여러 호출에 넘기면 [cancel] 한 번에 아직 끝나지 않은 호출이 모두 취소된다.
/// 한 번 취소한 토큰은 되돌릴 수 없다 — 그 토큰으로 새 호출을 하면 바로 취소로 끝난다.
final class ShopliveCancelToken {
  ShopliveCancelToken();

  final Set<void Function()> _listeners = {};
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// 여러 번 불러도 안전하다.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final l in listeners) {
      l();
    }
  }
}
