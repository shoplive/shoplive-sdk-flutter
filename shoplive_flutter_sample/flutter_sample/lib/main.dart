import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shoplive_player/shoplive_player.dart';
import 'package:shoplive_streamer/shoplive_streamer.dart'
    show
        ShopliveBroadcastState,
        ShopliveStreamer,
        ShopliveStreamerEvent,
        ShopliveStreamerStateChanged,
        ShopliveStreamerErrorEvent,
        ShopliveStreamerUnknownEvent;

import 'studio_login.dart';

// Shoplive 3.0.3 데모(DRAFT-flutter-sdk-302-android S9, SMV-1749): shoplive_core · shoplive_player · shoplive_streamer.
//
// 빌드 설정(Android): Shoplive SDK는 https://sdk.shoplive.cloud/maven-repo 에서 받는다(3.0.3은 Maven Central에 없음).
// 플러그인이 cloud.shoplive 그룹을 exclusiveContent로 이 저장소에만 묶는다(플러그인 android/build.gradle 참고).
// minSdk 23, compileSdk 36, Java 17이 필요하다.
//
// 실행: flutter run
//       입력칸에는 1.x 샘플(flutter_sample/lib/main.dart, main 브랜치)과 같은 기본 키가 채워진다.
//       다른 키를 쓰려면 --dart-define=SHOPLIVE_ACCESS_KEY=<key> / SHOPLIVE_CAMPAIGN_KEY=<key> 로 덮어쓴다.
//       SHOPLIVE_ACCESS_KEY 를 넘기면 앱 시작 시점에 바로 초기화한다.

/// 1.x 샘플 기본값(main 브랜치 flutter_sample/lib/main.dart:44-45와 동일).
const String _defaultAccessKey = 'uv9CGthPzlvsInZerCw0';
const String _defaultCampaignKey = '2551fcb165c3';

/// --dart-define=SHOPLIVE_ACCESS_KEY 로 주입(앱 시작 시 초기화 패턴).
const String _accessKeyFromEnv = String.fromEnvironment('SHOPLIVE_ACCESS_KEY');
const String _campaignKeyFromEnv = String.fromEnvironment('SHOPLIVE_CAMPAIGN_KEY', defaultValue: _defaultCampaignKey);

/// 방송자(스튜디오) JWT를 미리 알고 있으면 --dart-define=SHOPLIVE_STREAM_TOKEN 으로 넣을 수 있다(로그인 생략).
const String _streamTokenFromEnv = String.fromEnvironment('SHOPLIVE_STREAM_TOKEN');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (_accessKeyFromEnv.isNotEmpty) {
    // 앱 시작 시점에 한 번 초기화한다. 실패는 앱 실행을 막지 않고 로그로 남긴다.
    unawaited(Shoplive.initialize(const ShopliveConfiguration(accessKey: _accessKeyFromEnv)).catchError(
      (Object e) => debugPrint('Shoplive.initialize failed: ${e is PlatformException ? e.code : e.runtimeType}'),
    ));
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'Shoplive 3.0.3 sample', home: ShopliveSamplePage());
  }
}

class ShopliveSamplePage extends StatefulWidget {
  const ShopliveSamplePage({super.key, this.studioLogin});

  /// 테스트에서 가짜 로그인 서버를 넣기 위한 주입점. null이면 실제 스튜디오 로그인.
  final StudioLogin? studioLogin;

  static const String title = 'Shoplive SDK 3.0.3 sample';

  @override
  State<ShopliveSamplePage> createState() => _ShopliveSamplePageState();
}

class _ShopliveSamplePageState extends State<ShopliveSamplePage> {
  static const int _maxLogLines = 200;

  final _accessKey = TextEditingController(text: _accessKeyFromEnv.isEmpty ? _defaultAccessKey : _accessKeyFromEnv);
  final _campaignKey = TextEditingController(text: _campaignKeyFromEnv);
  final _shareScheme = TextEditingController();
  final _streamerKey = TextEditingController();
  final _webPageUrl = TextEditingController();
  final _studioId = TextEditingController();
  final _studioPassword = TextEditingController();
  late final StudioLogin _studioLogin = widget.studioLogin ?? StudioLogin();

