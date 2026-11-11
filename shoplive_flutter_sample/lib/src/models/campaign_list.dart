/// 방송(캠페인) 목록 조회 모델(SDK 3.0.6 Android · 3.0.5 iOS `ShoplivePlayerAPI.getCampaigns` — SMV-1899 D10).
/// 새 공개 타입은 `final`이다 — 앱이 implements하지 않으므로 필드를 더해도 앱 코드가 깨지지 않는다.
library;

import 'package:meta/meta.dart';

import '../wire.dart' as wire;

/// 요청 필터 상태. 응답 표기 상태([ShopliveCampaignLifecycleStatus])와 달리 3종만 있다.
/// [ready]는 예정·대기·리허설 중(응답에는 reserved가 섞일 수 있다), [onAir]는 방송 중(종료 진행 중 포함), [closed]는 다시보기 가능한 종료 방송.
enum ShopliveCampaignListStatus { ready, onAir, closed }

/// `scheduledAt` 기준 정렬.
enum ShopliveCampaignListOrder { ascending, descending }

/// 목록 조회 조건. 값을 주지 않은 조건은 SDK·서버 기본값을 쓴다.
final class ShopliveCampaignListRequest {
  const ShopliveCampaignListRequest({this.page, this.size, this.statuses = const [], this.order});

  /// 1부터. null이면 1, 1 미만은 1로 보정된다(SDK 규칙 — 오류 아님).
  final int? page;

  /// 페이지당 개수 1~20. null이면 10, 범위 밖은 범위 안으로 보정된다(SDK 규칙 — 오류 아님).
  final int? size;

  /// 비어 있으면 전체.
  final List<ShopliveCampaignListStatus> statuses;

  /// null이면 [ShopliveCampaignListOrder.descending](최신순).
  final ShopliveCampaignListOrder? order;

  @internal
  Map<String, Object?> toWire() {
    final m = <String, Object?>{'statuses': [for (final s in statuses) wire.toWire(s)]};
    wire.putIfNotNull(m, 'page', page);
    wire.putIfNotNull(m, 'size', size);
    wire.putIfNotNull(m, 'order', order == null ? null : wire.toWire(order!));
    return m;
  }
}

/// 목록 조회 결과. [hasMore]가 true면 다음 page가 있다.
final class ShopliveCampaignListResponse {
  const ShopliveCampaignListResponse({required this.campaigns, required this.hasMore});

  final List<ShopliveCampaignListItem> campaigns;
  final bool hasMore;

  /// 네이티브 회신 → 응답. 필수 필드가 하나라도 틀리면 null(호출자가 SDK_ERROR로 끝낸다 — 항목만 빼면 페이징이 어긋난다).
  @internal
  static ShopliveCampaignListResponse? tryParse(Object? raw) {
    final m = wire.asStringMap(raw);
    final list = m?['campaigns'];
    final hasMore = m?['hasMore'];
    if (list is! List || hasMore is! bool) return null;
    final items = <ShopliveCampaignListItem>[];
    for (final e in list) {
      final item = ShopliveCampaignListItem._tryParse(e);
      if (item == null) return null;
      items.add(item);
    }
    return ShopliveCampaignListResponse(campaigns: List.unmodifiable(items), hasMore: hasMore);
  }
}

/// 목록의 방송 하나. 시각은 UTC [DateTime]이다(네이티브는 epoch ms).
final class ShopliveCampaignListItem {
  const ShopliveCampaignListItem({
    required this.campaignId,
    required this.campaignKey,
    this.title,
    this.description,
    required this.campaignUrl,
    required this.rerun,
    required this.archiveStream,
    required this.privateLive,
    this.scheduledAt,
    this.scheduledEndAt,
    this.posterUrl,
    required this.lifecycle,
    this.metrics,
  });

  final int campaignId;

  /// 재생(`ShoplivePlayer.start`)에 쓰는 키.
  final String campaignKey;
  final String? title;
  final String? description;
  final String campaignUrl;
  final bool rerun;
  final bool archiveStream;

  /// 프라이빗 방송 여부 — 노출 판단은 앱 몫이다.
  final bool privateLive;
  final DateTime? scheduledAt;
  final DateTime? scheduledEndAt;
  final String? posterUrl;
  final ShopliveCampaignLifecycle lifecycle;

  /// onAir·closed에서만 있다.
  final ShopliveCampaignMetrics? metrics;

