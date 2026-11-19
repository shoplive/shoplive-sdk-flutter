import 'package:meta/meta.dart';
import '../wire.dart' as wire;
import 'player_enums.dart';

/// start/play 옵션. null 필드는 SDK 기본값.
class ShoplivePlayOptions {
  const ShoplivePlayOptions({this.referrer, this.keepWindowStateOnPlayExecuted, this.presentationStyle});

  final String? referrer;
  final bool? keepWindowStateOnPlayExecuted;
  final ShoplivePresentationStyle? presentationStyle;

  @internal
  Map<String, Object?> toWire() {
    final m = <String, Object?>{};
    wire.putIfNotNull(m, 'referrer', referrer);
    wire.putIfNotNull(m, 'keepWindowStateOnPlayExecuted', keepWindowStateOnPlayExecuted);
    wire.putIfNotNull(m, 'presentationStyle', presentationStyle == null ? null : wire.toWire(presentationStyle!));
    return m;
  }
}
