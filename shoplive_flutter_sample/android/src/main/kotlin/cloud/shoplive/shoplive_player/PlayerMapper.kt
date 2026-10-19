package cloud.shoplive.shoplive_player

import cloud.shoplive.player.ShopliveAnalyticsInfo
import cloud.shoplive.player.ShopliveCampaignInfo
import cloud.shoplive.player.ShopliveCampaignStatus
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

/** Dart wire Map ↔ Shoplive player 3.0.3 타입 (순수 함수). */
internal object PlayerMapper {
    private val K = PlayerContract

    // ---- wire enum 테이블(design §2.3). Dart enum.name과 같은 camelCase ----
    val PLAYER_STATE = mapOf(
        "idle" to ShoplivePlayerState.IDLE, "loading" to ShoplivePlayerState.LOADING, "playing" to ShoplivePlayerState.PLAYING,
        "paused" to ShoplivePlayerState.PAUSED, "inAppPip" to ShoplivePlayerState.IN_APP_PIP, "closed" to ShoplivePlayerState.CLOSED,
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
     */
    fun mergeConfiguration(current: ShoplivePlayerConfiguration, partial: Args): ShoplivePlayerConfiguration =
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
                ),
                overlay = current.overlay.copy(ui = nonNullEnum(overlay, "ui", OVERLAY_UI) ?: current.overlay.ui),
                customParameters = partial.optStringStringMap("customParameters") ?: requireNotExplicitNull(partial, "customParameters", current.customParameters),
            )
        }

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

    // SDK 3.0.3에서 결과 타입의 alertType 기본값이 null→ALERT로 바뀌었다. 브릿지는 생략 시 null을 명시 전달하므로($default 미적용) 3.0.2 동작 유지.
    // TODO(SDP-VERIFY): 요확인 — alertType 생략 시 기본값(현재 Android=null 웹 기본, iOS=.toast) 3.0.3 네이티브 기본 ALERT로 맞출지 사용자 결정 대기 · 근거 SMV-1749
    fun toCouponResult(couponId: String, a: Args): ShopliveCouponResult = Bridge.constructing(K.STATUS) {
        ShopliveCouponResult(
            couponId,
            a.requireBool(K.SUCCESS),
            a.optString(K.MESSAGE),
            a.requireWireEnum(K.STATUS, RESULT_STATUS),
            a.optWireEnum(K.ALERT_TYPE, ALERT_TYPE),
        )
    }

    fun toCustomActionResult(id: String, a: Args): ShopliveCustomActionResult = Bridge.constructing(K.STATUS) {
        ShopliveCustomActionResult(
            id,
            a.requireBool(K.SUCCESS),
            a.optString(K.MESSAGE),
            a.requireWireEnum(K.STATUS, RESULT_STATUS),
            a.optWireEnum(K.ALERT_TYPE, ALERT_TYPE),
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
        ),
        "sound" to mapOf("muteOnStart" to c.sound.muteOnStart, "mixWithOthers" to c.sound.mixWithOthers),
        "appearance" to mapOf("indicatorColor" to (c.appearance.indicatorColor.toLong() and ARGB_MASK)),
        "navigation" to mapOf("actionOnNavigation" to wireOf(c.navigation.actionOnNavigation, NAVIGATION_ACTION), "shareScheme" to c.navigation.shareScheme),
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

    fun eventToWire(event: ShoplivePlayerEvent): Map<String, Any?> = when (event) {
        is ShoplivePlayerEvent.StateChanged -> mapOf(TYPE to "stateChanged", "state" to wireOf(event.state, PLAYER_STATE))
        is ShoplivePlayerEvent.CampaignStatusChanged -> mapOf(TYPE to "campaignStatusChanged", "status" to wireOf(event.status, CAMPAIGN_STATUS))
        is ShoplivePlayerEvent.CampaignInfoReceived -> mapOf(TYPE to "campaignInfoReceived") + campaignInfoToWire(event.info)
        is ShoplivePlayerEvent.ConnectionStateChanged -> mapOf(TYPE to "connectionStateChanged", "state" to wireOf(event.state, CONNECTION_STATE))
        is ShoplivePlayerEvent.Playback -> playbackToWire(event.event)
        is ShoplivePlayerEvent.Error -> mapOf(TYPE to "error", "error" to Bridge.errorToWire(event.error))
        is ShoplivePlayerEvent.Analytics -> analyticsToWire(event.info)
        is ShoplivePlayerEvent.WebCommandReceived ->
            mapOf(TYPE to "webCommandReceived", "name" to event.name, "payload" to ValueNormalizer.normalize(event.payload))
        is ShoplivePlayerEvent.UserNameUpdateRequested ->
            mapOf(TYPE to "userNameUpdateRequested", "payload" to ValueNormalizer.normalize(event.payload))
        else -> unknownToWire(event)
    }

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
