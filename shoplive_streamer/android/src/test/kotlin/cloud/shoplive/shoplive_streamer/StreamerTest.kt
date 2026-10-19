package cloud.shoplive.shoplive_streamer

import cloud.shoplive.core.publicsurface.ShopliveError
import cloud.shoplive.core.publicsurface.ShopliveErrorCode
import cloud.shoplive.streamer.ShopliveBroadcastState
import cloud.shoplive.streamer.ShopliveStreamerDelegate
import cloud.shoplive.streamer.ShopliveStreamerEvent
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

internal class FakeScheduler(var onMain: Boolean = true) : MainScheduler {
    val posted = mutableListOf<Runnable>()
    override fun isMainThread(): Boolean = onMain
    override fun post(task: Runnable) { posted += task }
    override fun postDelayed(task: Runnable, delayMs: Long): Cancellable = Cancellable { }
    fun runPosted() { val c = posted.toList(); posted.clear(); c.forEach { it.run() } }
}

internal class RecordingSink(private val failWith: RuntimeException? = null) : EventChannel.EventSink {
    val events = mutableListOf<Any?>()
    override fun success(event: Any?) { failWith?.let { throw it }; events += event }
    override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {}
    override fun endOfStream() {}
}

internal class FakeStreamerPort(override var state: ShopliveBroadcastState = ShopliveBroadcastState.IDLE) : StreamerPort {
    override var delegate: ShopliveStreamerDelegate? = null
    val started = mutableListOf<String>()
    val webPageUrls = mutableListOf<String?>()
    override fun start(campaignKey: String, webPageUrl: String?) {
        started += campaignKey
        webPageUrls += webPageUrl
        state = ShopliveBroadcastState.PREVIEW
    }
}

class StreamerTest {

    // ---- Mapper ----

    @Test // case: B-01
    fun broadcastState_table_coversAllSdkConstants_andIsCamelCase() {
        assertEquals(ShopliveBroadcastState.values().toSet(), StreamerMapper.BROADCAST_STATE.values.toSet())
        assertEquals("reconnecting", wireOf(ShopliveBroadcastState.RECONNECTING, StreamerMapper.BROADCAST_STATE))
    }

    @Test // case: N-05
    fun events_toWire() {
        assertEquals(
            mapOf("type" to "stateChanged", "state" to "live", "isRehearsal" to true),
            StreamerMapper.eventToWire(ShopliveStreamerEvent.StateChanged(ShopliveBroadcastState.LIVE, true)),
        )
        assertEquals(
            mapOf("type" to "error", "error" to mapOf("code" to "CONNECTION_ISSUE", "message" to null, "rawCode" to 12, "recoverable" to false)),
            StreamerMapper.eventToWire(ShopliveStreamerEvent.Error(ShopliveError(ShopliveErrorCode.CONNECTION_ISSUE, 12, null, null, false))),
        )
    }

    @Test // case: U-07
    fun contract_names() {
        assertEquals("shoplive_streamer", StreamerContract.METHOD_CHANNEL)
        assertEquals("shoplive_streamer/events", StreamerContract.EVENTS_CHANNEL)
        assertEquals(listOf("start", "getState"), StreamerContract.METHODS)
    }

    // ---- Handler (ST-01) ----

    private val created = mutableListOf<Pair<String, FakeStreamerPort>>()
    private var nextState = ShopliveBroadcastState.IDLE
    private val live = object : ShopliveStreamerDelegate {
        override fun onEvent(streamer: cloud.shoplive.streamer.ShopliveStreamer, event: ShopliveStreamerEvent) {}
    }
    private val handler = StreamerMethodHandler<String>(
        portFactory = { host -> FakeStreamerPort(nextState).also { created += host to it } },
        liveDelegate = { live },
    )

    private fun call(method: String, args: Map<String, Any?>? = null) = handler.handle(method, Args.of(args))

    @Test // case: F-02
    fun start_withoutHost_isNoHostScreen() {
        val e = assertThrows(BridgeStateException::class.java) { call("start", mapOf("campaignKey" to "k")) }
        assertEquals(BridgeErrorCode.NO_HOST_SCREEN, e.code)
    }

