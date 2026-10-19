package cloud.shoplive.shoplive_player

import cloud.shoplive.player.ShopliveCampaignInfo
import cloud.shoplive.player.ShopliveCampaignStatus
import cloud.shoplive.player.ShopliveCouponResult
import cloud.shoplive.player.ShopliveCustomActionResult
import cloud.shoplive.player.ShopliveOverlayUIMode
import cloud.shoplive.player.ShoplivePlayOptions
import cloud.shoplive.player.ShoplivePlayerConfiguration
import cloud.shoplive.player.ShoplivePlayerDelegate
import cloud.shoplive.player.ShoplivePlayerPresentationStyle
import cloud.shoplive.player.ShoplivePlayerState
import cloud.shoplive.player.ShoplivePlayerType
import cloud.shoplive.player.ShopliveResizeMode
import cloud.shoplive.player.ShopliveResultStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

internal class FakePort(var running: Boolean = false) : PlayerPort {
    val calls = mutableListOf<String>()
    /** SDK 3.0.3 모델: 생성 시에만 IDLE, start 이후 실행 중이 아니면 CLOSED(되돌아가지 않음). */
    var started = running
    var lastOptions: ShoplivePlayOptions? = null
    var startedWithConfiguration: ShoplivePlayerConfiguration? = null
    var campaign: ShopliveCampaignInfo? = null

    override val isRunning: Boolean get() = running
    override var delegate: ShoplivePlayerDelegate? = null
    override var configuration: ShoplivePlayerConfiguration = ShoplivePlayerConfiguration()
        set(value) { calls += "setConfiguration"; field = value }
    override var isMuted: Boolean = false
        set(value) { calls += "setMuted"; field = value }
    override var resizeMode: ShopliveResizeMode = ShopliveResizeMode.FILL
        set(value) { calls += "setResizeMode"; field = value }
    override var overlayUI: ShopliveOverlayUIMode = ShopliveOverlayUIMode.BUILT_IN
        set(value) { calls += "setOverlayUI"; field = value }
    override val isInPictureInPicture: Boolean get() = false
    override val state: ShoplivePlayerState get() = when {
        running -> ShoplivePlayerState.PLAYING
        started -> ShoplivePlayerState.CLOSED
        else -> ShoplivePlayerState.IDLE
    }
    override val currentCampaign: ShopliveCampaignInfo? get() = campaign

    var startFailure: RuntimeException? = null
    override fun start(campaignKey: String, options: ShoplivePlayOptions) {
        startFailure?.let { throw it }
        calls += "start2"; lastOptions = options; running = true; started = true
    }
    override fun start(campaignKey: String, options: ShoplivePlayOptions, configuration: ShoplivePlayerConfiguration) {
        calls += "start3"; lastOptions = options; startedWithConfiguration = configuration; this.configuration = configuration; calls.remove("setConfiguration"); running = true; started = true
    }
    var onClose: (() -> Unit)? = null
    override fun close() { onClose?.invoke(); calls += "close"; running = false }
    override fun play(campaignKey: String, options: ShoplivePlayOptions) { calls += "play" }
    override fun stop() { calls += "stop" }
    override fun reload() { calls += "reload" }
    override fun enterPictureInPicture() { calls += "enterPiP" }
    override fun exitPictureInPicture() { calls += "exitPiP" }
    override fun send(command: String, payload: Map<String, Any?>?) { calls += "send:$command:$payload" }
}

class PlayerMethodHandlerTest {

    private val scheduler = FakeScheduler()
    private val registry = PendingRequestRegistry(scheduler)
    private val created = mutableListOf<Pair<String, FakePort>>()
    private val liveEvents = mutableListOf<cloud.shoplive.player.ShoplivePlayerEvent>()
    private val liveDelegate = object : ShoplivePlayerDelegate {
        override fun onEvent(sender: cloud.shoplive.player.ShoplivePlayerControlling, event: cloud.shoplive.player.ShoplivePlayerEvent) { liveEvents += event }
        override fun onRequest(sender: cloud.shoplive.player.ShoplivePlayerControlling, request: cloud.shoplive.player.ShoplivePlayerRequest) {}
    }
    private var nextRunning = false
    private var nextFailure: RuntimeException? = null
    private val handler = PlayerMethodHandler<String>(
        registry = registry,
        portFactory = { host -> FakePort(nextRunning).also { it.startFailure = nextFailure; created += host to it } },
        liveDelegate = { liveDelegate },
    )

