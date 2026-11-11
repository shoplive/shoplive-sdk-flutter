import 'package:meta/meta.dart';
import '../wire.dart' as wire;
import 'player_enums.dart';

/// 플레이어 설정(design.md rev2 §2.4 Configuration). 모든 필드가 선택이며 **현재 설정 위에 병합**된다(CFG-01):
/// null 필드는 현재 값을 유지한다. `getConfiguration()`은 전체 값을 채워 돌려준다.
///
/// 한계: nullable 필드(navigation.shareScheme, android.isVolumeKeyEnabled)를 null로 되돌리는 표현은 이 Dart API에 없다.
class ShoplivePlayerConfiguration {
  const ShoplivePlayerConfiguration({
    this.type,
    this.pip,
    this.sound,
    this.appearance,
    this.navigation,
    this.overlay,
    this.customParameters,
    this.android,
  });

  final ShoplivePlayerType? type;
  final ShoplivePipOptions? pip;
  final ShopliveSoundOptions? sound;
  final ShopliveAppearanceOptions? appearance;
  final ShopliveNavigationOptions? navigation;
  final ShopliveOverlayOptions? overlay;

  /// 맵 단위로 교체된다.
  final Map<String, String>? customParameters;

  /// Android 전용 옵션. iOS에서는 무시된다(CS-03).
  final ShopliveAndroidPlayerOptions? android;

  @internal
  Map<String, Object?> toWire() {
    final m = <String, Object?>{};
    wire.putIfNotNull(m, 'type', type == null ? null : wire.toWire(type!));
    wire.putIfNotNull(m, 'pip', pip?.toWire());
    wire.putIfNotNull(m, 'sound', sound?.toWire());
    wire.putIfNotNull(m, 'appearance', appearance?.toWire());
    wire.putIfNotNull(m, 'navigation', navigation?.toWire());
    wire.putIfNotNull(m, 'overlay', overlay?.toWire());
    wire.putIfNotNull(m, 'customParameters', customParameters);
    wire.putIfNotNull(m, 'android', android?.toWire());
    return m;
  }

  /// getConfiguration 응답 파싱. 형식이 다른 필드는 null로 둔다(던지지 않음).
  static ShoplivePlayerConfiguration fromWire(Object? raw) {
    final m = wire.asStringMap(raw) ?? const {};
    final params = wire.asStringMap(m['customParameters']);
    return ShoplivePlayerConfiguration(
      type: _enum(ShoplivePlayerType.values, m['type'], ShoplivePlayerType.unknown),
      pip: ShoplivePipOptions._fromWire(wire.asStringMap(m['pip'])),
      sound: ShopliveSoundOptions._fromWire(wire.asStringMap(m['sound'])),
      appearance: ShopliveAppearanceOptions._fromWire(wire.asStringMap(m['appearance'])),
      navigation: ShopliveNavigationOptions._fromWire(wire.asStringMap(m['navigation'])),
      overlay: ShopliveOverlayOptions._fromWire(wire.asStringMap(m['overlay'])),
      customParameters: params == null ? null : {for (final e in params.entries) if (e.value is String) e.key: e.value! as String},
      android: ShopliveAndroidPlayerOptions._fromWire(wire.asStringMap(m['android'])),
    );
  }
}


E? _enum<E extends Enum>(List<E> values, Object? raw, E unknown) => raw == null ? null : wire.parseWireEnum(values, raw, unknown: unknown);

class ShoplivePipOptions {
  const ShoplivePipOptions({
    this.isInAppPipEnabled,
    this.isOSPipEnabled,
    this.defaultPosition,
    this.scale,
    this.aspectRatio,
    this.padding,
    this.isDragOutToCloseEnabled,
    this.closeButton,
    this.restoreButton,
  });

  /// 앱 사용 중 요청한 PIP(PIP 버튼·[ShoplivePlayer.enterPictureInPicture]·Android 뒤로가기 PIP)를 허용할지. null이면 현재 값 유지.
  /// Android SDK 3.0.5부터 [isOSPipEnabled]와 따로 판정한다(하나가 다른 하나를 끄지 않음). Android 풀스크린·임베드 플레이어의 PIP는 OS PIP 창이다.
  final bool? isInAppPipEnabled;

  /// 사용자가 앱을 떠날 때(홈 이탈) PIP로 이어 볼지. null이면 현재 값 유지. 앱 안 PIP 중 백그라운드로 가면 이 값이 false일 때 세션이 끝난다.
  final bool? isOSPipEnabled;
  final ShoplivePipPosition? defaultPosition;
  final double? scale;
  final ShoplivePipRatio? aspectRatio;
  final ShopliveInsets? padding;

