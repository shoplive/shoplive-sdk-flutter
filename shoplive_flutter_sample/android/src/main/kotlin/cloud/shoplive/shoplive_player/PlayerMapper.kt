package cloud.shoplive.shoplive_player

import android.util.Log
import cloud.shoplive.player.ShopliveAnalyticsInfo
import cloud.shoplive.player.ShopliveCampaignInfo
import cloud.shoplive.player.ShopliveCampaignStatus
import cloud.shoplive.player.ShopliveCloseReason
import cloud.shoplive.player.ShopliveConnectionState
import cloud.shoplive.player.ShopliveCouponResult
import cloud.shoplive.player.ShopliveCustomActionResult
import cloud.shoplive.player.ShopliveInsets
import cloud.shoplive.player.ShopliveNavigationAction
import cloud.shoplive.player.ShopliveOverlayUIMode
import cloud.shoplive.player.ShoplivePipPosition
import cloud.shoplive.player.ShoplivePipRatio
import cloud.shoplive.player.ShoplivePlayOptions
import cloud.shoplive.player.ShoplivePlaybackEvent
import cloud.shoplive.player.ShoplivePlayerConfiguration
import cloud.shoplive.player.ShoplivePlayerEvent
import cloud.shoplive.player.ShoplivePlayerPresentationStyle
import cloud.shoplive.player.ShoplivePlayerState
import cloud.shoplive.player.ShoplivePlayerType
import cloud.shoplive.player.ShopliveResizeMode
import cloud.shoplive.player.ShopliveResultAlertType
import cloud.shoplive.player.ShopliveResultStatus
import cloud.shoplive.player.ShopliveShareInfo

/** 채널 `shoplive_player` 계약 이름(design.md rev2 §2.1·§2.4·§2.5). */
internal object PlayerContract {
    const val METHOD_CHANNEL = "shoplive_player"
    const val EVENTS_CHANNEL = "shoplive_player/events"
    const val REQUESTS_CHANNEL = "shoplive_player/requests"

    const val START = "start"
    const val PLAY = "play"
    const val STOP = "stop"
    const val CLOSE = "close"
    const val RELOAD = "reload"
    const val SEND = "send"
    const val SET_MUTED = "setMuted"
    const val IS_MUTED = "isMuted"
    const val SET_RESIZE_MODE = "setResizeMode"
    const val GET_RESIZE_MODE = "getResizeMode"
    const val SET_OVERLAY_UI = "setOverlayUI"
    const val GET_OVERLAY_UI = "getOverlayUI"
    const val ENTER_PIP = "enterPictureInPicture"
    const val EXIT_PIP = "exitPictureInPicture"
    const val IS_IN_PIP = "isInPictureInPicture"
    const val GET_STATE = "getState"
    const val GET_CURRENT_CAMPAIGN = "getCurrentCampaign"
    const val IS_RUNNING = "isRunning"
    const val SET_CONFIGURATION = "setConfiguration"
    const val GET_CONFIGURATION = "getConfiguration"
    const val SET_REQUEST_TIMEOUT = "setRequestTimeout"
    const val RESPOND_COUPON = "respondCoupon"
    const val RESPOND_CUSTOM_ACTION = "respondCustomAction"
    const val RESPOND_FALLBACK = "respondFallback"

    val METHODS = listOf(
        START, PLAY, STOP, CLOSE, RELOAD, SEND, SET_MUTED, IS_MUTED, SET_RESIZE_MODE, GET_RESIZE_MODE,
        SET_OVERLAY_UI, GET_OVERLAY_UI, ENTER_PIP, EXIT_PIP, IS_IN_PIP, GET_STATE, GET_CURRENT_CAMPAIGN,
        IS_RUNNING, SET_CONFIGURATION, GET_CONFIGURATION, SET_REQUEST_TIMEOUT, RESPOND_COUPON,
        RESPOND_CUSTOM_ACTION, RESPOND_FALLBACK,
    )

