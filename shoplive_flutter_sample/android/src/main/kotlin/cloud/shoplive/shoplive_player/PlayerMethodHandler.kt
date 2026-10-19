package cloud.shoplive.shoplive_player

import cloud.shoplive.player.ShopliveOverlayUIMode
import cloud.shoplive.player.ShoplivePlayOptions
import cloud.shoplive.player.ShoplivePlayer
import cloud.shoplive.player.ShoplivePlayerConfiguration
import cloud.shoplive.player.ShoplivePlayerControlling
import cloud.shoplive.player.ShoplivePlayerDelegate
import cloud.shoplive.player.ShoplivePlayerEvent
import cloud.shoplive.player.ShoplivePlayerPresentationStyle
import cloud.shoplive.player.ShoplivePlayerState
import cloud.shoplive.player.ShopliveResizeMode
import java.lang.ref.WeakReference

/** ShoplivePlayer 위임 경계(테스트에서 대체). ShoplivePlayerControlling + start/close/isRunning. */
internal interface PlayerPort : ShoplivePlayerControlling {
    val isRunning: Boolean
    fun start(campaignKey: String, options: ShoplivePlayOptions)
    fun start(campaignKey: String, options: ShoplivePlayOptions, configuration: ShoplivePlayerConfiguration)
    fun close()
}

internal class SdkPlayerPort(private val player: ShoplivePlayer) : PlayerPort, ShoplivePlayerControlling by player {
    override val isRunning: Boolean get() = player.isRunning
    override fun start(campaignKey: String, options: ShoplivePlayOptions) = player.start(campaignKey, options)
    override fun start(campaignKey: String, options: ShoplivePlayOptions, configuration: ShoplivePlayerConfiguration) =
        player.start(campaignKey, options, configuration)
    override fun close() = player.close()
}

/**
 * 채널 `shoplive_player` 메서드 처리(design.md rev2 §2.4·§4.2). [H]는 호스트 화면(Android: Activity) — JVM 테스트에서 대체.
 *
 * 인스턴스 수명: 인스턴스는 start에서만 만들고, 한 번 start된 인스턴스는 다음 start에 재사용하지 않는다([portForStart]).
 * 호스트 detach 시 비실행 인스턴스 해제.
 * 설정 보존(R2-N1): 마지막 확정 configuration·resizeMode·overlayUI를 인스턴스와 별도로 보관해 새 인스턴스에 이관.
 * 모든 메서드는 메인 스레드에서 호출된다(MethodChannel).
 */