  /// in-app PIP 창을 화면 밖으로 끌어 놓아 닫을 수 있는지(SDK 3.0.3+, Android·iOS). null이면 현재 값 유지(SDK 기본값 —
  /// Android·iOS 모두 true — Android는 바이트코드, iOS는 실측으로 확인).
  final bool? isDragOutToCloseEnabled;

  /// in-App PIP 창의 닫기(×) 버튼(SDK 3.0.4+, Android·iOS — SMV-1899). null이면 현재 값 유지.
  /// 숨기면 끌어내기([isDragOutToCloseEnabled])·앱의 `close()`로만 닫힌다 — 둘 다 막으면 사용자가 닫을 UI가 없다.
  final ShopliveButtonOptions? closeButton;

  /// in-App PIP 창의 복귀(풀스크린으로) 버튼(SDK 3.0.4+, Android·iOS — SMV-1899). null이면 현재 값 유지.
  /// 숨기면 PIP 창을 탭해 복귀한다.
  final ShopliveButtonOptions? restoreButton;

  @internal
  Map<String, Object?> toWire() {
    final m = <String, Object?>{};
    wire.putIfNotNull(m, 'isInAppPipEnabled', isInAppPipEnabled);
    wire.putIfNotNull(m, 'isOSPipEnabled', isOSPipEnabled);
    wire.putIfNotNull(m, 'defaultPosition', defaultPosition == null ? null : wire.toWire(defaultPosition!));
    wire.putIfNotNull(m, 'scale', scale);
    wire.putIfNotNull(m, 'aspectRatio', aspectRatio == null ? null : wire.toWire(aspectRatio!));
    wire.putIfNotNull(m, 'padding', padding?.toWire());
    wire.putIfNotNull(m, 'isDragOutToCloseEnabled', isDragOutToCloseEnabled);
    wire.putIfNotNull(m, 'closeButton', closeButton?.toWire());
    wire.putIfNotNull(m, 'restoreButton', restoreButton?.toWire());
    return m;
  }

  static ShoplivePipOptions? _fromWire(Map<String, Object?>? m) => m == null
      ? null
      : ShoplivePipOptions(
          isInAppPipEnabled: wire.asType<bool>(m['isInAppPipEnabled']),
          isOSPipEnabled: wire.asType<bool>(m['isOSPipEnabled']),
          defaultPosition: _enum(ShoplivePipPosition.values, m['defaultPosition'], ShoplivePipPosition.unknown),
          scale: wire.asType<num>(m['scale'])?.toDouble(),
          aspectRatio: _enum(ShoplivePipRatio.values, m['aspectRatio'], ShoplivePipRatio.unknown),
          padding: ShopliveInsets._fromWire(wire.asStringMap(m['padding'])),
          isDragOutToCloseEnabled: wire.asType<bool>(m['isDragOutToCloseEnabled']),
          closeButton: ShopliveButtonOptions._fromWire(wire.asStringMap(m['closeButton'])),
          restoreButton: ShopliveButtonOptions._fromWire(wire.asStringMap(m['restoreButton'])),
        );
}

/// in-App PIP 버튼 옵션(SDK 3.0.4+ `ButtonOptions`, SMV-1899). OS PIP 창에는 적용되지 않는다.
///
/// [isHidden]이 true면 이미지와 상관없이 버튼을 그리지 않는다(우선순위는 SDK가 정함).
class ShopliveButtonOptions {
  const ShopliveButtonOptions({this.isHidden, this.nativeImageName});

  /// true면 버튼을 그리지 않는다. null이면 현재 값 유지(SDK 기본 false).
  final bool? isHidden;

  /// 버튼 이미지로 쓸 **앱 네이티브 이미지 이름** — Android는 앱의 drawable 리소스 이름(`res/drawable/<name>`),
  /// iOS는 앱 번들 Asset Catalog의 이미지 이름이다. **Flutter 에셋 경로(`assets/...`)가 아니다.**
  /// - null(생략)이면 현재 이미지를 유지한다. 이미지가 없는 버튼은 서버 에셋으로 그리고, 서버 에셋도 없으면 닫기는 SDK 기본
  ///   이미지, 복귀는 버튼을 그리지 않는다. 두 버튼 모두 이미지가 없으면 3.0.3과 같은 외형이다. Android는 다른 버튼의
  ///   이미지가 해석되면 SDK가 두 버튼 모두 새 외형으로 그린다(iOS는 외형 전환 없음).
  /// - 이름을 찾지 못하거나 ''이면 실패하지 않고 경고 로그를 남긴 뒤 이미지 없음으로 그린다(이전에 지정한 이미지도 지워짐).
  /// - 버튼 틀은 Android 28dp · iOS 24pt — 벡터(Android vector drawable·iOS PDF/SVG) 또는 그 크기에 맞는 이미지를 권장한다.
  ///   Android drawable은 테마 속성(`?attr/...`)을 쓰지 않는다.
  /// - Android release 빌드의 리소스 축소(shrinkResources)는 Dart에서만 이름으로 쓰는 drawable을 지울 수 있다 —
  ///   `res/raw/keep.xml`에 `tools:keep="@drawable/<name>"`으로 남긴다.
  /// - 쓰기 전용: `getConfiguration()`은 이 값을 돌려주지 않는다(항상 null). get → set 왕복은 생략 = 유지라 이미지가 보존된다.
  final String? nativeImageName;

