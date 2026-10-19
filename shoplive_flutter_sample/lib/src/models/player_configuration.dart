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
  });

  final bool? isInAppPipEnabled;
  final bool? isOSPipEnabled;
  final ShoplivePipPosition? defaultPosition;
  final double? scale;
  final ShoplivePipRatio? aspectRatio;
  final ShopliveInsets? padding;

  /// in-app PIP 창을 화면 밖으로 끌어 놓아 닫을 수 있는지(SDK 3.0.3+, Android·iOS). null이면 현재 값 유지(SDK 기본값 —
  /// Android·iOS 모두 true — Android는 바이트코드, iOS는 실측으로 확인).
  final bool? isDragOutToCloseEnabled;

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
        );
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
  const ShopliveNavigationOptions({this.actionOnNavigation, this.shareScheme});

  final ShopliveNavigationAction? actionOnNavigation;
  final String? shareScheme;

  @internal
  Map<String, Object?> toWire() {
    final m = <String, Object?>{};
    wire.putIfNotNull(m, 'actionOnNavigation', actionOnNavigation == null ? null : wire.toWire(actionOnNavigation!));
    wire.putIfNotNull(m, 'shareScheme', shareScheme);
    return m;
  }

  static ShopliveNavigationOptions? _fromWire(Map<String, Object?>? m) => m == null
      ? null
      : ShopliveNavigationOptions(
          actionOnNavigation: _enum(ShopliveNavigationAction.values, m['actionOnNavigation'], ShopliveNavigationAction.unknown),
          shareScheme: wire.asType<String>(m['shareScheme']),
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
  const ShopliveAndroidPlayerOptions({
    this.enterOSPipOnBackPressed,
    this.isVolumeKeyEnabled,
    this.autoResumeOnFocusGained,
    this.isStatusBarVisible,
    this.allowScreenCapture,
    this.closeWhenAppDestroyed,
  });

  final bool? enterOSPipOnBackPressed;
  final bool? isVolumeKeyEnabled;
  final bool? autoResumeOnFocusGained;
  final bool? isStatusBarVisible;
  final bool? allowScreenCapture;
  final bool? closeWhenAppDestroyed;

  @internal
  Map<String, Object?> toWire() {
    final m = <String, Object?>{};
    wire.putIfNotNull(m, 'enterOSPipOnBackPressed', enterOSPipOnBackPressed);
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
          enterOSPipOnBackPressed: wire.asType<bool>(m['enterOSPipOnBackPressed']),
          isVolumeKeyEnabled: wire.asType<bool>(m['isVolumeKeyEnabled']),
          autoResumeOnFocusGained: wire.asType<bool>(m['autoResumeOnFocusGained']),
          isStatusBarVisible: wire.asType<bool>(m['isStatusBarVisible']),
          allowScreenCapture: wire.asType<bool>(m['allowScreenCapture']),
          closeWhenAppDestroyed: wire.asType<bool>(m['closeWhenAppDestroyed']),
        );
}