    // 인자 키
    const val CAMPAIGN_KEY = "campaignKey"
    const val PLAY_OPTIONS = "playOptions"
    const val CONFIGURATION = "configuration"
    const val COMMAND = "command"
    const val PAYLOAD = "payload"
    const val MUTED = "muted"
    const val MODE = "mode"
    const val TIMEOUT_MS = "timeoutMs"
    const val REQUEST_ID = "requestId"
    const val SUCCESS = "success"
    const val STATUS = "status"
    const val MESSAGE = "message"
    const val ALERT_TYPE = "alertType"
    const val REFERRER = "referrer"
    const val KEEP_WINDOW_STATE = "keepWindowStateOnPlayExecuted"
    const val PRESENTATION_STYLE = "presentationStyle"
}

/** Dart wire Map ↔ Shoplive player 3.0.4 타입 (순수 함수). */
internal object PlayerMapper {
    private val K = PlayerContract

    // ---- wire enum 테이블(design §2.3). Dart enum.name과 같은 camelCase ----
    /** 닫힌 이유(SDK 3.0.4 `Closed.reason`). stateChanged(closed)의 `closeReason` 값(SMV-1899 A4). */
    val CLOSE_REASON = mapOf(
        "userAction" to ShopliveCloseReason.USER_ACTION, "appRequest" to ShopliveCloseReason.APP_REQUEST,
        "accessKeyChanged" to ShopliveCloseReason.ACCESS_KEY_CHANGED,
    )
    val CAMPAIGN_STATUS = mapOf(
        "ready" to ShopliveCampaignStatus.READY, "live" to ShopliveCampaignStatus.LIVE, "ended" to ShopliveCampaignStatus.ENDED,
    )
    val CONNECTION_STATE = mapOf(
        "connecting" to ShopliveConnectionState.CONNECTING, "connected" to ShopliveConnectionState.CONNECTED,
        "reconnecting" to ShopliveConnectionState.RECONNECTING, "disconnected" to ShopliveConnectionState.DISCONNECTED,
    )
    val RESIZE_MODE = mapOf("fill" to ShopliveResizeMode.FILL, "fit" to ShopliveResizeMode.FIT)
    val OVERLAY_UI = mapOf("builtIn" to ShopliveOverlayUIMode.BUILT_IN, "hidden" to ShopliveOverlayUIMode.HIDDEN)
    val PRESENTATION_STYLE = mapOf("fullscreen" to ShoplivePlayerPresentationStyle.FULLSCREEN, "pip" to ShoplivePlayerPresentationStyle.PIP)
    val PLAYER_TYPE = mapOf("live" to ShoplivePlayerType.LIVE, "preview" to ShoplivePlayerType.PREVIEW)
    val PIP_POSITION = mapOf(
        "topLeft" to ShoplivePipPosition.TOP_LEFT, "topCenter" to ShoplivePipPosition.TOP_CENTER, "topRight" to ShoplivePipPosition.TOP_RIGHT,
        "middleLeft" to ShoplivePipPosition.MIDDLE_LEFT, "middleCenter" to ShoplivePipPosition.MIDDLE_CENTER, "middleRight" to ShoplivePipPosition.MIDDLE_RIGHT,
        "bottomLeft" to ShoplivePipPosition.BOTTOM_LEFT, "bottomCenter" to ShoplivePipPosition.BOTTOM_CENTER, "bottomRight" to ShoplivePipPosition.BOTTOM_RIGHT,
    )
    val PIP_RATIO = mapOf(
        "ratio1x1" to ShoplivePipRatio.RATIO_1X1, "ratio1x2" to ShoplivePipRatio.RATIO_1X2, "ratio2x3" to ShoplivePipRatio.RATIO_2X3,
        "ratio3x4" to ShoplivePipRatio.RATIO_3X4, "ratio9x16" to ShoplivePipRatio.RATIO_9X16,
    )
    val NAVIGATION_ACTION = mapOf(
        "pip" to ShopliveNavigationAction.PIP, "keep" to ShopliveNavigationAction.KEEP, "close" to ShopliveNavigationAction.CLOSE,
    )
    val RESULT_STATUS = mapOf("show" to ShopliveResultStatus.SHOW, "hide" to ShopliveResultStatus.HIDE, "keep" to ShopliveResultStatus.KEEP)
    val ALERT_TYPE = mapOf("alert" to ShopliveResultAlertType.ALERT, "toast" to ShopliveResultAlertType.TOAST)