    private fun call(method: String, args: Map<String, Any?>? = null): Any? = handler.handle(method, Args.of(args))
    private fun port(): FakePort = created.last().second
    private fun stateCode(block: () -> Unit): String = assertThrows(BridgeStateException::class.java) { block() }.code

    // ---- 인스턴스 생성은 start에서만 (F-02, X-08, pair #19) ----

    @Test // case: F-02
    fun noHost_start_isNoHostScreen_andCreatesNothing() {
        assertEquals(BridgeErrorCode.NO_HOST_SCREEN, stateCode { call("start", mapOf("campaignKey" to "k")) })
        assertEquals(0, created.size)
    }

    @Test // case: F-02, NR-01
    fun noInstance_queriesReturnDefaults_withoutCreating() {
        assertEquals("idle", call("getState"))
        assertEquals(false, call("isRunning"))
        assertEquals(false, call("isMuted"))
        assertEquals(false, call("isInPictureInPicture"))
        assertNull(call("getCurrentCampaign"))
        assertEquals("fill", call("getResizeMode"))
        assertEquals("builtIn", call("getOverlayUI"))
        assertEquals(PlayerMapper.configurationToWire(ShoplivePlayerConfiguration()), call("getConfiguration"))
        assertNull(call("close"))
        assertEquals(0, created.size)
    }

    @Test // case: CFG-01, CFG-02, CFG-03
    fun noInstance_settersStoreOnly_andGettersReturnStored() {
        call("setConfiguration", mapOf("configuration" to mapOf("sound" to mapOf("muteOnStart" to true))))
        call("setResizeMode", mapOf("mode" to "fit"))
        call("setOverlayUI", mapOf("mode" to "hidden"))
        assertEquals(0, created.size)
        assertEquals("fit", call("getResizeMode"))
        assertEquals("hidden", call("getOverlayUI"))
        assertEquals(true, ((call("getConfiguration") as Map<*, *>)["sound"] as Map<*, *>)["muteOnStart"])
    }

    @Test // case: F-02
    fun noHost_hostFreeMethods_work() {
        call("setRequestTimeout", mapOf("timeoutMs" to 1000))
        assertEquals(false, call("respondFallback", mapOf("requestId" to "x")))
        assertEquals(false, call("respondCoupon", mapOf("requestId" to "x", "success" to true, "status" to "keep")))
        assertEquals(0, created.size)
    }