    @Test // case: F-04
    fun start_blankKey_isInvalid() {
        handler.attachHost("A")
        assertThrows(BridgeArgumentException::class.java) { call("start", mapOf("campaignKey" to "")) }
        assertEquals(0, created.size)
    }

    @Test // case: SMV-1749 webPageUrl 생략/null → null(3.0.2 동작), http(s) URL → 그대로 전달
    fun start_webPageUrl_omittedNullOrValid() {
        handler.attachHost("A")
        call("start", mapOf("campaignKey" to "k1"))
        call("start", mapOf("campaignKey" to "k2", "webPageUrl" to null))
        call("start", mapOf("campaignKey" to "k3", "webPageUrl" to "https://shop.example.com/p?id=1"))
        call("start", mapOf("campaignKey" to "k4", "webPageUrl" to "HTTP://example.com"))
        assertEquals(
            listOf(null, null, "https://shop.example.com/p?id=1", "HTTP://example.com"),
            created.map { it.second.webPageUrls.single() },
        )
    }

    @Test // case: SMV-1749 webPageUrl 비http(s)·형식 오류·비String → INVALID_ARGUMENT, 인스턴스 생성·이전 세션 해제 없음
    fun start_webPageUrl_invalid_isInvalidArgument_andCreatesNothing() {
        handler.attachHost("A")
        call("start", mapOf("campaignKey" to "k0"))
        val previous = created.single().second
        for (bad in listOf("", "   ", "example.com", "/relative", "ftp://example.com", "javascript:alert(1)", "https://", "http://exa mple.com", 1)) {
            val e = assertThrows(bad.toString(), BridgeArgumentException::class.java) {
                call("start", mapOf("campaignKey" to "k", "webPageUrl" to bad))
            }
            assertEquals("webPageUrl", e.key)
        }
        assertEquals(1, created.size)
        assertSame(live, previous.delegate)
    }

    @Test // case: SMV-1749 R1-01 공용 벡터 — iOS BridgeCoreTests.testHttpURLSharedVectors와 같은 파일·같은 기대값(플랫폼 판정 일치)
    fun webUrlRule_sharedVectors_matchIos() {
        // 테스트 작업 디렉토리 = shoplive_streamer/android
        val file = java.io.File(System.getProperty("user.dir"), "../test/fixtures/http_url_vectors.json")
        assertTrue("missing ${file.canonicalPath}", file.isFile)
        val vectors = org.json.JSONObject(file.readText()).getJSONArray("vectors")
        assertTrue(vectors.length() >= 50)
        for (i in 0 until vectors.length()) {
            val v = vectors.getJSONObject(i)
            val input = v.getString("input")
            val accept = v.getBoolean("accept")
            val args = Args.of(mapOf("u" to input))
            if (accept) {
                assertEquals(input, input, args.optHttpUrl("u")) // 통과 시 문자열 그대로 SDK로
            } else {
                val e = assertThrows(input, BridgeArgumentException::class.java) { args.optHttpUrl("u") }
                assertEquals("u", e.key)
                assertTrue(input, input.isEmpty() || input.isBlank() || !e.message!!.contains(input))
            }
        }
    }

    @Test // case: ST-01
    fun getState_withoutInstance_isIdle_andNeedsNoHost() {
        assertEquals("idle", call("getState"))
    }

    @Test // case: ST-01
    fun eachStart_newInstance_previousDelegateReleased() {
        handler.attachHost("A1")
        call("start", mapOf("campaignKey" to "k1"))
        val first = created.last().second
        assertSame(live, first.delegate)
        handler.attachHost("A2")
        call("start", mapOf("campaignKey" to "k2"))
        val second = created.last().second
        assertNull(first.delegate)
        assertSame(live, second.delegate)
        assertEquals("A2", created.last().first)
        assertEquals(listOf("k2"), second.started)
        assertEquals("preview", call("getState"))
    }

