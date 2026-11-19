import 'package:meta/meta.dart';
import '../wire_enum.dart' as wire;

/// 프로필 성별.
enum ShopliveGender { male, female, neutral, undefined }

/// `Shoplive.setUser` 사용자.
sealed class ShopliveUser {
  const ShopliveUser();

  const factory ShopliveUser.guest() = ShopliveGuestUser;
  const factory ShopliveUser.token(String jwt) = ShopliveTokenUser;
  const factory ShopliveUser.profile({
    required String id,
    String? name,
    int? age,
    ShopliveGender? gender,
    int? rank,
    Map<String, Object?>? custom,
  }) = ShopliveProfileUser;

  @internal
  @internal
  Map<String, Object?> toWire();
}

class ShopliveGuestUser extends ShopliveUser {
  const ShopliveGuestUser();

  @override
  @internal
  Map<String, Object?> toWire() => {'type': 'guest'};
}

class ShopliveTokenUser extends ShopliveUser {
  const ShopliveTokenUser(this.jwt);

  final String jwt;

  @override
  @internal
  Map<String, Object?> toWire() => {'type': 'token', 'jwt': jwt};
}

/// [id]는 필수(SDK @NotNull, default 없음). [gender] 생략 시 SDK 기본값.
class ShopliveProfileUser extends ShopliveUser {
  const ShopliveProfileUser({required this.id, this.name, this.age, this.gender, this.rank, this.custom});

  final String id;
  final String? name;
  final int? age;
  final ShopliveGender? gender;
  final int? rank;
  final Map<String, Object?>? custom;

  @override
  @internal
  Map<String, Object?> toWire() => {
        'type': 'profile',
        'id': id,
        if (name != null) 'name': name,
        if (age != null) 'age': age,
        if (gender != null) 'gender': wire.toWire(gender!),
        if (rank != null) 'rank': rank,
        if (custom != null) 'custom': custom,
      };
}