    // ---- 입력 ----

    /** 생략 필드는 SDK 기본 인스턴스 값(design §2.2). */
    fun toPlayOptions(args: Args?): ShoplivePlayOptions {
        val d = ShoplivePlayOptions()
        if (args == null) return d
        return Bridge.constructing(K.PLAY_OPTIONS) {
            ShoplivePlayOptions(
                referrer = if (args.has(K.REFERRER)) args.optString(K.REFERRER) else d.referrer,
                keepWindowStateOnPlayExecuted = nonNullBool(args, K.KEEP_WINDOW_STATE) ?: d.keepWindowStateOnPlayExecuted,
                presentationStyle = args.optWireEnum(K.PRESENTATION_STYLE, PRESENTATION_STYLE) ?: d.presentationStyle,
            )
        }
    }

    /**
     * 부분 Configuration을 [current] 위에 병합(CFG-01, X-04). 하위 맵 안의 생략 필드도 현재 값 유지.
     * non-null 필드에 키+null → INVALID_ARGUMENT. nullable 필드(shareScheme·isVolumeKeyEnabled)는 키+null = 명시적 null.
     * customParameters는 맵 단위 교체. loadingAnimation·chatInputTypeface는 노출하지 않으므로 항상 현재 값 유지.
     * [drawableId]: 앱 drawable 리소스 이름 → 리소스 ID(없으면 null). Mapper가 Context를 갖지 않도록 인자로 받는다(JVM 테스트 대역 — SMV-1899 D1).
     */
    fun mergeConfiguration(current: ShoplivePlayerConfiguration, partial: Args, drawableId: (String) -> Int?): ShoplivePlayerConfiguration =
        Bridge.constructing(K.CONFIGURATION) {
            val android = partial.optArgs("android")
            val pip = partial.optArgs("pip")
            val sound = partial.optArgs("sound")
            val appearance = partial.optArgs("appearance")
            val navigation = partial.optArgs("navigation")
            val overlay = partial.optArgs("overlay")
            val cp = current.pip
            val cs = current.sound
            val ca = current.appearance
            val cn = current.navigation
            current.copy(
                type = nonNullEnum(partial, "type", PLAYER_TYPE) ?: current.type,
                pip = cp.copy(
                    isInAppPipEnabled = nonNullBool(pip, "isInAppPipEnabled") ?: cp.isInAppPipEnabled,
                    isOSPipEnabled = nonNullBool(pip, "isOSPipEnabled") ?: cp.isOSPipEnabled,
                    enterOSPipOnBackPressed = nonNullBool(android, "enterOSPipOnBackPressed") ?: cp.enterOSPipOnBackPressed,
                    defaultPosition = nonNullEnum(pip, "defaultPosition", PIP_POSITION) ?: cp.defaultPosition,
                    scale = nonNullFloat(pip, "scale") ?: cp.scale,
                    aspectRatio = nonNullEnum(pip, "aspectRatio", PIP_RATIO) ?: cp.aspectRatio,
                    padding = pip?.optArgs("padding")?.let { mergeInsets(cp.padding, it) } ?: requireNotExplicitNull(pip, "padding", cp.padding),
                    // SDK 3.0.3 신규(기본 true). 생략 = 현재 값 유지, 키+null·비Boolean = INVALID_ARGUMENT(다른 Boolean 필드와 같은 규칙)
                    isDragOutToCloseEnabled = nonNullBool(pip, "isDragOutToCloseEnabled") ?: cp.isDragOutToCloseEnabled,
                    // SDK 3.0.4 in-App PIP 버튼(SMV-1899 A3). isHidden·이미지 우선순위는 SDK가 정한다 — 브릿지는 값만 넘긴다.
                    closeButton = mergeButton(cp.closeButton, pip, "closeButton", drawableId),
                    restoreButton = mergeButton(cp.restoreButton, pip, "restoreButton", drawableId),
                ),
                sound = cs.copy(
                    muteOnStart = nonNullBool(sound, "muteOnStart") ?: cs.muteOnStart,
                    mixWithOthers = nonNullBool(sound, "mixWithOthers") ?: cs.mixWithOthers,
                    autoResumeOnFocusGained = nonNullBool(android, "autoResumeOnFocusGained") ?: cs.autoResumeOnFocusGained,
                    isVolumeKeyEnabled = if (android?.has("isVolumeKeyEnabled") == true) android.optBool("isVolumeKeyEnabled") else cs.isVolumeKeyEnabled,
                ),
                appearance = ca.copy(
                    indicatorColor = argbColor(appearance) ?: ca.indicatorColor,
                    isStatusBarVisible = nonNullBool(android, "isStatusBarVisible") ?: ca.isStatusBarVisible,
                    allowScreenCapture = nonNullBool(android, "allowScreenCapture") ?: ca.allowScreenCapture,
                ),
                navigation = cn.copy(
                    actionOnNavigation = nonNullEnum(navigation, "actionOnNavigation", NAVIGATION_ACTION) ?: cn.actionOnNavigation,
                    shareScheme = if (navigation?.has("shareScheme") == true) navigation.optString("shareScheme") else cn.shareScheme,
                    closeWhenAppDestroyed = nonNullBool(android, "closeWhenAppDestroyed") ?: cn.closeWhenAppDestroyed,
                    // SDK 3.0.4(기본 false). 생략 = 현재 값 유지, 키+null·비Boolean = INVALID_ARGUMENT(iOS와 같은 키·규칙 — SMV-1899 A2-4)
                    isCustomShareEnabled = nonNullBool(navigation, "isCustomShareEnabled") ?: cn.isCustomShareEnabled,
                ),
                overlay = current.overlay.copy(ui = nonNullEnum(overlay, "ui", OVERLAY_UI) ?: current.overlay.ui),
                customParameters = partial.optStringStringMap("customParameters") ?: requireNotExplicitNull(partial, "customParameters", current.customParameters),
            )
        }

