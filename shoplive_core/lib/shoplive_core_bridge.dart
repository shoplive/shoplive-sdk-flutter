/// Shoplive 패키지(shoplive_player·shoplive_streamer) **내부용** 브릿지 헬퍼.
///
/// 고객 앱용 API가 아니며 호환성을 보장하지 않는다(언제든 바뀔 수 있음). 앱 코드는
/// `package:shoplive_core/shoplive_core.dart`만 쓴다.
library shoplive_core_bridge;

export 'src/wire_enum.dart' show toWire, parseWireEnum;