    @Test // case: ST-01
    fun detachHost_releasesIdleOnly_keepsEndedAndActive() {
        handler.attachHost("A")
        call("start", mapOf("campaignKey" to "k"))
        val p = created.last().second
        p.state = ShopliveBroadcastState.LIVE
        handler.detachHost()
        assertSame(live, p.delegate)
        assertEquals("live", call("getState"))
        p.state = ShopliveBroadcastState.ENDED
        handler.detachHost()
        assertSame(live, p.delegate) // F3-M1: ENDED는 유지
        assertEquals("ended", call("getState"))
        p.state = ShopliveBroadcastState.IDLE
        handler.detachHost()
        assertNull(p.delegate)
        // pair #26: 해제 후에도 마지막 상태 보존
        assertEquals("idle", call("getState"))
    }

    @Test // case: R-03, ST-01
    fun engineDetached_releasesDelegate() {
        handler.attachHost("A")
        call("start", mapOf("campaignKey" to "k"))
        val p = created.last().second
        handler.onEngineDetached()
        assertNull(p.delegate)
        assertEquals("preview", call("getState"))
    }

    @Test // case: ST-01 (F3-M1)
    fun ended_keepsInstanceAndDelegate_restartInPlaceEventsReachDart() {
        val gen = AttachGeneration().also { it.next() }
        val scheduler = FakeScheduler()
        val emitter = EventEmitter("e", scheduler)
        val sink = RecordingSink()
        emitter.onListen(null, sink)
        val bridge = StreamerDelegateBridge(gen, gen.current, scheduler, emitter)
        val h = StreamerMethodHandler<String>(portFactory = { FakeStreamerPort() }, liveDelegate = { bridge })
        h.attachHost("A")
        h.handle("start", Args.of(mapOf("campaignKey" to "k")))
        val p = h.currentPortForTest()!! as FakeStreamerPort
        p.state = ShopliveBroadcastState.ENDED
        bridge.handle(ShopliveStreamerEvent.StateChanged(ShopliveBroadcastState.ENDED, false))
        h.detachHost() // ENDED는 해제하지 않음
        assertSame(bridge, p.delegate)
        // SDK가 같은 인스턴스로 재시작(restartInPlace)
        p.state = ShopliveBroadcastState.LIVE
        bridge.handle(ShopliveStreamerEvent.StateChanged(ShopliveBroadcastState.CONNECTING, false))
        bridge.handle(ShopliveStreamerEvent.StateChanged(ShopliveBroadcastState.LIVE, false))
        assertEquals(listOf("ended", "connecting", "live"), sink.events.map { (it as Map<*, *>)["state"] })
        assertEquals("live", h.handle("getState", Args.of(null)))
    }

    @Test // case: F-05
    fun unknownMethod_isNotImplemented() {
        assertThrows(MethodNotImplemented::class.java) { call("stop") }
    }

    // ---- Delegate 브릿지 ----

    @Test // case: T-05, R-03
    fun delegateBridge_emitsOnMain_dropsWhenStale() {
        val gen = AttachGeneration().also { it.next() }
        val scheduler = FakeScheduler()
        val emitter = EventEmitter("e", scheduler)
        val sink = RecordingSink()
        emitter.onListen(null, sink)
        val bridge = StreamerDelegateBridge(gen, gen.current, scheduler, emitter)
        bridge.handle(ShopliveStreamerEvent.StateChanged(ShopliveBroadcastState.CONNECTING, false))
        scheduler.onMain = false
        bridge.handle(ShopliveStreamerEvent.StateChanged(ShopliveBroadcastState.LIVE, false))
        assertEquals(1, sink.events.size)
        scheduler.onMain = true
        scheduler.runPosted()
        assertEquals(2, sink.events.size)
        gen.next()
        bridge.handle(ShopliveStreamerEvent.StateChanged(ShopliveBroadcastState.ENDED, false))
        assertEquals(2, sink.events.size)
    }

    // ---- Plugin ----

    @Test // case: R-03
    fun plugin_beforeAttach_completesOnceWithSdkError() {
        val calls = mutableListOf<String>()
        var message: String? = null
        ShopliveStreamerPlugin().onMethodCall(
            MethodCall("getState", null),
            object : MethodChannel.Result {
                override fun success(result: Any?) { calls += "success" }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) { calls += errorCode; message = errorMessage }
                override fun notImplemented() { calls += "notImplemented" }
            },
        )
        assertEquals(listOf("SDK_ERROR"), calls)
        assertEquals("plugin detached", message)
        assertTrue(true)
    }
}
