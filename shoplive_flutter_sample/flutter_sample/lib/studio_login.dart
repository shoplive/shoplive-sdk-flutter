import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Broadcaster (studio) login for the sample app.
///
/// The Shoplive SDK has no public login API: the native demo app logs in with the SDK's internal
/// network service and passes the returned JWT to `Shoplive.setStreamToken`. This reproduces that
/// call over plain HTTP so the sample can follow the same order:
/// login -> `Shoplive.initialize` -> `Shoplive.setStreamToken(jwt)` -> `ShopliveStreamer.start`.
///
/// Contract (matrix-sdk-android, ShopLiveNetworkStreamerService.login / ShopLiveStreamerLoginRequest):
///   POST {host}studio/v2/administrator/login, form-urlencoded id, password, source=STREAM_APP, duration=10000
///   2xx -> {"accessToken": "<jwt>"}; error -> {"_s": code, "_e" | "message": text}
///
/// The Flutter plugin always talks to the production stage (stage selection is internal in SDK 3.x),
/// so only the production host is used here. Credentials and the JWT are never logged or persisted.
class StudioLogin {
  StudioLogin({StudioTransport? transport}) : _transport = transport ?? _HttpClientTransport();

  static final Uri loginUri = Uri.parse('https://private.shopliveapi.com/studio/v2/administrator/login');

  final StudioTransport _transport;

  /// Returns the broadcaster JWT, or throws [StudioLoginException].
  Future<String> login({required String id, required String password, Map<String, String> headers = const {}}) async {
    if (id.trim().isEmpty || password.isEmpty) {
      throw const StudioLoginException('ID and password are required');
    }
    // TODO(SDP-VERIFY): 요확인 — SDK는 FormBody.addEncoded로 값을 인코딩 없이 보낸다. 여기서는 표준 퍼센트 인코딩을 한다.
    //  특수문자(&, =, %, +) 비밀번호에서 서버 해석이 같은지 실측 · 근거 DRAFT-flutter-sdk-302-ios/STUDIO-LOGIN
    final body = {
      'id': id.trim(),
      'password': password,
      'source': 'STREAM_APP',
      'duration': '10000',
    }.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');

    final StudioResponse res;
    try {
      res = await _transport.post(loginUri, body, {
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        'Accept': 'application/json',
        ...headers,
      });
    } on TimeoutException {
      throw const StudioLoginException('Network timeout');
    } on IOException {
      // SocketException, HttpException, TlsException(HandshakeException) 등. 원인 메시지는 노출하지 않는다.
      throw const StudioLoginException('Network error');
    }

    Object? json;
    try {
      json = res.body.isEmpty ? null : jsonDecode(res.body);
    } on FormatException {
      json = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final token = json is Map ? json['accessToken'] : null;
      if (token is String && token.isNotEmpty) return token;
      throw StudioLoginException('Login response has no accessToken', statusCode: res.statusCode);
    }
    final message = json is Map ? (json['_e'] ?? json['message']) : null;
    throw StudioLoginException(message is String && message.isNotEmpty ? message : 'Login failed',
        statusCode: res.statusCode);
  }

  /// Headers the SDK sends with studio calls (ShopLiveCommonNetwork.studioHeader) that are known without
  /// native device APIs.
  // TODO(SDP-VERIFY): 요확인 — 서버가 x-sl-studio-* 헤더(sdk-version, os-version, device)를 필수로 요구하는지 실측.
  //  여기서는 os-type·sdk-version·language만 보낸다 · 근거 DRAFT-flutter-sdk-302-ios/STUDIO-LOGIN
  static Map<String, String> defaultHeaders({required String sdkVersion}) => {
        'x-sl-studio-os-type': Platform.isIOS ? 'i' : 'a',
        'x-sl-studio-sdk-version': sdkVersion,
        'x-sl-language': Platform.localeName.split(RegExp('[_-]')).first,
      };
}

class StudioLoginException implements Exception {
  const StudioLoginException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null ? message : '$message (HTTP $statusCode)';
}

class StudioResponse {
  const StudioResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

/// HTTP seam so the login flow can be tested without the network.
abstract class StudioTransport {
  Future<StudioResponse> post(Uri uri, String body, Map<String, String> headers);
}

class _HttpClientTransport implements StudioTransport {
  @override
  Future<StudioResponse> post(Uri uri, String body, Map<String, String> headers) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.postUrl(uri);
      headers.forEach(req.headers.set);
      req.write(body);
      final res = await req.close().timeout(const Duration(seconds: 30));
      return StudioResponse(
          res.statusCode, await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 30)));
    } finally {
      client.close(force: true);
    }
  }
}