  /// 방송자 JWT. 메모리에만 둔다(로그·디스크 저장 안 함).
  String? _studioJwt = _streamTokenFromEnv.isEmpty ? null : _streamTokenFromEnv;
  final _userId = TextEditingController(text: 'sample-user');
  final _jwt = TextEditingController();

  final _player = ShoplivePlayer.instance;
  final _streamer = ShopliveStreamer.instance;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _log = <String>[];

  bool _respondToRequests = true;
  bool _muted = false;
  // OS PIP 사용 여부 — 끄면 in-App PIP(미니) 상태에서 홈으로 나갈 때 OS PIP 없이 백그라운드로 내려간다. 모든 start 경로에 함께 실린다.
  bool _osPipEnabled = true;
  ShoplivePlayerState _playerState = ShoplivePlayerState.idle;
  ShopliveBroadcastState _broadcastState = ShopliveBroadcastState.idle;

  @override
  void initState() {
    super.initState();
    // 요청 리스너(쿠폰·커스텀)는 플레이어를 쓰는 동안 계속 구독한다:
    //  - 리스너가 없으면 SDK 요청은 즉시 폴백(success=false, status=keep, toast)으로 응답된다.
    //  - 모든 요청 리스너가 해제되면 응답 대기 중인 요청도 폴백으로 끝난다.
    //  - 리스너가 동기 예외를 던지면 그 요청은 즉시 폴백된다.
    _subscriptions
      ..add(_player.events.listen(_onPlayerEvent, onError: _onStreamError))
      ..add(_player.navigationRequests.listen((r) => _append('navigation → ${r.url}'), onError: _onStreamError))
      ..add(_player.couponRequests.listen(_onCoupon, onError: _onStreamError))
      ..add(_player.customWebActionRequests.listen(_onCustomAction, onError: _onStreamError))
      ..add(_streamer.events.listen(_onStreamerEvent, onError: _onStreamError));
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    for (final c in [_accessKey, _campaignKey, _shareScheme, _streamerKey, _webPageUrl, _studioId, _studioPassword, _userId, _jwt]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- 이벤트·요청 ----

  void _onPlayerEvent(ShoplivePlayerEvent e) {
    switch (e) {
      case ShoplivePlayerStateChanged(:final state):
        setState(() => _playerState = state);
        _append('player state → ${state.name}');
      case ShopliveCampaignStatusChanged(:final status):
        _append('campaign status → ${status.name}');
      case ShopliveCampaignInfoReceived(:final info):
        _append('campaign info → ${info.campaignKey} ${info.title ?? ''}');
      case ShopliveConnectionStateChanged(:final state):
        _append('connection → ${state.name}');
      case ShoplivePlaybackEvent(:final kind, :final code):
        _append('playback → ${kind.name}${code == null ? '' : ' code=$code'}');
      case ShoplivePlayerErrorEvent(:final error):
        _append('player error → ${error.code} recoverable=${error.recoverable}');
      case ShopliveAnalyticsEvent(:final isPlaying, :final durationMs):
        _append('analytics → playing=$isPlaying ${durationMs}ms');
      case ShopliveWebCommandReceived(:final name):
        _append('web command → $name');
      case ShopliveUserNameUpdateRequested():
        _append('user name update requested');
      case ShoplivePlayerUnknownEvent(:final rawType):
        _append('unknown player event → $rawType');
    }
  }

  void _onStreamerEvent(ShopliveStreamerEvent e) {
    switch (e) {
      case ShopliveStreamerStateChanged(:final state, :final isRehearsal):
        setState(() => _broadcastState = state);
        _append('broadcast → ${state.name}${isRehearsal == true ? ' (rehearsal)' : ''}');
      case ShopliveStreamerErrorEvent(:final error):
        _append('streamer error → ${error.code}');
      case ShopliveStreamerUnknownEvent(:final rawType):
        _append('unknown streamer event → $rawType');
    }
  }

  Future<void> _onCoupon(ShopliveCouponRequest r) async {
    _append('coupon request ${r.couponId} (respond=${_respondToRequests ? 'on' : 'off → timeout fallback'})');
    if (!_respondToRequests) return;
    final delivered = await r.respond(const ShopliveCouponResult(
      success: true,
      status: ShopliveResultStatus.hide,
      message: '쿠폰이 발급되었습니다',
      alertType: ShopliveResultAlertType.toast,
    ));
    _append(delivered ? 'coupon respond delivered' : 'coupon respond ignored — 이미 타임아웃/중복 응답/리스너 해제로 폴백됨');
  }

  Future<void> _onCustomAction(ShopliveCustomWebActionRequest r) async {
    _append('custom action ${r.id} type=${r.actionType} (respond=${_respondToRequests ? 'on' : 'off'})');
    if (!_respondToRequests) return;
    final delivered =
        await r.respond(const ShopliveCustomActionResult(success: true, status: ShopliveResultStatus.keep));
    _append(
        delivered ? 'custom action respond delivered' : 'custom action respond ignored — 이미 타임아웃/중복 응답/리스너 해제로 폴백됨');
  }

  void _onStreamError(Object error) => _append('stream error → ${error.runtimeType}');

  void _append(String line) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, '${TimeOfDay.now().format(context)}  $line');
      if (_log.length > _maxLogLines) _log.removeLast();
    });
  }

  // ---- 호출 래퍼: 실패는 코드로 표시 ----

  /// 호출 결과를 로그로 남기고 성공 여부를 돌려준다. 빠른 실행은 실패한 단계에서 멈춘다.
  Future<bool> _run(String label, Future<Object?> Function() action) async {
    try {
      final result = await action();
      _append('$label ✓${result == null ? '' : ' → $result'}');
      return true;
    } on PlatformException catch (e) {
      _append('$label ✗ ${e.code}');
      _toast('$label 실패: ${e.code}');
    } on MissingPluginException {
      _append('$label ✗ not implemented on this platform');
      _toast('$label 실패: not implemented on this platform');
    } catch (e) {
      _append('$label ✗ ${e.runtimeType}');
      _toast('$label 실패: ${e.runtimeType}');
    }
    return false;
  }

  // ---- 빠른 실행(1.x example의 LivePlayer PLAY / LivePreview PLAY와 같은 흐름) ----

  /// 입력값 확인 → initialize → setUser(profile) → 플레이어 설정 → start 를 한 번에 수행한다.
  Future<void> _quickPlay({required bool preview}) async {
    final accessKey = _accessKey.text.trim();
    final campaignKey = _campaignKey.text.trim();
    if (accessKey.isEmpty) return _toast('Required to accessKey');
    if (campaignKey.isEmpty) return _toast('Required to campaignKey');
    final shareScheme = _shareScheme.text.trim();

    // 초기화·사용자 설정이 실패하면 재생하지 않는다(이전 초기화 상태로 잘못 재생되는 것을 막음).
    if (!await _run('initialize', () => Shoplive.initialize(ShopliveConfiguration(accessKey: accessKey)))) return;
    final userId = _userId.text.trim().isEmpty ? 'userId' : _userId.text.trim();
    if (!await _run(
      'setUser',
      () => Shoplive.setUser(ShopliveUser.profile(
        id: userId,
        name: 'TestUser',
        age: 20,
        gender: ShopliveGender.neutral,
        rank: 0,
        custom: {'key': 'value'},
      )),
    )) {
      return;
    }
    await _run(
      preview ? 'LivePreview PLAY' : 'LivePlayer PLAY',
      () => _player.start(
        campaignKey,
        playOptions: preview ? const ShoplivePlayOptions(presentationStyle: ShoplivePresentationStyle.pip) : null,
        configuration: ShoplivePlayerConfiguration(
          type: preview ? ShoplivePlayerType.preview : ShoplivePlayerType.live,
          pip: ShoplivePipOptions(isInAppPipEnabled: true, isOSPipEnabled: _osPipEnabled),
          sound: const ShopliveSoundOptions(muteOnStart: false, mixWithOthers: true),
          navigation: ShopliveNavigationOptions(shareScheme: shareScheme.isEmpty ? null : shareScheme),
          android: const ShopliveAndroidPlayerOptions(enterOSPipOnBackPressed: true),
        ),
      ),
    );
  }

  /// 네이티브 데모 앱과 같은 순서: 스튜디오 로그인(JWT 없을 때만) → initialize → setStreamToken(JWT) → start.
  /// 토큰이 없으면 서버가 송출 주소를 내주지 않아 SDK가 "방송 송출에 실패했습니다" 팝업을 띄운다.
  Future<void> _quickBroadcast() async {
    final accessKey = _accessKey.text.trim();
    final broadcastKey = _streamerKey.text.trim();
    if (accessKey.isEmpty) return _toast('Required to accessKey');
    if (broadcastKey.isEmpty) return _toast('Required to broadcast campaignKey');
    final jwt = _studioJwt ?? await _loginStudio();
    if (jwt == null) return;
    if (!await _run('initialize', () => Shoplive.initialize(ShopliveConfiguration(accessKey: accessKey)))) return;
    if (!await _run('setStreamToken', () => Shoplive.setStreamToken(jwt))) {
      setState(() => _studioJwt = null);
      return;
    }
    // 고급 제어 > Streamer 의 Web page URL 칸을 함께 쓴다(비우면 웹페이지 없음).
    final url = _webPageUrl.text.trim();
    await _run('Streamer START', () => _streamer.start(broadcastKey, webPageUrl: url.isEmpty ? null : url));
  }

  Future<String?> _loginStudio() async {
    final id = _studioId.text.trim();
    final password = _studioPassword.text;
    if (id.isEmpty || password.isEmpty) {
      _toast('Required to studio login (ID / password)');
      return null;
    }
    try {
      final sdkVersion = await Shoplive.getSdkVersion().catchError((Object _) => '');
      final jwt = await _studioLogin.login(
        id: id,
        password: password,
        headers: StudioLogin.defaultHeaders(sdkVersion: sdkVersion),
      );
      _studioPassword.clear();
      setState(() => _studioJwt = jwt);
      _append('studio login ✓');
      return jwt;
    } on StudioLoginException catch (e) {
      _append('studio login ✗ ${e.statusCode ?? ''}');
      _toast('Studio login failed: $e');
      return null;
    }
  }

  /// 앱에 보관한 JWT만 버린다. SDK에 이미 설정된 stream token은 다음 setStreamToken 때 교체된다
  /// (Shoplive.setStreamToken은 빈 값을 받지 않아 SDK 쪽을 비울 공개 API가 없다).
  void _logoutStudio() {
    setState(() => _studioJwt = null);
    _append('studio logout');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(ShopliveSamplePage.title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Text('player: ${_playerState.name}   broadcast: ${_broadcastState.name}',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  _outlinedField(_accessKey, 'Access key'),
                  _outlinedField(_campaignKey, 'Campaign key'),
                  _outlinedField(_shareScheme, 'Share scheme url'),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                            onPressed: () => _quickPlay(preview: false), child: const Text('LivePlayer PLAY')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: () => _quickPlay(preview: true),
                          child: const Text('LivePreview PLAY'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _outlinedField(_streamerKey, 'Broadcast campaign key'),
                  if (_studioJwt == null) ...[
                    _outlinedField(_studioId, 'Studio ID (broadcaster)'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: _studioPassword,
                        obscureText: true,
                        decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Studio password'),
                      ),
                    ),
                  ] else
                    Row(
                      children: [
                        const Expanded(child: Text('Studio: logged in (stream token set on START)')),
                        TextButton(onPressed: _logoutStudio, child: const Text('Studio logout')),
                      ],
                    ),
                  FilledButton.tonal(onPressed: _quickBroadcast, child: const Text('Streamer START')),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('쿠폰·커스텀 요청에 응답'),
                    subtitle: const Text('끄면 응답하지 않음 → 10초 뒤 폴백(실패·유지·토스트)'),
                    value: _respondToRequests,
                    onChanged: (v) => setState(() => _respondToRequests = v),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    title: const Text('고급 제어 (3.0.3 API 개별 호출)'),
                    children: _advancedControls(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              flex: 2,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _log.length,
                itemBuilder: (_, i) => Text(_log[i], style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _advancedControls() => [
        _section('Core'),
        _field(_accessKey, 'Access key'),
        _buttons([
          _button('initialize', () => Shoplive.initialize(ShopliveConfiguration(accessKey: _accessKey.text.trim()))),
          _button('sdkVersion', Shoplive.getSdkVersion),
          _button('guest', () => Shoplive.setUser(const ShopliveUser.guest())),
          _button('profile', () => Shoplive.setUser(ShopliveUser.profile(id: _userId.text.trim(), name: 'Sample'))),
          _button('token', () => Shoplive.setUser(ShopliveUser.token(_jwt.text.trim()))),
          _button('logout', Shoplive.logout),
        ]),
        _field(_userId, 'Profile user id'),
        _field(_jwt, 'JWT'),
        _section('Player'),
        _field(_campaignKey, 'Campaign key'),
        _buttons([
          _button(
            'start',
            () => _player.start(
              _campaignKey.text.trim(),
              configuration: ShoplivePlayerConfiguration(pip: ShoplivePipOptions(isOSPipEnabled: _osPipEnabled)),
            ),
          ),
          _button(
            'start PIP',
            () => _player.start(
              _campaignKey.text.trim(),
              playOptions: const ShoplivePlayOptions(presentationStyle: ShoplivePresentationStyle.pip),
              configuration: ShoplivePlayerConfiguration(
                pip: ShoplivePipOptions(isInAppPipEnabled: true, isOSPipEnabled: _osPipEnabled),
              ),
            ),
          ),
          _button(
            'start preview',
            () => _player.start(
              _campaignKey.text.trim(),
              configuration: ShoplivePlayerConfiguration(
                type: ShoplivePlayerType.preview,
                pip: ShoplivePipOptions(isOSPipEnabled: _osPipEnabled),
              ),
            ),
          ),
          _button('play', () => _player.play(_campaignKey.text.trim())),
          _button('stop', _player.stop),
          _button('reload', _player.reload),
          _button('close', _player.close),
          _button(_muted ? 'unmute' : 'mute', () async {
            await _player.setMuted(!_muted);
            setState(() => _muted = !_muted);
            return null;
          }),
          _button('enter PiP', _player.enterPictureInPicture),
          _button('exit PiP', _player.exitPictureInPicture),
          _button('state', () async => (await _player.getState()).name),
          _button('resize fit', () => _player.setResizeMode(ShopliveResizeMode.fit)),
          // OS PiP on/off — 끄면 홈으로 나갈 때 OS PIP 없이 백그라운드로 내려간다. SDK 는 IDLE 에서만 설정을 받으므로
          // 이미 한 번 재생했다면 앱을 다시 띄운 뒤 첫 재생 전에 누른다. 값은 모든 start 경로(PLAY 포함)에 함께 실린다.
          for (final enabled in [false, true])
            _button('OS PiP ${enabled ? 'on' : 'off'}', () async {
              setState(() => _osPipEnabled = enabled);
              await _player.setConfiguration(ShoplivePlayerConfiguration(pip: ShoplivePipOptions(isOSPipEnabled: enabled)));
              return 'osPip=$enabled (첫 재생 전에 설정)';
            }),
          for (final enabled in [false, true])
            _button(
              'PiP drag-out close ${enabled ? 'on' : 'off'}',
              () => _player.setConfiguration(ShoplivePlayerConfiguration(pip: ShoplivePipOptions(isDragOutToCloseEnabled: enabled))),
            ),
          _button('config', () async {
            final c = await _player.getConfiguration();
            return 'type=${c.type?.name} inAppPip=${c.pip?.isInAppPipEnabled} osPip=${c.pip?.isOSPipEnabled} dragOutClose=${c.pip?.isDragOutToCloseEnabled} '
                'muteOnStart=${c.sound?.muteOnStart} overlay=${c.overlay?.ui?.name}';
          }),
        ]),
        _section('Streamer'),
        _field(_webPageUrl, 'Web page URL (optional, http/https)'),
        _buttons([
          _button('start broadcast', () {
            final url = _webPageUrl.text.trim();
            return _streamer.start(_streamerKey.text.trim(), webPageUrl: url.isEmpty ? null : url);
          }),
          _button('broadcast state', () async => (await _streamer.getState()).name),
        ]),
      ];

  Widget _outlinedField(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child:
            TextField(controller: c, decoration: InputDecoration(border: const OutlineInputBorder(), labelText: label)),
      );

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _field(TextEditingController c, String label) =>
      TextField(controller: c, decoration: InputDecoration(labelText: label, isDense: true));

  Widget _buttons(List<Widget> children) => Wrap(spacing: 6, runSpacing: 4, children: children);

  Widget _button(String label, Future<Object?> Function() action) =>
      OutlinedButton(onPressed: () => _run(label, action), child: Text(label));
}