  static ShopliveCampaignListItem? _tryParse(Object? raw) {
    final m = wire.asStringMap(raw);
    if (m == null) return null;
    final campaignId = m['campaignId'], campaignKey = m['campaignKey'], campaignUrl = m['campaignUrl'];
    final rerun = m['rerun'], archiveStream = m['archiveStream'], privateLive = m['privateLive'];
    final lifecycle = ShopliveCampaignLifecycle._tryParse(m['lifecycle']);
    if (campaignId is! int || campaignKey is! String || campaignUrl is! String || rerun is! bool || archiveStream is! bool ||
        privateLive is! bool || lifecycle == null) {
      return null;
    }
    return ShopliveCampaignListItem(
      campaignId: campaignId,
      campaignKey: campaignKey,
      title: wire.asType<String>(m['title']),
      description: wire.asType<String>(m['description']),
      campaignUrl: campaignUrl,
      rerun: rerun,
      archiveStream: archiveStream,
      privateLive: privateLive,
      scheduledAt: _utc(m['scheduledAt']),
      scheduledEndAt: _utc(m['scheduledEndAt']),
      posterUrl: wire.asType<String>(m['posterUrl']),
      lifecycle: lifecycle,
      metrics: ShopliveCampaignMetrics._tryParse(m['metrics']),
    );
  }
}

/// 방송 진행 상태.
final class ShopliveCampaignLifecycle {
  const ShopliveCampaignLifecycle({required this.status, required this.rehearsal, this.startedAt, this.closingAt, this.endedAt});

  /// 리허설 중은 [ShopliveCampaignLifecycleReady], 종료 진행 중은 [ShopliveCampaignLifecycleOnAir]로 표기된다.
  final ShopliveCampaignLifecycleStatus status;

  /// 리허설 여부 — 리허설 중은 status가 ready라 이 값으로 구분한다.
  final bool rehearsal;
  final DateTime? startedAt;

  /// onAir에서 값이 있으면 종료 진행 중이다.
  final DateTime? closingAt;
  final DateTime? endedAt;

  static ShopliveCampaignLifecycle? _tryParse(Object? raw) {
    final m = wire.asStringMap(raw);
    final rehearsal = m?['rehearsal'];
    if (m == null || rehearsal is! bool) return null;
    return ShopliveCampaignLifecycle(
      status: ShopliveCampaignLifecycleStatus._fromWire(m['status'], m['unknownStatus']),
      rehearsal: rehearsal,
      startedAt: _utc(m['startedAt']),
      closingAt: _utc(m['closingAt']),
      endedAt: _utc(m['endedAt']),
    );
  }
}

/// 서버 표기 상태. 이 플러그인 버전이 모르는 값은 [ShopliveCampaignLifecycleUnknown]이 원문을 담는다(양 OS 네이티브와 같은 모양).
sealed class ShopliveCampaignLifecycleStatus {
  const ShopliveCampaignLifecycleStatus();

  static ShopliveCampaignLifecycleStatus _fromWire(Object? status, Object? unknownStatus) => switch (status) {
        'reserved' => const ShopliveCampaignLifecycleReserved(),
        'ready' => const ShopliveCampaignLifecycleReady(),
        'onAir' => const ShopliveCampaignLifecycleOnAir(),
        'closed' => const ShopliveCampaignLifecycleClosed(),
        'unknown' => ShopliveCampaignLifecycleUnknown(wire.asType<String>(unknownStatus)),
        // 네이티브보다 Dart가 오래된 경우의 새 wire 값 — 그 값을 원문으로 보존한다
        _ => ShopliveCampaignLifecycleUnknown(wire.asType<String>(status)),
      };
}

final class ShopliveCampaignLifecycleReserved extends ShopliveCampaignLifecycleStatus {
  const ShopliveCampaignLifecycleReserved();
}

final class ShopliveCampaignLifecycleReady extends ShopliveCampaignLifecycleStatus {
  const ShopliveCampaignLifecycleReady();
}

final class ShopliveCampaignLifecycleOnAir extends ShopliveCampaignLifecycleStatus {
  const ShopliveCampaignLifecycleOnAir();
}

final class ShopliveCampaignLifecycleClosed extends ShopliveCampaignLifecycleStatus {
  const ShopliveCampaignLifecycleClosed();
}

/// 모르는 서버 상태. [value]는 서버 원문(SDK가 원문을 주지 못하면 null).
final class ShopliveCampaignLifecycleUnknown extends ShopliveCampaignLifecycleStatus {
  const ShopliveCampaignLifecycleUnknown(this.value);

  final String? value;

  @override
  bool operator ==(Object other) => other is ShopliveCampaignLifecycleUnknown && other.value == value;

  @override
  int get hashCode => Object.hash(ShopliveCampaignLifecycleUnknown, value);

  @override
  String toString() => 'ShopliveCampaignLifecycleUnknown($value)';
}

/// 시청 지표. [showUserCount]가 false면 [userCount]·[adoreCount]를 UI에 노출하지 않아야 한다.
final class ShopliveCampaignMetrics {
  const ShopliveCampaignMetrics({this.userCount, this.adoreCount, required this.showUserCount});

  final int? userCount;
  final int? adoreCount;
  final bool showUserCount;

  static ShopliveCampaignMetrics? _tryParse(Object? raw) {
    final m = wire.asStringMap(raw);
    final show = m?['showUserCount'];
    if (m == null || show is! bool) return null;
    return ShopliveCampaignMetrics(userCount: wire.asType<int>(m['userCount']), adoreCount: wire.asType<int>(m['adoreCount']), showUserCount: show);
  }
}

DateTime? _utc(Object? ms) => ms is int ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true) : null;