    /**
     * 버튼 맵 병합: 키 생략 = 현재 값, 키+null·비맵 = INVALID_ARGUMENT(padding과 같은 규칙). isHidden은 non-null Boolean.
     * nativeImageName: 생략 = 현재 이미지 유지, 키+null = 해제(nullable 필드 규칙), 비문자열 = INVALID_ARGUMENT.
     */
    private fun mergeButton(
        cur: ShoplivePlayerConfiguration.ButtonOptions,
        pip: Args?,
        key: String,
        drawableId: (String) -> Int?,
    ): ShoplivePlayerConfiguration.ButtonOptions {
        val a = pip?.optArgs(key) ?: return requireNotExplicitNull(pip, key, cur)
        val imageResId = if (a.has(NATIVE_IMAGE_NAME)) a.optString(NATIVE_IMAGE_NAME)?.let { resolveImage(key, it, drawableId) } else cur.imageResId
        return cur.copy(isHidden = nonNullBool(a, "isHidden") ?: cur.isHidden, imageResId = imageResId)
    }

    /**
     * 해석 실패('' · 없는 이름 · 0)는 실패로 던지지 않는다(§1(3)): 경고 1줄 후 이미지 없음 → SDK가 서버 에셋 → 기본으로 그린다.
     * 0 대신 null을 넘긴다(SDK도 0을 미지정으로 보지만 계약상 "없음"은 null).
     */
    private fun resolveImage(key: String, name: String, drawableId: (String) -> Int?): Int? {
        val id = name.takeIf { it.isNotEmpty() }?.let(drawableId)?.takeIf { it != 0 }
        if (id == null) {
            Log.w(TAG, "configuration.pip.$key.$NATIVE_IMAGE_NAME '$name' is not a drawable resource of the app; using the server asset or the SDK default")
        }
        return id
    }

    private const val NATIVE_IMAGE_NAME = "nativeImageName"
    private const val TAG = "ShoplivePlayer"

    private fun mergeInsets(cur: ShopliveInsets, a: Args): ShopliveInsets = ShopliveInsets(
        nonNullInt(a, "left") ?: cur.left,
        nonNullInt(a, "top") ?: cur.top,
        nonNullInt(a, "right") ?: cur.right,
        nonNullInt(a, "bottom") ?: cur.bottom,
    )

