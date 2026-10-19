import 'package:meta/meta.dart';
/// `Shoplive.initialize` 설정(design.md rev2 §2.4·§2.6). null 필드는 키를 생략해 SDK 기본값을 쓴다.
class ShopliveConfiguration {
  const ShopliveConfiguration({
    required this.accessKey,
    this.allowedWebViewDomains,
    this.attribution,
    @Deprecated('Ignored since Shoplive SDK 3.0.3. Will be removed in a future major release.') this.appVersion,
  });

  final String accessKey;

  /// 생략(null) 시 SDK 기본값(빈 리스트).
  final List<String>? allowedWebViewDomains;
  final ShopliveAttribution? attribution;

  /// 무시된다: Shoplive SDK 3.0.3은 Android·iOS 모두 앱 버전을 직접 읽으므로 이 값을 SDK에 전달하지 않는다.
  /// 3.0.2 코드 호환을 위해 남겨 둔 필드다 — 타입만 검증(문자열이 아니면 `INVALID_ARGUMENT`)하고 경고 로그 후 버린다.
  @Deprecated('Ignored since Shoplive SDK 3.0.3 (Android and iOS read the app version themselves). Will be removed in a future major release.')
  final String? appVersion;

  @internal
  Map<String, Object?> toWire() => {
        'accessKey': accessKey,
        if (allowedWebViewDomains != null) 'allowedWebViewDomains': allowedWebViewDomains,
        if (attribution != null) 'attribution': attribution!.toWire(),
        // 브릿지가 타입 검증·경고 로그 후 버린다(3.0.2 호출 호환).
        // ignore: deprecated_member_use_from_same_package
        if (appVersion != null) 'appVersion': appVersion,
      };
}

class ShopliveAttribution {
  const ShopliveAttribution({this.utmSource, this.utmMedium, this.utmCampaign, this.utmContent});

  final String? utmSource;
  final String? utmMedium;
  final String? utmCampaign;
  final String? utmContent;

  @internal
  Map<String, Object?> toWire() => {
        if (utmSource != null) 'utmSource': utmSource,
        if (utmMedium != null) 'utmMedium': utmMedium,
        if (utmCampaign != null) 'utmCampaign': utmCampaign,
        if (utmContent != null) 'utmContent': utmContent,
      };
}
