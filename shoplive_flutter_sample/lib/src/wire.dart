// shoplive_core의 패키지 내부용 브릿지 헬퍼(고객 비보장 — pair #25).
import 'package:shoplive_core/shoplive_core_bridge.dart' show toWire, parseWireEnum;

import 'models/player_enums.dart';

export 'package:shoplive_core/shoplive_core_bridge.dart' show toWire, parseWireEnum;

/// [ShopliveResizeMode.auto]의 wire 값. enum 이름과 다른 유일한 wire 값이다 — Android SDK 3.0.6 `DEFAULT`를 따르는데
/// `default`는 Dart 예약어라 enum 이름을 쓸 수 없다(사용자 결정 — SMV-1899 D9).
const String _resizeModeAutoWire = 'default';

String resizeModeToWire(ShopliveResizeMode mode) => mode == ShopliveResizeMode.auto ? _resizeModeAutoWire : toWire(mode);

/// 'default' → auto. 'auto'는 wire 값이 아니므로 다른 미지 값처럼 unknown(값 하나에 wire 하나).
ShopliveResizeMode resizeModeFromWire(Object? raw) {
  if (raw == _resizeModeAutoWire) return ShopliveResizeMode.auto;
  final mode = parseWireEnum(ShopliveResizeMode.values, raw, unknown: ShopliveResizeMode.unknown);
  return mode == ShopliveResizeMode.auto ? ShopliveResizeMode.unknown : mode;
}

/// 네이티브 Map 읽기 헬퍼. 형식이 다르면 null(파서가 unknown으로 폴백).
Map<String, Object?>? asStringMap(Object? raw) {
  if (raw is! Map) return null;
  final out = <String, Object?>{};
  for (final e in raw.entries) {
    final k = e.key;
    if (k is! String) return null;
    out[k] = e.value;
  }
  return out;
}

T? asType<T>(Object? v) => v is T ? v : null;

/// null 필드를 키 생략으로(키 부재 = 기본값/현재 값 유지, design §2.2).
void putIfNotNull(Map<String, Object?> m, String key, Object? value) {
  if (value != null) m[key] = value;
}