    /**
     * ARGB color as an unsigned 32-bit value (Dart `0xFF00FF00` = 4278255360 exceeds Int). Signed Int input is
     * accepted too; anything outside -2^31..2^32-1 is INVALID_ARGUMENT. Output is always unsigned (contract, iOS same).
     */
    private fun argbColor(a: Args?): Int? {
        val key = "indicatorColor"
        val v = a?.optLong(key) ?: return requireNotExplicitNull(a, key, null)
        if (v < Int.MIN_VALUE || v > ARGB_MASK) throw BridgeArgumentException(key, "ARGB 0..0xFFFFFFFF", "out of range")
        return v.toInt()
    }

    private const val ARGB_MASK = 0xFFFFFFFFL

    private fun <T> requireNotExplicitNull(a: Args?, key: String, keep: T): T {
        if (a != null && a.has(key)) throw BridgeArgumentException(key, "non-null value", "null")
        return keep
    }

    private fun nonNullBool(a: Args?, key: String): Boolean? = a?.optBool(key) ?: requireNotExplicitNull(a, key, null)
    private fun nonNullInt(a: Args?, key: String): Int? = a?.optInt(key) ?: requireNotExplicitNull(a, key, null)
    private fun nonNullFloat(a: Args?, key: String): Float? = a?.optFloat(key) ?: requireNotExplicitNull(a, key, null)
    private fun <E> nonNullEnum(a: Args?, key: String, table: Map<String, E>): E? = a?.optWireEnum(key, table)

    // alertType 생략 = TOAST(iOS와 같은 값, SMV-1749 결정). SDK 3.0.3 생성자 기본값(ALERT)이나 null(웹 기본)을 쓰지 않는다.
    fun toCouponResult(couponId: String, a: Args): ShopliveCouponResult = Bridge.constructing(K.STATUS) {
        ShopliveCouponResult(
            couponId,
            a.requireBool(K.SUCCESS),
            a.optString(K.MESSAGE),
            a.requireWireEnum(K.STATUS, RESULT_STATUS),
            a.optWireEnum(K.ALERT_TYPE, ALERT_TYPE) ?: ShopliveResultAlertType.TOAST,
        )
    }

    fun toCustomActionResult(id: String, a: Args): ShopliveCustomActionResult = Bridge.constructing(K.STATUS) {
        ShopliveCustomActionResult(
            id,
            a.requireBool(K.SUCCESS),
            a.optString(K.MESSAGE),
            a.requireWireEnum(K.STATUS, RESULT_STATUS),
            a.optWireEnum(K.ALERT_TYPE, ALERT_TYPE) ?: ShopliveResultAlertType.TOAST,
        )
    }

    // ---- 출력 ----

    fun configurationToWire(c: ShoplivePlayerConfiguration): Map<String, Any?> = mapOf(
        "type" to wireOf(c.type, PLAYER_TYPE),
        "pip" to mapOf(
            "isInAppPipEnabled" to c.pip.isInAppPipEnabled,
            "isOSPipEnabled" to c.pip.isOSPipEnabled,
            "defaultPosition" to wireOf(c.pip.defaultPosition, PIP_POSITION),
            "scale" to c.pip.scale.toDouble(),
            "aspectRatio" to wireOf(c.pip.aspectRatio, PIP_RATIO),
            "padding" to mapOf("left" to c.pip.padding.left, "top" to c.pip.padding.top, "right" to c.pip.padding.right, "bottom" to c.pip.padding.bottom),
            "isDragOutToCloseEnabled" to c.pip.isDragOutToCloseEnabled,
            // 버튼은 isHidden만(nativeImageName은 쓰기 전용 — iOS UIImage를 이름으로 되돌릴 수 없어 양 OS 같은 wire, SMV-1899 D1)
            "closeButton" to mapOf("isHidden" to c.pip.closeButton.isHidden),
            "restoreButton" to mapOf("isHidden" to c.pip.restoreButton.isHidden),
        ),
        "sound" to mapOf("muteOnStart" to c.sound.muteOnStart, "mixWithOthers" to c.sound.mixWithOthers),
        "appearance" to mapOf("indicatorColor" to (c.appearance.indicatorColor.toLong() and ARGB_MASK)),
        "navigation" to mapOf(
            "actionOnNavigation" to wireOf(c.navigation.actionOnNavigation, NAVIGATION_ACTION),
            "shareScheme" to c.navigation.shareScheme,
            "isCustomShareEnabled" to c.navigation.isCustomShareEnabled,
        ),
        "overlay" to mapOf("ui" to wireOf(c.overlay.ui, OVERLAY_UI)),
        "customParameters" to c.customParameters,
        "android" to mapOf(
            "enterOSPipOnBackPressed" to c.pip.enterOSPipOnBackPressed,
            "isVolumeKeyEnabled" to c.sound.isVolumeKeyEnabled,
            "autoResumeOnFocusGained" to c.sound.autoResumeOnFocusGained,
            "isStatusBarVisible" to c.appearance.isStatusBarVisible,
            "allowScreenCapture" to c.appearance.allowScreenCapture,
            "closeWhenAppDestroyed" to c.navigation.closeWhenAppDestroyed,
        ),
    )