  @internal
  Map<String, Object?> toWire() {
    final m = <String, Object?>{};
    wire.putIfNotNull(m, 'isHidden', isHidden);
    wire.putIfNotNull(m, 'nativeImageName', nativeImageName);
    return m;
  }

  static ShopliveButtonOptions? _fromWire(Map<String, Object?>? m) =>
      m == null ? null : ShopliveButtonOptions(isHidden: wire.asType<bool>(m['isHidden']));
}

/// PIP 여백(px). null 변은 현재 값 유지.
class ShopliveInsets {
  const ShopliveInsets({this.left, this.top, this.right, this.bottom});

  final int? left;
  final int? top;
  final int? right;
  final int? bottom;

  @internal
  Map<String, Object?> toWire() {
    final m = <String, Object?>{};
    wire.putIfNotNull(m, 'left', left);
    wire.putIfNotNull(m, 'top', top);
    wire.putIfNotNull(m, 'right', right);
    wire.putIfNotNull(m, 'bottom', bottom);
    return m;
  }

  static ShopliveInsets? _fromWire(Map<String, Object?>? m) => m == null
      ? null
      : ShopliveInsets(left: wire.asType<int>(m['left']), top: wire.asType<int>(m['top']), right: wire.asType<int>(m['right']), bottom: wire.asType<int>(m['bottom']));
}

class ShopliveSoundOptions {
  const ShopliveSoundOptions({this.muteOnStart, this.mixWithOthers});

  final bool? muteOnStart;
  final bool? mixWithOthers;

  @internal
  Map<String, Object?> toWire() {
    final m = <String, Object?>{};
    wire.putIfNotNull(m, 'muteOnStart', muteOnStart);
    wire.putIfNotNull(m, 'mixWithOthers', mixWithOthers);
    return m;
  }

  static ShopliveSoundOptions? _fromWire(Map<String, Object?>? m) =>
      m == null ? null : ShopliveSoundOptions(muteOnStart: wire.asType<bool>(m['muteOnStart']), mixWithOthers: wire.asType<bool>(m['mixWithOthers']));
}

class ShopliveAppearanceOptions {
  const ShopliveAppearanceOptions({this.indicatorColor});

  /// ARGB 정수(예: 0xFF00FF00).
  final int? indicatorColor;

  @internal
  Map<String, Object?> toWire() {
    final m = <String, Object?>{};
    wire.putIfNotNull(m, 'indicatorColor', indicatorColor);
    return m;
  }

  static ShopliveAppearanceOptions? _fromWire(Map<String, Object?>? m) =>
      m == null ? null : ShopliveAppearanceOptions(indicatorColor: wire.asType<int>(m['indicatorColor']));
}

class ShopliveNavigationOptions {
  const ShopliveNavigationOptions({this.actionOnNavigation, this.shareScheme, this.isCustomShareEnabled});

  final ShopliveNavigationAction? actionOnNavigation;
  final String? shareScheme;

  /// 공유를 앱이 처리할지(SDK 3.0.4+, Android·iOS — SMV-1899). true면 공유 탭 때 SDK 기본 시트 대신
  /// [ShoplivePlayerShareRequested] 이벤트가 온다(events를 반드시 구독). null이면 현재 값 유지(SDK 기본값 false).
  /// 재생 중 바꾸면 Android는 바로, iOS는 다음 start·play·reload부터 적용된다(SDK 반영 시점 — README Configuration).
  final bool? isCustomShareEnabled;

  @internal
  Map<String, Object?> toWire() {
    final m = <String, Object?>{};
    wire.putIfNotNull(m, 'actionOnNavigation', actionOnNavigation == null ? null : wire.toWire(actionOnNavigation!));
    wire.putIfNotNull(m, 'shareScheme', shareScheme);
    wire.putIfNotNull(m, 'isCustomShareEnabled', isCustomShareEnabled);
    return m;
  }

