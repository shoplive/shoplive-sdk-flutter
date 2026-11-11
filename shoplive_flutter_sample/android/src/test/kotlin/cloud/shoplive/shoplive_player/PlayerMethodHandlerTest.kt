package cloud.shoplive.shoplive_player

import cloud.shoplive.player.ShopliveCampaignInfo
import cloud.shoplive.player.ShopliveCampaignStatus
import cloud.shoplive.player.ShopliveCloseReason
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
    /** SDK 3.0.3·3.0.4 모델: 생성 시에만 Idle, start 이후 실행 중이 아니면 Closed(되돌아가지 않음). close() = APP_REQUEST(ShoplivePlayer.kt:1198). */
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
    override var resizeMode: ShopliveResizeMode = ShopliveResizeMode.DEFAULT // 3.0.6 ShoplivePlayer 생성자 초기값(ShoplivePlayer.kt:1731)
        set(value) { calls += "setResizeMode"; field = value }
    override var overlayUI: ShopliveOverlayUIMode = ShopliveOverlayUIMode.BUILT_IN
        set(value) { calls += "setOverlayUI"; field = value }
    /** startPreview 대역: SDK가 돌려준 인스턴스가 in-App PIP로 떠 있는가. */
    var inPip = false
    override val isInPictureInPicture: Boolean get() = inPip
    override val instance: Any get() = this
    override val state: ShoplivePlayerState get() = when {
        running -> ShoplivePlayerState.Playing
        started -> ShoplivePlayerState.Closed(ShopliveCloseReason.APP_REQUEST)
        else -> ShoplivePlayerState.Idle
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
    /** startPreview 대역: SDK ShoplivePlayer.startPreview가 돌려줄 인스턴스(호스트·키를 기록). */
    private val previewCalls = mutableListOf<Pair<String, String>>()
    private val previewReturned = mutableListOf<FakePort>()
    private var nextPreview: () -> FakePort = { FakePort(running = true).also { it.inPip = true } }
    private val handler = PlayerMethodHandler<String>(
        registry = registry,
        portFactory = { host -> FakePort(nextRunning).also { it.startFailure = nextFailure; created += host to it } },
        previewLauncher = { host, key -> previewCalls += host to key; nextPreview().also { previewReturned += it } },
        liveDelegate = { liveDelegate },
        drawableId = { null },
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
        assertEquals("default", call("getResizeMode")) // case: R-1 (R6-A2) — 3.0.6 생성자 초기값 DEFAULT
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
        assertEquals(emptyList<Any>(), liveEvents.filter { it is cloud.shoplive.player.ShoplivePlayerEvent.StateChanged && it.state is ShoplivePlayerState.Closed })
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
        // case: A4-3 (R-A7) — 브릿지 합성 closed의 사유는 appRequest(SDK close()와 같은 값)
        assertEquals(listOf(cloud.shoplive.player.ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.Closed(ShopliveCloseReason.APP_REQUEST))), liveEvents)
        // 교체할 세션이 없던 첫 start 실패는 closed를 보내지 않는다
        val fresh = PlayerMethodHandler<String>(
            registry, { FakePort().also { it.startFailure = IllegalStateException("sdk") } }, { _, _ -> FakePort() }, { liveDelegate }, { null },
        )
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

    // ---- startPreview(SMV-1899 D11 — SDK ShoplivePlayer.startPreview가 돌려준 인스턴스를 동일성으로 판단해 채택) ----

    @Test // case: S-8 (R6-A6) — 호스트가 없으면 SDK를 부르지 않고 NO_HOST_SCREEN
    fun startPreview_noHost_isNoHostScreen_withoutSdkCall() {
        assertEquals(BridgeErrorCode.NO_HOST_SCREEN, stateCode { call("startPreview", mapOf("campaignKey" to "k")) })
        assertEquals(emptyList<Any>(), previewCalls)
    }

    @Test // case: S-5 (R6-A6, D11-d) — 빈·공백 키는 SDK를 부르기 전에 INVALID_ARGUMENT(SDK의 빈 키 오류는 반환 전에 나가 받을 수 없다)
    fun startPreview_blankKey_isInvalid_withoutSdkCall() {
        handler.attachHost("A1")
        for (key in listOf("", "  ")) {
            assertThrows(BridgeArgumentException::class.java) { call("startPreview", mapOf("campaignKey" to key)) }
        }
        assertEquals(emptyList<Any>(), previewCalls)
    }

    @Test // case: S-1·S-9 (R6-A6) — 포트가 없을 때 SDK가 띄운 새 인스턴스를 채택: live delegate, 보관 설정 미적용, 현재 상태 1회 보충
    fun startPreview_newInstance_isAdopted_withStateOnce() {
        call("setResizeMode", mapOf("mode" to "fit"))
        call("setConfiguration", mapOf("configuration" to mapOf("sound" to mapOf("muteOnStart" to false))))
        handler.attachHost("A1")
        assertNull(call("startPreview", mapOf("campaignKey" to "p")))
        assertEquals(listOf("A1" to "p"), previewCalls)
        val preview = lastPreview()
        assertSame(liveDelegate, preview.delegate)
        assertEquals(ShopliveResizeMode.DEFAULT, preview.resizeMode) // SDK 프리셋 그대로(보관값은 다음 start용)
        assertEquals(emptyList<String>(), preview.calls)
        assertEquals(listOf<Any>(cloud.shoplive.player.ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.Playing)), liveEvents) // SDK가 반환 전에 낸 상태를 1회 보충(St-a)
        assertEquals("playing", call("getState"))
        assertEquals(true, call("isInPictureInPicture"))
    }

    @Test // case: S-2·S-3·S-4 (R6-A6) — SDK가 지금 port와 같은 인스턴스를 돌려주면(재사용·같은 인스턴스 재시작·시청 중 무시) 아무것도 바꾸지 않는다
    fun startPreview_sameInstance_changesNothing() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        val running = port()
        nextPreview = { running }
        assertNull(call("startPreview", mapOf("campaignKey" to "p")))
        assertSame(liveDelegate, running.delegate)
        call("stop") // port가 그대로 running인지 공개 경로로 확인
        assertEquals(listOf("start2", "stop"), running.calls)
        assertEquals(emptyList<Any>(), liveEvents)
    }

    @Test // case: S-10 (R6-A6) — 다른 인스턴스로 바뀌면 이전 port는 retire(DetachedDelegate·대기 요청 폴백·실행 중이면 close) 후 채택
    fun startPreview_otherInstance_retiresPreviousPort() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        val old = port()
        val coupons = mutableListOf<cloud.shoplive.player.ShopliveCouponResult>()
        registry.register(PendingRequest.Coupon("c1") { coupons += it })
        call("startPreview", mapOf("campaignKey" to "p"))
        assertSame(DetachedDelegate, old.delegate)
        assertEquals(listOf("start2", "close"), old.calls)
        assertEquals(1, coupons.size) // 이전 세션 대기 요청은 폴백 1회
        assertSame(liveDelegate, lastPreview().delegate)
    }

    @Test // case: S-6 (R6-A6) — SDK가 시작하지 않은 새 인스턴스를 돌려주면(미초기화·진입 거부) SDK_ERROR, 지금 세션은 그대로
    fun startPreview_notStarted_isSdkError_currentSessionKept() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        val running = port()
        nextPreview = { FakePort() }
        assertEquals(BridgeErrorCode.SDK_ERROR, stateCode { call("startPreview", mapOf("campaignKey" to "p")) })
        assertSame(liveDelegate, running.delegate)
        assertEquals(true, call("isRunning"))
        assertEquals(emptyList<Any>(), liveEvents)
    }

    @Test // case: S-14 (R6-A6) — 채택한 프리뷰가 있어도 start는 기존 규칙대로 그 인스턴스를 retire하고 새로 만든다
    fun start_afterPreview_retiresPreview() {
        handler.attachHost("A1")
        call("startPreview", mapOf("campaignKey" to "p"))
        val preview = lastPreview()
        call("start", mapOf("campaignKey" to "k"))
        assertSame(DetachedDelegate, preview.delegate)
        assertEquals(listOf("close"), preview.calls)
        assertEquals(1, created.size)
        assertSame(liveDelegate, port().delegate)
    }

    private fun lastPreview(): FakePort = previewReturned.last()

    // ---- D12(SMV-1899): 재생 중 setConfiguration — 인스턴스는 인스턴스 설정 위에, 보관값은 보관값 위에 ----

    @Test // case: C-1·C-2·C-3 (R6-A7) — 실행 중 인스턴스(프리셋이 보관값과 다름)에는 type 없이 병합, 보관값은 SDK 기본 위에
    fun setConfiguration_runningInstance_mergesOntoInstanceWithoutType_savedOntoSaved() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        port().configuration = ShoplivePlayerConfiguration.PREVIEW // 보관값과 다른 인스턴스 설정(프리뷰 채택·SDK 확장 변경 등)
        call("setConfiguration", mapOf("configuration" to mapOf("type" to "live", "navigation" to mapOf("isCustomShareEnabled" to true))))
        val instance = port().configuration
        assertEquals(ShoplivePlayerType.PREVIEW, instance.type)
        assertEquals(true, instance.sound.muteOnStart)
        assertEquals(ShopliveOverlayUIMode.HIDDEN, instance.overlay.ui)
        assertEquals(true, instance.navigation.isCustomShareEnabled)
        val saved = call("getConfiguration") as Map<*, *>
        assertEquals("live", saved["type"])
        assertEquals(false, (saved["sound"] as Map<*, *>)["muteOnStart"])
        assertEquals(true, (saved["navigation"] as Map<*, *>)["isCustomShareEnabled"])
    }

    @Test // case: C-3 (R6-A7) — 보관값이 없으면 getConfiguration은 SDK 기본(인스턴스 설정으로 떨어지지 않는다)
    fun getConfiguration_withoutSaved_isSdkDefault_notInstance() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        port().configuration = ShoplivePlayerConfiguration.PREVIEW
        assertEquals(PlayerMapper.configurationToWire(ShoplivePlayerConfiguration()), call("getConfiguration"))
    }

    @Test // case: C-5 (R6-A7, X9·Y2) — 비실행 Idle 인스턴스에는 type까지 병합 → 재사용되는 다음 start가 그 type으로 시작
    fun setConfiguration_idleInstance_includesType_nextStartUsesIt() {
        handler.attachHost("A1")
        nextFailure = IllegalStateException("start failed")
        assertThrows(IllegalStateException::class.java) { call("start", mapOf("campaignKey" to "k")) }
        val idle = port()
        idle.startFailure = null
        call("setConfiguration", mapOf("configuration" to mapOf("type" to "preview")))
        assertEquals(ShoplivePlayerType.PREVIEW, idle.configuration.type)
        call("start", mapOf("campaignKey" to "k"))
        assertEquals(1, created.size) // Idle·같은 호스트라 재사용(portForStart)
        assertEquals(ShoplivePlayerType.PREVIEW, idle.configuration.type)
        assertEquals("preview", (call("getConfiguration") as Map<*, *>)["type"])
    }

    @Test // case: C-2 (R6-A7) — 인자 오류면 인스턴스·보관값 어느 것도 바뀌지 않는다(두 병합 계산 뒤 대입)
    fun setConfiguration_invalid_changesNeitherInstanceNorSaved() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k"))
        port().configuration = ShoplivePlayerConfiguration.PREVIEW
        port().calls.clear()
        assertThrows(BridgeArgumentException::class.java) {
            call("setConfiguration", mapOf("configuration" to mapOf("navigation" to mapOf("isCustomShareEnabled" to true), "sound" to mapOf("muteOnStart" to "yes"))))
        }
        assertEquals(ShoplivePlayerConfiguration.PREVIEW, port().configuration)
        assertEquals(emptyList<String>(), port().calls)
        assertEquals(PlayerMapper.configurationToWire(ShoplivePlayerConfiguration()), call("getConfiguration"))
    }

    @Test // case: C-4 (R6-A7, 교차검증 K1) — 실행 중 인스턴스까지 두 번 병합해도 이름 해석(=해석 실패 경고 지점)은 이름당 1회
    fun setConfiguration_resolvesEachImageNameOncePerCall() {
        val asked = mutableListOf<String>()
        val h = PlayerMethodHandler<String>(
            registry, portFactory = { FakePort() }, previewLauncher = { _, _ -> FakePort() }, liveDelegate = { liveDelegate }, drawableId = { asked += it; null },
        )
        h.attachHost("A1")
        h.handle("start", Args.of(mapOf("campaignKey" to "k")))
        h.handle(
            "setConfiguration",
            Args.of(mapOf("configuration" to mapOf("pip" to mapOf("closeButton" to mapOf("nativeImageName" to "missing"), "restoreButton" to mapOf("nativeImageName" to "missing"))))),
        )
        assertEquals(listOf("missing"), asked)
    }

    @Test // case: SMV-1749, A4-6 (R-A7) — close 후 같은 호스트에서 다시 start해도 Closed 인스턴스를 재사용하지 않는다(재사용 조건은 Idle뿐)
    fun closedInstance_sameHost_startCreatesNewPort() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k", "configuration" to mapOf("type" to "preview")))
        val first = port()
        call("close")
        assertEquals("closed", call("getState")) // A4-4: getState는 사유 없이 'closed'
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
        assertEquals(ShopliveResizeMode.DEFAULT, port().resizeMode)
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
                "respondCustomAction", "respondFallback", "getCampaigns", "cancelGetCampaigns", "startPreview",
            ),
            PlayerContract.METHODS,
        )
        assertEquals("shoplive_player/events", PlayerContract.EVENTS_CHANNEL)
        assertEquals("shoplive_player/requests", PlayerContract.REQUESTS_CHANNEL)
    }

    // ---- D6: 교체된 세션의 delegate는 retired(SMV-1899 A4-5, R-A8) ----

    private val gen = AttachGeneration().also { it.next() }
    private val bridgeEvents = EventEmitter("events", scheduler)
    private val bridgeRequests = EventEmitter("requests", scheduler)
    private val eventSink = RecordingSink()
    private val bridgeCoupons = mutableListOf<ShopliveCouponResult>()
    private val bridged = PlayerMethodHandler<String>(
        registry = registry,
        portFactory = { host -> FakePort(nextRunning).also { it.startFailure = nextFailure; created += host to it } },
        previewLauncher = { _, _ -> FakePort() },
        liveDelegate = { PlayerDelegateBridge(gen, gen.current, scheduler, bridgeEvents, bridgeRequests, registry) },
        drawableId = { null },
    )

    @Test // case: A4-5 (R-A8) — 메인 hop 대기 중 retire되면 이전 세션 이벤트는 버리고 요청은 폴백 1회
    fun retiredBridge_dropsPostedEvents_andFallsBackRequests() {
        bridgeEvents.onListen(null, eventSink)
        bridgeRequests.onListen(null, RecordingSink())
        bridged.attachHost("A1")
        bridged.handle("start", Args.of(mapOf("campaignKey" to "k1")))
        val oldBridge = created.last().second.delegate!!
        scheduler.onMain = false // SDK가 메인 밖에서 통지 → 메인 hop 예약
        oldBridge.onEvent(FakePort(), cloud.shoplive.player.ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.Closed(ShopliveCloseReason.APP_REQUEST)))
        oldBridge.onRequest(FakePort(), cloud.shoplive.player.ShoplivePlayerRequest.Coupon("c1") { bridgeCoupons += it })
        scheduler.onMain = true
        bridged.handle("start", Args.of(mapOf("campaignKey" to "k2"))) // retire(이전 세션)
        scheduler.runPosted()
        assertEquals(emptyList<Any?>(), eventSink.events)
        assertEquals(1, bridgeCoupons.size)
        assertEquals(ShopliveResultStatus.KEEP, bridgeCoupons.single().status)
        assertEquals(0, registry.size())
    }

    @Test // case: A4-5 (R-A8, 교차검증 R3) — SDK가 스스로 닫아(endSession) delegate를 비운 인스턴스도 retire에서 표시된다
    fun sdkClosedInstance_delegateCleared_isStillRetired() {
        bridgeEvents.onListen(null, eventSink)
        bridged.attachHost("A1")
        bridged.handle("start", Args.of(mapOf("campaignKey" to "k1")))
        val old = created.last().second
        val oldBridge = old.delegate!!
        old.running = false // endSession 모사: 토큰 반납 + delegate = null(3.0.4 ShoplivePlayer.kt endSession)
        old.delegate = null
        scheduler.onMain = false // 미뤄진 Closed(accessKeyChanged) 통지가 메인 hop 대기
        oldBridge.onEvent(FakePort(), cloud.shoplive.player.ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.Closed(ShopliveCloseReason.ACCESS_KEY_CHANGED)))
        scheduler.onMain = true
        bridged.handle("start", Args.of(mapOf("campaignKey" to "k2")))
        scheduler.runPosted()
        assertEquals(emptyList<Any?>(), eventSink.events)
    }

    @Test // case: A4-5 (R-A8 비회귀) — detachHost(비실행 인스턴스 해제)는 retired를 세우지 않는다, 합성 closed는 새 bridge로 전달
    fun detachHost_doesNotRetire_andSyntheticClosedIsDelivered() {
        bridgeEvents.onListen(null, eventSink)
        bridged.attachHost("A1")
        nextFailure = IllegalStateException("sdk")
        assertThrows(IllegalStateException::class.java) { bridged.handle("start", Args.of(mapOf("campaignKey" to "k0"))) }
        val idleBridge = created.last().second.delegate!!
        bridged.detachHost() // 비실행 port release(표시 없음)
        idleBridge.onEvent(FakePort(), cloud.shoplive.player.ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.Loading))
        assertEquals(listOf<Any?>(mapOf("type" to "stateChanged", "state" to "loading")), eventSink.events)
        eventSink.events.clear()
        nextFailure = null
        bridged.attachHost("A1")
        nextRunning = false
        bridged.handle("start", Args.of(mapOf("campaignKey" to "k1")))
        nextFailure = IllegalStateException("sdk")
        assertThrows(IllegalStateException::class.java) { bridged.handle("start", Args.of(mapOf("campaignKey" to "k2"))) }
        assertEquals(listOf<Any?>(mapOf("type" to "stateChanged", "state" to "closed", "closeReason" to "appRequest")), eventSink.events)
    }
}