    fun campaignToWire(info: ShopliveCampaignInfo?): Map<String, Any?>? = info?.let(::campaignInfoToWire)

    private fun campaignInfoToWire(info: ShopliveCampaignInfo): Map<String, Any?> =
        mapOf("campaignKey" to info.campaignKey, "title" to info.title, "status" to wireOf(info.status, CAMPAIGN_STATUS))

    /**
     * 상태 → wire 이름(Dart ShoplivePlayerState.name). SDK 3.0.4에서 상태가 sealed(`Closed(reason)`)가 되어 상수 테이블·wireOf
     * 동등 비교로는 Closed를 'unknown'으로 보낸다 → 하위 타입 전수 when. else를 두지 않는다: SDK가 상태를 더하면 컴파일 오류로
     * 드러난다(SMV-1899 A0-1). getState·stateChanged가 이 함수 하나를 쓴다. 사유는 stateChanged에만 싣는다(getState는 'closed' — D2).
     */
    fun stateToWire(state: ShoplivePlayerState): String = when (state) {
        ShoplivePlayerState.Idle -> "idle"
        ShoplivePlayerState.Loading -> "loading"
        ShoplivePlayerState.Playing -> "playing"
        ShoplivePlayerState.Paused -> "paused"
        ShoplivePlayerState.InAppPIP -> "inAppPip"
        is ShoplivePlayerState.Closed -> "closed"
    }

    /** stateChanged: closed일 때만 `closeReason` 키(SMV-1899 A4 — 다른 상태엔 키 없음). */
    private fun stateChangedToWire(state: ShoplivePlayerState): Map<String, Any?> {
        val base = mapOf(TYPE to "stateChanged", "state" to stateToWire(state))
        return if (state is ShoplivePlayerState.Closed) base + ("closeReason" to wireOf(state.reason, CLOSE_REASON)) else base
    }

    fun eventToWire(event: ShoplivePlayerEvent): Map<String, Any?> = when (event) {
        is ShoplivePlayerEvent.StateChanged -> stateChangedToWire(event.state)
        is ShoplivePlayerEvent.CampaignStatusChanged -> mapOf(TYPE to "campaignStatusChanged", "status" to wireOf(event.status, CAMPAIGN_STATUS))
        is ShoplivePlayerEvent.CampaignInfoReceived -> mapOf(TYPE to "campaignInfoReceived") + campaignInfoToWire(event.info)
        is ShoplivePlayerEvent.ConnectionStateChanged -> mapOf(TYPE to "connectionStateChanged", "state" to wireOf(event.state, CONNECTION_STATE))
        is ShoplivePlayerEvent.Playback -> playbackToWire(event.event)
        is ShoplivePlayerEvent.Error -> mapOf(TYPE to "error", "error" to Bridge.errorToWire(event.error))
        is ShoplivePlayerEvent.Analytics -> analyticsToWire(event.info)
        // SDK 3.0.4: payload 없는 커맨드(LOGIN_REQUIRED 등)는 null로 온다 → iOS(PlayerMapper.swift nil → {})와 같은 {}로(SMV-1899 D4)
        is ShoplivePlayerEvent.WebCommandReceived ->
            mapOf(TYPE to "webCommandReceived", "name" to event.name, "payload" to ValueNormalizer.normalize(event.payload ?: emptyMap<String, Any?>()))
        // TODO(SDP-VERIFY): 요확인 — Android SDK가 1탭을 2건으로 내는 경로(웹 두 입구가 100ms 넘게 떨어짐) 실측. 브릿지는 1건=1건 중계(디바운스 없음) · 근거 SMV-1899
        is ShoplivePlayerEvent.ShareRequested -> mapOf(TYPE to "shareRequested") + shareInfoToWire(event.info)
        is ShoplivePlayerEvent.UserNameUpdateRequested ->
            mapOf(TYPE to "userNameUpdateRequested", "payload" to ValueNormalizer.normalize(event.payload))
        else -> unknownToWire(event)
    }