  static ShopliveNavigationOptions? _fromWire(Map<String, Object?>? m) => m == null
      ? null
      : ShopliveNavigationOptions(
          actionOnNavigation: _enum(ShopliveNavigationAction.values, m['actionOnNavigation'], ShopliveNavigationAction.unknown),
          shareScheme: wire.asType<String>(m['shareScheme']),
          isCustomShareEnabled: wire.asType<bool>(m['isCustomShareEnabled']),
        );
}

class ShopliveOverlayOptions {
  const ShopliveOverlayOptions({this.ui});

  final ShopliveOverlayUIMode? ui;

  @internal
  Map<String, Object?> toWire() {
    final m = <String, Object?>{};
    wire.putIfNotNull(m, 'ui', ui == null ? null : wire.toWire(ui!));
    return m;
  }

  static ShopliveOverlayOptions? _fromWire(Map<String, Object?>? m) =>
      m == null ? null : ShopliveOverlayOptions(ui: _enum(ShopliveOverlayUIMode.values, m['ui'], ShopliveOverlayUIMode.unknown));
}

/// Android 전용 옵션(configuration.android, CS-03). iOS에서는 무시된다.
class ShopliveAndroidPlayerOptions {
  /// [enterOSPipOnBackPressed]는 [backPressEntersPip]의 옛 이름이다. 둘 다 주면 [backPressEntersPip]가 이긴다.
  const ShopliveAndroidPlayerOptions({
    bool? backPressEntersPip,
    @Deprecated('Use backPressEntersPip (renamed with Android SDK 3.0.6)') bool? enterOSPipOnBackPressed,
    this.isVolumeKeyEnabled,
    this.autoResumeOnFocusGained,
    this.isStatusBarVisible,
    this.allowScreenCapture,
    this.closeWhenAppDestroyed,
  }) : backPressEntersPip = backPressEntersPip ?? enterOSPipOnBackPressed;

  /// 시스템 뒤로가기로 PIP에 들어갈지(Android SDK 3.0.6 `PipOptions.backPressEntersPip`). 판정은 SDK가 한다 — 이 값과
  /// `pip.isInAppPipEnabled`가 모두 true일 때만 뒤로가기가 PIP로 내려가고, 아니면 세션을 닫는다(기본 false). null이면 현재 값 유지.
  final bool? backPressEntersPip;

  /// [backPressEntersPip]의 옛 이름(3.0.3). 같은 값을 읽는다.
  @Deprecated('Use backPressEntersPip (renamed with Android SDK 3.0.6)')
  bool? get enterOSPipOnBackPressed => backPressEntersPip;

  final bool? isVolumeKeyEnabled;
  final bool? autoResumeOnFocusGained;
  final bool? isStatusBarVisible;
  final bool? allowScreenCapture;
  final bool? closeWhenAppDestroyed;

  @internal
  Map<String, Object?> toWire() {
    final m = <String, Object?>{};
    // wire 키는 3.0.3 이름 그대로 — Dart와 네이티브는 한 패키지로 함께 배포돼 키를 바꿀 이득이 없다(SMV-1899 D8 W1).
    wire.putIfNotNull(m, 'enterOSPipOnBackPressed', backPressEntersPip);
    wire.putIfNotNull(m, 'isVolumeKeyEnabled', isVolumeKeyEnabled);
    wire.putIfNotNull(m, 'autoResumeOnFocusGained', autoResumeOnFocusGained);
    wire.putIfNotNull(m, 'isStatusBarVisible', isStatusBarVisible);
    wire.putIfNotNull(m, 'allowScreenCapture', allowScreenCapture);
    wire.putIfNotNull(m, 'closeWhenAppDestroyed', closeWhenAppDestroyed);
    return m;
  }

  static ShopliveAndroidPlayerOptions? _fromWire(Map<String, Object?>? m) => m == null
      ? null
      : ShopliveAndroidPlayerOptions(
          backPressEntersPip: wire.asType<bool>(m['enterOSPipOnBackPressed']),
          isVolumeKeyEnabled: wire.asType<bool>(m['isVolumeKeyEnabled']),
          autoResumeOnFocusGained: wire.asType<bool>(m['autoResumeOnFocusGained']),
          isStatusBarVisible: wire.asType<bool>(m['isStatusBarVisible']),
          allowScreenCapture: wire.asType<bool>(m['allowScreenCapture']),
          closeWhenAppDestroyed: wire.asType<bool>(m['closeWhenAppDestroyed']),
        );
}
