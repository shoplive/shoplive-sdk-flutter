/// player wire enum(design.md rev2 §2.3). 네이티브에서 받는 값이 미지이면 `unknown`(B-02).
/// `unknown`을 네이티브로 보내면 INVALID_ARGUMENT가 된다.
library;

enum ShoplivePlayerState { idle, loading, playing, paused, inAppPip, closed, unknown }

/// 플레이어가 닫힌 이유(SDK 3.0.4, SMV-1899). [ShoplivePlayerState.closed]의 stateChanged에만 실린다.
/// - [userAction]: 사용자가 닫음(닫기 버튼·PIP 끌어내기·뒤로가기 등)
/// - [appRequest]: 앱 또는 SDK가 닫음(`stop`·`close`·SDK 내부 정지, 새 `start`가 화면을 띄우지 못해 이전 세션이 끝난 경우).
///   `start`로 교체된 이전 세션의 closed는 오지 않는다. `reload()`는 closed(appRequest) 뒤 loading이 이어진다
///   (세션 종료가 아님 — iOS는 시뮬레이터 확인, 실기기 확인 중 SMV-1899 A0-6).
/// - [accessKeyChanged]: 다른 accessKey로 `Shoplive.initialize`를 다시 불러 이전 키의 재생이 닫힘
enum ShopliveCloseReason { userAction, appRequest, accessKeyChanged, unknown }

enum ShopliveCampaignStatus { ready, live, ended, unknown }

enum ShopliveConnectionState { connecting, connected, reconnecting, disconnected, unknown }

/// 영상 화면 맞춤.
/// - [auto]: Android SDK 3.0.6+ `DEFAULT` — 창 크기로 고른다(폰 [fill], 태블릿·펼친 폴더블 [fit], 접고 펼 때 다시 고름).
///   새 플레이어의 Android 기본값이다. iOS에는 이 판정이 없어 [fill]로 적용하고 `getResizeMode()`는 [fill]을 돌려준다.
///   1.8.x 플러그인의 `auto`(서버 화면비)와 다른 뜻이다.
/// - [fill]·[fit]: 창 크기와 무관하게 그 방식으로 그린다.
enum ShopliveResizeMode { fill, fit, auto, unknown }

enum ShopliveOverlayUIMode { builtIn, hidden, unknown }

enum ShoplivePresentationStyle { fullscreen, pip }

enum ShoplivePlayerType { live, preview, unknown }

enum ShoplivePipPosition {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  middleCenter,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
  unknown,
}

enum ShoplivePipRatio { ratio1x1, ratio1x2, ratio2x3, ratio3x4, ratio9x16, unknown }

enum ShopliveNavigationAction { pip, keep, close, unknown }

enum ShopliveResultStatus { show, hide, keep }

enum ShopliveResultAlertType { alert, toast }

enum ShoplivePlaybackEventKind {
  requested,
  started,
  audioLoaded,
  rendering,
  buffering,
  rebufferingStarted,
  rebufferingEnded,
  ended,
  failed,
  unknown,
}