    @Test // case: N-02
    fun start_createsOnceWithLiveDelegate() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        call("isMuted")
        call("play", mapOf("campaignKey" to "k2"))
        assertEquals(1, created.size)
        assertSame(liveDelegate, port().delegate)
    }

    @Test // case: R-04, T-04
    fun runningInstance_survivesHostDetach_andIsControllable() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        handler.detachHost()
        assertEquals("playing", call("getState"))
        call("stop")
        assertEquals("stop", port().calls.last())
    }

    // ---- start ----

    @Test // case: N-02, CFG-01
    fun start_withoutConfiguration_usesTwoArgStart() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        assertEquals(listOf("start2"), port().calls)
    }

    @Test // case: CFG-01
    fun start_withPartialConfiguration_mergesAndUsesThreeArgStart() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k", "configuration" to mapOf("sound" to mapOf("muteOnStart" to true))))
        assertEquals(listOf("start3"), port().calls)
        assertEquals(true, port().startedWithConfiguration!!.sound.muteOnStart)
    }

    @Test // case: F-04
    fun start_blankKey_isInvalid() {
        handler.attachHost("A1")
        assertThrows(BridgeArgumentException::class.java) { call("start", mapOf("campaignKey" to " ")) }
        assertEquals(0, created.size)
    }

    @Test // case: B-09
    fun start_pipWithoutInAppPip_isInvalid_andCreatesNothing() {
        handler.attachHost("A1")
        val e = assertThrows(BridgeArgumentException::class.java) {
            call("start", mapOf("campaignKey" to "k", "playOptions" to mapOf("presentationStyle" to "pip"), "configuration" to mapOf("pip" to mapOf("isInAppPipEnabled" to false))))
        }
        assertEquals("playOptions.presentationStyle", e.key)
        assertEquals(0, created.size)
    }

    @Test // case: B-09, CFG-01
    fun start_pipAfterSetConfiguration_isAllowed() {
        handler.attachHost("A1")
        call("setConfiguration", mapOf("configuration" to mapOf("pip" to mapOf("isInAppPipEnabled" to true))))
        call("start", mapOf("campaignKey" to "k", "playOptions" to mapOf("presentationStyle" to "pip")))
        assertEquals(ShoplivePlayerPresentationStyle.PIP, port().lastOptions!!.presentationStyle)
        assertEquals(true, port().configuration.pip.isInAppPipEnabled)
    }

    // ---- NOT_RUNNING (NR-01) ----

    @Test // case: NR-01
    fun sessionCommands_withoutInstance_orNotRunning_areNotRunning() {
        val cases = listOf(
            "play" to mapOf("campaignKey" to "k"), "stop" to null, "reload" to null, "send" to mapOf("command" to "c"),
            "setMuted" to mapOf("muted" to true), "enterPictureInPicture" to null, "exitPictureInPicture" to null,
        )
        for ((m, a) in cases) assertEquals(m, BridgeErrorCode.NOT_RUNNING, stateCode { call(m, a) })
        assertEquals(0, created.size)
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        call("close")
        for ((m, a) in cases) assertEquals(m, BridgeErrorCode.NOT_RUNNING, stateCode { call(m, a) })
        assertEquals(listOf("start2", "close"), port().calls)
    }

    @Test // case: NR-01
    fun close_isIdempotent() {
        assertNull(call("close"))
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        call("close")
        assertNull(call("close"))
        assertEquals(listOf("start2", "close", "close"), port().calls)
    }

    @Test // case: N-02
    fun sessionCommands_whenRunning_delegate() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        call("play", mapOf("campaignKey" to "k2"))
        call("send", mapOf("command" to "c", "payload" to mapOf("a" to 1)))
        call("setMuted", mapOf("muted" to true))
        call("enterPictureInPicture")
        call("exitPictureInPicture")
        call("reload")
        call("stop")
        assertEquals(listOf("start2", "play", "send:c:{a=1}", "setMuted", "enterPiP", "exitPiP", "reload", "stop"), port().calls)
        assertEquals(true, call("isMuted"))
    }

    @Test // case: N-02
    fun send_withoutPayload_sendsEmptyMap() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        call("send", mapOf("command" to "c"))
        assertEquals("send:c:{}", port().calls.last())
    }

    // ---- getter·setter ----

    @Test // case: N-02, CFG-02
    fun getters_withInstance_returnWire() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        port().campaign = ShopliveCampaignInfo("k", "t", ShopliveCampaignStatus.LIVE)
        assertEquals("playing", call("getState"))
        assertEquals(true, call("isRunning"))
        assertEquals(mapOf("campaignKey" to "k", "title" to "t", "status" to "live"), call("getCurrentCampaign"))
        assertEquals(PlayerMapper.configurationToWire(port().configuration), call("getConfiguration"))
    }

    @Test // case: B-01
    fun setResizeMode_unknownWire_isInvalid() {
        assertThrows(BridgeArgumentException::class.java) { call("setResizeMode", mapOf("mode" to "FILL")) }
    }

    // ---- CFG-03: 재생성·해제 후 설정 유지 (R2-N1) ----

    private fun configureEverything() {
        call("setConfiguration", mapOf("configuration" to mapOf("pip" to mapOf("isInAppPipEnabled" to true), "sound" to mapOf("muteOnStart" to true))))
        call("setResizeMode", mapOf("mode" to "fit"))
        call("setOverlayUI", mapOf("mode" to "hidden"))
    }

    private fun assertSettingsCarried(p: FakePort) {
        assertEquals(true, p.configuration.pip.isInAppPipEnabled)
        assertEquals(true, p.configuration.sound.muteOnStart)
        assertEquals(ShopliveResizeMode.FIT, p.resizeMode)
        assertEquals(ShopliveOverlayUIMode.HIDDEN, p.overlayUI)
    }

    @Test // case: CFG-03, T-04
    fun cfg03_hostChange_recreatesAndCarriesSettings_thenPipStartAllowed() {
        handler.attachHost("A1")
        configureEverything()
        call("start", mapOf("campaignKey" to "k"))
        val old = port()
        call("close")
        handler.detachHost()
        handler.attachHost("A2") // 회전으로 Activity 재생성
        call("start", mapOf("campaignKey" to "k", "playOptions" to mapOf("presentationStyle" to "pip")))
        assertEquals(2, created.size)
        assertEquals("A2", created.last().first)
        assertSettingsCarried(port())
        assertSame(DetachedDelegate, old.delegate)
    }

    @Test // case: T-04, SMV-1749 — 실행 중 Activity가 바뀌어도 새 start는 현재 Activity의 새 인스턴스로
    fun runningInstance_hostChange_startRetiresAndRecreatesOnNewHost() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        val old = port()
        handler.attachHost("A2")
        call("start", mapOf("campaignKey" to "k"))
        assertEquals(2, created.size)
        assertEquals("A2", created.last().first)
        assertEquals(listOf("start2", "close"), old.calls)
        assertSame(DetachedDelegate, old.delegate)
    }

    @Test // case: SMV-1749 T-01 — preview(PIP)로 실행 중 live로 start: 새 인스턴스에 live 설정이 실리고 이전 인스턴스는 해제 후 close
    fun runningPreview_thenLiveStart_newPortGetsLiveConfiguration() {
        handler.attachHost("A1")
        call(
            "start",
            mapOf(
                "campaignKey" to "k1",
                "playOptions" to mapOf("presentationStyle" to "pip"),
                "configuration" to mapOf("type" to "preview", "pip" to mapOf("isInAppPipEnabled" to true)),
            ),
        )
        val preview = port()
        assertEquals(ShoplivePlayerType.PREVIEW, preview.startedWithConfiguration!!.type)
        var delegateAtClose: ShoplivePlayerDelegate? = null
        preview.onClose = { delegateAtClose = preview.delegate }
        liveEvents.clear()
        call("start", mapOf("campaignKey" to "k2", "configuration" to mapOf("type" to "live")))
        // R5-02: 교체 성공 경로에서는 (가짜) closed를 보내지 않는다 — 이전 세션 이벤트는 DetachedDelegate로 차단
        assertEquals(emptyList<Any>(), liveEvents.filter { it == cloud.shoplive.player.ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.CLOSED) })
        val live = port()
        assertEquals(2, created.size)
        // create가 보관 설정을 먼저 넣고(IDLE이라 SDK가 받음) effective로 3인자 start 1회
        assertEquals(listOf("start3"), live.calls.filter { it.startsWith("start") || it == "close" })
        assertEquals(ShoplivePlayerType.LIVE, live.startedWithConfiguration!!.type)
        assertEquals(true, live.startedWithConfiguration!!.pip.isInAppPipEnabled) // 보관값 + partial 병합
        assertSame(liveDelegate, live.delegate)
        assertEquals(listOf("start3", "close"), preview.calls)
        assertSame(DetachedDelegate, delegateAtClose) // close 전에 DetachedDelegate(이전 세션 이벤트 차단)
        assertSame(DetachedDelegate, preview.delegate)
        assertEquals("live", (call("getConfiguration") as Map<*, *>)["type"])
    }

    @Test // case: SMV-1749 R4-03(a) — 실행 중 세션이 있을 때 검증 단계(B-09·빈 키·호스트 없음)에서 start가 실패하면 이전 세션은 그대로
    fun runningSession_failedStartValidation_keepsPreviousSession() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        val old = port()
        assertThrows(BridgeArgumentException::class.java) {
            call("start", mapOf("campaignKey" to "k2", "playOptions" to mapOf("presentationStyle" to "pip"), "configuration" to mapOf("pip" to mapOf("isInAppPipEnabled" to false))))
        }
        assertThrows(BridgeArgumentException::class.java) { call("start", mapOf("campaignKey" to " ")) }
        handler.detachHost() // 실행 중이라 인스턴스는 유지, 호스트만 없음
        assertEquals(BridgeErrorCode.NO_HOST_SCREEN, stateCode { call("start", mapOf("campaignKey" to "k3")) })
        assertEquals(1, created.size)
        assertEquals(listOf("start2"), old.calls)
        assertSame(liveDelegate, old.delegate)
        assertEquals("playing", call("getState"))
    }

    @Test // case: SMV-1749 R4-03(b) — 교체 경로에서도 보관 resizeMode·overlayUI·설정이 새 인스턴스로 이관
    fun retirePath_carriesSavedSettingsToNewPort() {
        handler.attachHost("A1")
        configureEverything()
        call("start", mapOf("campaignKey" to "k"))
        call("start", mapOf("campaignKey" to "k2"))
        assertEquals(2, created.size)
        assertSettingsCarried(port())
    }

    @Test // case: SMV-1749 R4-03(c) — 교체되는 세션의 대기 쿠폰·커스텀 요청은 폴백으로 정확히 1회, 이후 Dart respond는 false
    fun retirePath_flushesPendingRequestsOfPreviousSessionOnce() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        val coupons = mutableListOf<ShopliveCouponResult>()
        val actions = mutableListOf<ShopliveCustomActionResult>()
        val couponId = registry.register(PendingRequest.Coupon("c1") { coupons += it })
        val actionId = registry.register(PendingRequest.CustomAction("a1") { actions += it })
        call("start", mapOf("campaignKey" to "k2"))
        assertEquals(1, coupons.size)
        assertEquals(ShopliveResultStatus.KEEP, coupons.single().status)
        assertEquals(1, actions.size)
        assertEquals(false, call("respondCoupon", mapOf("requestId" to couponId, "success" to true, "status" to "hide")))
        assertEquals(false, call("respondCustomAction", mapOf("requestId" to actionId, "success" to true, "status" to "hide")))
        assertEquals(0, scheduler.pendingTimers()) // 타임아웃 타이머도 취소됨
        scheduler.advance(200_000)
        assertEquals(1, coupons.size)
        assertEquals(1, actions.size)
    }

    @Test // case: SMV-1749 R4-02 — 이전 세션을 닫은 뒤 새 세션 start가 예외로 실패하면 Dart에 closed 1회(상태가 낡지 않게)
    fun replacementStartFailure_emitsClosedOnce_andPropagates() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        liveEvents.clear()
        nextFailure = IllegalStateException("sdk")
        assertThrows(IllegalStateException::class.java) { call("start", mapOf("campaignKey" to "k2")) }
        assertEquals(listOf(cloud.shoplive.player.ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.CLOSED)), liveEvents)
        // 교체할 세션이 없던 첫 start 실패는 closed를 보내지 않는다
        val fresh = PlayerMethodHandler<String>(registry, { FakePort().also { it.startFailure = IllegalStateException("sdk") } }, { liveDelegate })
        liveEvents.clear()
        fresh.attachHost("A1")
        assertThrows(IllegalStateException::class.java) { fresh.handle("start", Args.of(mapOf("campaignKey" to "k"))) }
        assertEquals(emptyList<Any>(), liveEvents)
    }

    @Test // case: SMV-1749 R4-04 — getConfiguration은 다음 start에 쓰일 설정(실행 중 SET은 SDK가 무시해도 보관값 반환)
    fun getConfiguration_whileRunning_returnsSettingsForNextStart() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k", "configuration" to mapOf("type" to "preview")))
        call("setConfiguration", mapOf("configuration" to mapOf("type" to "live")))
        assertEquals("live", (call("getConfiguration") as Map<*, *>)["type"])
    }

    @Test // case: SMV-1749 — close 후 같은 호스트에서 다시 start해도 CLOSED 인스턴스를 재사용하지 않는다(SDK가 설정을 거부)
    fun closedInstance_sameHost_startCreatesNewPort() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k", "configuration" to mapOf("type" to "preview")))
        val first = port()
        call("close")
        call("start", mapOf("campaignKey" to "k", "configuration" to mapOf("type" to "live")))
        assertEquals(2, created.size)
        assertEquals(listOf("start3", "close"), first.calls) // CLOSED라 close를 다시 부르지 않는다
        assertEquals(ShoplivePlayerType.LIVE, port().startedWithConfiguration!!.type)
    }

    @Test // case: CFG-03, R-04
    fun cfg03_settingsBeforeAnyInstance_areCarriedOnFirstStart() {
        configureEverything()
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        assertEquals(1, created.size)
        assertSettingsCarried(port())
    }

    @Test // case: R-03
    fun engineDetach_setsDetachedDelegate_keepsSession_clearsSettings() {
        handler.attachHost("A1")
        configureEverything()
        call("start", mapOf("campaignKey" to "k"))
        val running = port()
        handler.onEngineDetached()
        assertSame(DetachedDelegate, running.delegate)
        assertEquals(true, running.running)
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        assertEquals(ShopliveResizeMode.FILL, port().resizeMode)
    }

    // ---- respond (C-4) ----

    @Test // case: N-06, T-06
    fun respondCoupon_deliversOnce_secondIsFalse() {
        val results = mutableListOf<ShopliveCouponResult>()
        val id = registry.register(PendingRequest.Coupon("c1") { results += it })
        val args = mapOf("requestId" to id, "success" to true, "status" to "hide", "message" to "ok", "alertType" to "alert")
        assertEquals(true, call("respondCoupon", args))
        assertEquals(false, call("respondCoupon", args))
        assertEquals(1, results.size)
        assertEquals(ShopliveResultStatus.HIDE, results.single().status)
        assertEquals(0, scheduler.pendingTimers())
    }

    @Test // case: N-06, T-03
    fun respond_invalidArgs_keepsEntry_forTimeoutFallback() {
        val results = mutableListOf<ShopliveCouponResult>()
        val id = registry.register(PendingRequest.Coupon("c1") { results += it })
        assertThrows(BridgeArgumentException::class.java) { call("respondCoupon", mapOf("requestId" to id, "success" to true)) }
        assertEquals(1, registry.size())
        scheduler.advance(PendingRequestRegistry.DEFAULT_TIMEOUT_MS)
        assertEquals(false, results.single().success)
    }

    @Test // case: N-06
    fun respond_kindMismatch_isInvalid_andKeepsEntry() {
        val id = registry.register(PendingRequest.CustomAction("a1") { })
        assertThrows(BridgeArgumentException::class.java) {
            call("respondCoupon", mapOf("requestId" to id, "success" to true, "status" to "keep"))
        }
        assertEquals(1, registry.size())
    }

    @Test // case: N-06
    fun respondCustomAction_and_fallback() {
        val results = mutableListOf<ShopliveCustomActionResult>()
        val id1 = registry.register(PendingRequest.CustomAction("a1") { results += it })
        val id2 = registry.register(PendingRequest.CustomAction("a2") { results += it })
        assertEquals(true, call("respondCustomAction", mapOf("requestId" to id1, "success" to true, "status" to "show")))
        assertEquals(true, call("respondFallback", mapOf("requestId" to id2)))
        assertEquals(false, call("respondFallback", mapOf("requestId" to id2)))
        assertEquals(listOf(true, false), results.map { it.success })
    }

    @Test // case: B-08
    fun setRequestTimeout_validates() {
        assertThrows(BridgeArgumentException::class.java) { call("setRequestTimeout", mapOf("timeoutMs" to 0)) }
        assertThrows(BridgeArgumentException::class.java) { call("setRequestTimeout", mapOf("timeoutMs" to Long.MAX_VALUE)) }
        assertThrows(BridgeArgumentException::class.java) { call("setRequestTimeout", emptyMap()) }
    }

    @Test // case: F-05
    fun unknownMethod_isNotImplemented() {
        assertThrows(MethodNotImplemented::class.java) { call("showPreview") }
    }

    @Test // case: U-07
    fun methodNames_matchContract() {
        assertEquals(
            listOf(
                "start", "play", "stop", "close", "reload", "send", "setMuted", "isMuted", "setResizeMode", "getResizeMode",
                "setOverlayUI", "getOverlayUI", "enterPictureInPicture", "exitPictureInPicture", "isInPictureInPicture", "getState",
                "getCurrentCampaign", "isRunning", "setConfiguration", "getConfiguration", "setRequestTimeout", "respondCoupon",
                "respondCustomAction", "respondFallback",
            ),
            PlayerContract.METHODS,
        )
        assertEquals("shoplive_player/events", PlayerContract.EVENTS_CHANNEL)
        assertEquals("shoplive_player/requests", PlayerContract.REQUESTS_CHANNEL)
    }
}