    /** 다섯 키를 항상 싣고 없는 값은 null(campaignInfoReceived와 같은 관례, iOS와 같은 wire — SMV-1899 A1-3). */
    private fun shareInfoToWire(i: ShopliveShareInfo): Map<String, Any?> = mapOf(
        "url" to i.url, "campaignKey" to i.campaignKey, "title" to i.title, "descriptionText" to i.descriptionText, "thumbnailUrl" to i.thumbnailUrl,
    )

    private fun playbackToWire(e: ShoplivePlaybackEvent): Map<String, Any?> {
        val kind = when (e) {
            is ShoplivePlaybackEvent.Requested -> "requested"
            is ShoplivePlaybackEvent.Started -> "started"
            is ShoplivePlaybackEvent.AudioLoaded -> "audioLoaded"
            is ShoplivePlaybackEvent.Rendering -> "rendering"
            is ShoplivePlaybackEvent.Buffering -> "buffering"
            is ShoplivePlaybackEvent.RebufferingStarted -> "rebufferingStarted"
            is ShoplivePlaybackEvent.RebufferingEnded -> "rebufferingEnded"
            is ShoplivePlaybackEvent.Ended -> "ended"
            is ShoplivePlaybackEvent.Failed -> "failed"
            else -> WIRE_UNKNOWN
        }
        val base = mapOf(TYPE to "playback", "event" to kind, "timestampMs" to e.timestampMs)
        return if (e is ShoplivePlaybackEvent.Failed) base + mapOf("code" to e.code, "message" to e.message) else base
    }

    private fun analyticsToWire(i: ShopliveAnalyticsInfo): Map<String, Any?> = mapOf(
        TYPE to "analytics",
        "campaignKey" to i.campaignKey,
        "isPlaying" to i.isPlaying,
        "isMuted" to i.isMuted,
        "durationMs" to i.durationMs,
        "campaign" to i.campaign?.let { mapOf("title" to it.title, "status" to wireOf(it.status, CAMPAIGN_STATUS)) },
        "brand" to i.brand?.let { mapOf("name" to it.name, "identifier" to it.identifier, "imageUrl" to it.imageUrl) },
    )

    /** 매핑 불가 하위 타입 → {unknown, rawType}(N-03). rawType은 하위 타입 이름 lowerCamel. */
    fun unknownToWire(event: Any): Map<String, Any?> =
        mapOf(TYPE to WIRE_UNKNOWN, "rawType" to event.javaClass.simpleName.replaceFirstChar { it.lowercase() })

    fun navigationToWire(url: String): Map<String, Any?> = mapOf(TYPE to "navigation", "url" to url)

    fun couponToWire(requestId: String, couponId: String): Map<String, Any?> =
        mapOf(TYPE to "coupon", K.REQUEST_ID to requestId, "couponId" to couponId)

    fun customWebActionToWire(requestId: String, id: String, actionType: String, payload: Any?): Map<String, Any?> =
        mapOf(TYPE to "customWebAction", K.REQUEST_ID to requestId, "id" to id, "actionType" to actionType, "payload" to ValueNormalizer.normalize(payload))

    private const val TYPE = EventEmitter.KEY_TYPE
}