internal class PlayerMethodHandler<H : Any>(
    private val registry: PendingRequestRegistry,
    private val portFactory: (H) -> PlayerPort,
    private val liveDelegate: () -> ShoplivePlayerDelegate,
) {
    private val k = PlayerContract

    private var host: H? = null
    private var port: PlayerPort? = null
    private var boundHost: WeakReference<H>? = null

    private var savedConfiguration: ShoplivePlayerConfiguration? = null
    private var savedResizeMode: ShopliveResizeMode? = null
    private var savedOverlayUI: ShopliveOverlayUIMode? = null

    fun attachHost(newHost: H) {
        host = newHost
    }

    /** 구성 변경·Activity 파괴(R-04): 비실행 인스턴스만 해제(설정은 보관), 실행 중이면 유지(T-04). */
    fun detachHost() {
        host = null
        val p = port ?: return
        if (!p.isRunning) release(p)
    }

    /** 엔진 detach(X-01): 세션은 유지하고 요청에는 DetachedDelegate가 폴백 응답. 설정·참조는 버린다. */
    fun onEngineDetached() {
        // TODO(SDP-VERIFY): 요확인 — 엔진 재attach 후 새 플러그인 인스턴스는 이전 엔진이 남긴 세션(closeWhenAppDestroyed=false)을 제어·종료할 수 없음. SDK 전역 세션 종료 경로 유무 · 근거 DRAFT-flutter-sdk-302-android/R-03 · 자동 통과 금지(실측)
        port?.delegate = DetachedDelegate
        port = null
        boundHost = null
        host = null
        savedConfiguration = null
        savedResizeMode = null
        savedOverlayUI = null
    }

    /**
     * 인스턴스 생성은 start에서만 한다(pair #19). 인스턴스가 없으면 조회는 기본/보관값, 설정은 PlayerSettings에만 저장,
     * 세션 명령은 NOT_RUNNING, close는 no-op success.
     */
    fun handle(method: String, args: Args): Any? = when (method) {
        k.START -> start(args)
        k.PLAY -> running().play(args.requireString(k.CAMPAIGN_KEY), PlayerMapper.toPlayOptions(args.optArgs(k.PLAY_OPTIONS))).let { null }
        k.STOP -> running().stop().let { null }
        // TODO(SDP-VERIFY): 요확인 — close 이후 응답 대기 중인 쿠폰/커스텀 요청에 respond(타임아웃 폴백 포함)를 호출해도 안전한지 · 근거 DRAFT-flutter-sdk-302-android/T-02 · 자동 통과 금지(실측)
        k.CLOSE -> port?.close().let { null } // 인스턴스 없으면 멱등 no-op
        k.RELOAD -> running().reload().let { null }
        k.SEND -> {
            val command = args.requireString(k.COMMAND)
            val payload = args.optStringKeyMap(k.PAYLOAD) ?: emptyMap()
            running().send(command, payload).let { null }
        }
        k.SET_MUTED -> {
            val muted = args.requireBool(k.MUTED)
            running().isMuted = muted
            null
        }
        k.IS_MUTED -> port?.isMuted ?: false
        k.SET_RESIZE_MODE -> {
            val mode = args.requireWireEnum(k.MODE, PlayerMapper.RESIZE_MODE)
            port?.resizeMode = mode
            savedResizeMode = mode
            null
        }
        k.GET_RESIZE_MODE -> wireOf(port?.resizeMode ?: savedResizeMode ?: DEFAULT_RESIZE_MODE, PlayerMapper.RESIZE_MODE)
        k.SET_OVERLAY_UI -> {
            val mode = args.requireWireEnum(k.MODE, PlayerMapper.OVERLAY_UI)
            port?.overlayUI = mode
            savedOverlayUI = mode
            null
        }
        k.GET_OVERLAY_UI -> wireOf(port?.overlayUI ?: savedOverlayUI ?: DEFAULT_OVERLAY_UI, PlayerMapper.OVERLAY_UI)
        k.ENTER_PIP -> running().enterPictureInPicture().let { null }
        k.EXIT_PIP -> running().exitPictureInPicture().let { null }
        k.IS_IN_PIP -> port?.isInPictureInPicture ?: false
        k.GET_STATE -> wireOf(port?.state ?: ShoplivePlayerState.IDLE, PlayerMapper.PLAYER_STATE)
        k.GET_CURRENT_CAMPAIGN -> PlayerMapper.campaignToWire(port?.currentCampaign)
        k.IS_RUNNING -> port?.isRunning ?: false
        k.SET_CONFIGURATION -> {
            val merged = PlayerMapper.mergeConfiguration(currentConfiguration(), args.requireArgs(k.CONFIGURATION))
            port?.configuration = merged
            savedConfiguration = merged
            null
        }
        // 다음 start에 쓰일 설정(보관값 우선). 실행 중 SET은 SDK가 무시하므로(ConfigurationGuard) 인스턴스 값이 아니라 보관값을 돌려준다(iOS 같은 의미).
        k.GET_CONFIGURATION -> PlayerMapper.configurationToWire(currentConfiguration())
        k.SET_REQUEST_TIMEOUT -> registry.setTimeoutMs(
            args.optLong(k.TIMEOUT_MS) ?: throw BridgeArgumentException(k.TIMEOUT_MS, "Int", "missing"),
        ).let { null }
        k.RESPOND_COUPON -> respondCoupon(args)
        k.RESPOND_CUSTOM_ACTION -> respondCustomAction(args)
        k.RESPOND_FALLBACK -> registry.take(args.requireString(k.REQUEST_ID))?.let { it.respondFallback(); true } ?: false
        else -> throw MethodNotImplemented
    }

    // ---- start (design §2.4 사전검증 순서) ----

    private fun start(args: Args): Any? {
        val currentHost = host ?: throw noHost()
        val campaignKey = args.requireString(k.CAMPAIGN_KEY)
        val options = PlayerMapper.toPlayOptions(args.optArgs(k.PLAY_OPTIONS))
        val partial = args.optArgs(k.CONFIGURATION)
        val current = currentConfiguration()
        val effective = partial?.let { PlayerMapper.mergeConfiguration(current, it) } ?: current
        if (options.presentationStyle == ShoplivePlayerPresentationStyle.PIP && !effective.pip.isInAppPipEnabled) {
            // B-09: SDK는 Log.w 후 조용히 거부하므로 브릿지가 사전 거부(개발자 확정). 검증 실패 시 인스턴스를 만들지 않는다.
            throw BridgeArgumentException("${k.PLAY_OPTIONS}.${k.PRESENTATION_STYLE}", "fullscreen unless pip.isInAppPipEnabled", "pip")
        }
        // 여기까지(호스트·키·B-09 검증)가 실패하면 실행 중 세션은 그대로 둔다. 아래부터 이전 세션을 교체한다.
        val replacedRunning = port?.isRunning == true
        val p = portForStart(currentHost)
        // TODO(SDP-VERIFY): 요확인 — launch context(Activity)가 GC됐거나 LifecycleOwner가 아니면 SDK가 Log.w 후 조용히 거부(브릿지 감지 불가) · 근거 DRAFT-flutter-sdk-302-android/NR-02 · 자동 통과 금지(실측)
        try {
            if (partial == null) {
                p.start(campaignKey, options)
            } else {
                p.start(campaignKey, options, effective)
                savedConfiguration = effective
            }
        } catch (t: Throwable) {
            // 이전 세션은 이미 닫혔는데(closed 이벤트는 retire에서 막음) 새 세션 시작이 예외로 실패: Dart 상태가 낡지 않게 closed 1회.
            if (replacedRunning) notifyClosed(p)
            throw t
        }
        return null
    }

    private fun notifyClosed(p: PlayerPort) = Bridge.guardCallback(TAG, "notifyClosed") {
        p.delegate?.onEvent(p, ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.CLOSED))
    }

    /**
     * start마다 effective configuration이 새 세션에 적용되도록 인스턴스를 고른다(SMV-1749, T-01·T-04 해소).
     * SDK 3.0.3 근거(javap): ConfigurationGuard.set은 state == IDLE일 때만 값을 받고(그 외 Log.w 후 무시 — start의 설정 인자 포함),
     * state는 생성 시에만 IDLE이며 close 후에는 CLOSED로 남는다 → 한 번 start된 인스턴스는 설정을 바꿀 수 없다.
     * SessionRegistry는 인스턴스별 등록(Map)이라 새 인스턴스 생성에 제약이 없다.
     * 그래서 IDLE이 아니거나 호스트가 바뀐 인스턴스는 해제 후 close하고 현재 호스트로 새로 만든다.
     */
    private fun portForStart(currentHost: H): PlayerPort {
        val p = port ?: return create(currentHost)
        if (p.state == ShoplivePlayerState.IDLE && boundHost?.get() === currentHost) return p
        retire(p)
        return create(currentHost)
    }

    /**
     * 교체되는 인스턴스 정리. DetachedDelegate를 먼저 붙인 뒤 close한다 — 이전 세션의 closed·늦은 이벤트가 새 세션 이벤트와
     * 섞여 Dart에 가지 않게 하고(iOS와 같은 의미), 이전 세션의 쿠폰·커스텀 요청은 폴백으로 1회 응답한다 — 대기 중인 것은
     * 여기서 flushAll(새 세션은 아직 시작 전이라 대기 요청은 모두 이전 세션 것), 이후 도착분은 DetachedDelegate.
     * close는 인스턴스 상태를 동기로 끝낸다(endSession: CLOSED·SessionRegistry.remove·delegate=null). 화면(Activity) 종료는 비동기.
     */
    private fun retire(p: PlayerPort) {
        release(p)
        registry.flushAll()
        // TODO(SDP-VERIFY): 요확인 — 이전 전체화면 Activity finish(비동기)와 새 start의 Activity 실행이 겹칠 때 화면 전환(특히 같은 campaignKey) 실측 · 근거 SMV-1749
        if (p.isRunning) p.close() // SDK isRunning = state ∉ {IDLE, CLOSED}. 그 밖의 close는 SDK에서 no-op(sessionToken null)
    }

    // ---- 인스턴스 ----

    /** 세션 명령: 인스턴스가 없거나 비실행이면 NOT_RUNNING(NR-01 — play·setMuted·enterPiP는 SDK 근거, stop·send·exitPiP·reload는 브릿지 정책). */
    private fun running(): PlayerPort {
        val p = port
        if (p == null || !p.isRunning) throw BridgeStateException(BridgeErrorCode.NOT_RUNNING, "player is not running")
        return p
    }

    private fun create(forHost: H): PlayerPort {
        val p = portFactory(forHost)
        savedConfiguration?.let { p.configuration = it }
        savedResizeMode?.let { p.resizeMode = it }
        savedOverlayUI?.let { p.overlayUI = it }
        p.delegate = liveDelegate()
        port = p
        boundHost = WeakReference(forHost)
        return p
    }

    private fun release(p: PlayerPort) {
        p.delegate = DetachedDelegate
        if (port === p) {
            port = null
            boundHost = null
        }
    }

    /** 병합 기준: 보관값 → 인스턴스 값 → SDK 기본 인스턴스(R2-N1, pair #19). */
    private fun currentConfiguration(): ShoplivePlayerConfiguration =
        savedConfiguration ?: port?.configuration ?: ShoplivePlayerConfiguration()

    private fun noHost() = BridgeStateException(BridgeErrorCode.NO_HOST_SCREEN, "no host screen (Activity) attached")

    // ---- respond (C-4) ----

    private fun respondCoupon(args: Args): Boolean {
        val id = args.requireString(k.REQUEST_ID)
        val pending = registry.peek(id) ?: return false
        if (pending !is PendingRequest.Coupon) throw kindMismatch()
        val result = PlayerMapper.toCouponResult(pending.couponId, args) // 인자 오류면 entry 유지(타임아웃 폴백 보장)
        registry.take(id) ?: return false
        Bridge.guardCallback(TAG, "respondCoupon") { pending.respond(result) }
        return true
    }

    private fun respondCustomAction(args: Args): Boolean {
        val id = args.requireString(k.REQUEST_ID)
        val pending = registry.peek(id) ?: return false
        if (pending !is PendingRequest.CustomAction) throw kindMismatch()
        val result = PlayerMapper.toCustomActionResult(pending.id, args)
        registry.take(id) ?: return false
        Bridge.guardCallback(TAG, "respondCustomAction") { pending.respond(result) }
        return true
    }

    private fun kindMismatch() = BridgeArgumentException(k.REQUEST_ID, "request id of matching kind", "other kind")

    companion object {
        private const val TAG = "ShoplivePlayerHandler"

        // 인스턴스가 없을 때 조회 기본값 = ShoplivePlayer(Context) 생성자 초기값(javap -c: 104 getstatic ShopliveResizeMode.FILL → putfield resizeMode,
        // 110 getstatic ShopliveOverlayUIMode.BUILT_IN → putfield overlayUI). SDK에 이 값을 읽을 공개 기본 인스턴스가 없어 상수로 둔다.
        // configuration 기본값은 ShoplivePlayerConfiguration() 기본 생성자에서 읽는다(currentConfiguration).
        // TODO(SDP-VERIFY): 요확인 — SDK 버전 업 시 ShoplivePlayer 생성자 초기 resizeMode/overlayUI가 바뀌면 이 상수와 어긋남 · 근거 DRAFT-flutter-sdk-302-android/CFG-02 · 자동 통과 금지(SDK 업데이트 시 javap 재확인)
        private val DEFAULT_RESIZE_MODE = ShopliveResizeMode.FILL
        private val DEFAULT_OVERLAY_UI = ShopliveOverlayUIMode.BUILT_IN
    }
}
