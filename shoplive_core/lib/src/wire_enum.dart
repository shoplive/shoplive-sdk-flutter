/// enum ↔ 채널 wire 값 헬퍼.
///
/// wire 값은 Dart enum의 camelCase `name`이다. 각 플랫폼이 자기 SDK 상수로 매핑한다.
library;

/// Dart → 네이티브: wire 문자열.
String toWire(Enum value) => value.name;

/// 네이티브 → Dart: 미지 값(신규 SDK 상수·잘못된 타입·null)은 [unknown]으로 받는다
/// (스트림을 에러로 끊지 않는다).
E parseWireEnum<E extends Enum>(Iterable<E> values, Object? raw, {required E unknown}) {
  if (raw is! String) return unknown;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return unknown;
}
