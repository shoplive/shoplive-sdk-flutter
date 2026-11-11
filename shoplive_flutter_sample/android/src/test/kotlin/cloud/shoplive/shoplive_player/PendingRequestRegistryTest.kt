package cloud.shoplive.shoplive_player

import cloud.shoplive.player.ShopliveCouponResult
import cloud.shoplive.player.ShopliveCustomActionResult
import cloud.shoplive.player.ShoplivePlayerEvent
import cloud.shoplive.player.ShoplivePlayerRequest
import cloud.shoplive.player.ShoplivePlayerState
import cloud.shoplive.player.ShopliveResultAlertType
import cloud.shoplive.player.ShopliveResultStatus
import cloud.shoplive.player.ShopliveShareInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingRequestRegistryTest {

    private val scheduler = FakeScheduler()
    private val registry = PendingRequestRegistry(scheduler)
    private val couponResults = mutableListOf<ShopliveCouponResult>()
    private val actionResults = mutableListOf<ShopliveCustomActionResult>()

    private fun couponPending(id: String = "c1") = PendingRequest.Coupon(id) { couponResults += it }
    private fun actionPending(id: String = "a1") = PendingRequest.CustomAction(id) { actionResults += it }

    // ---- Registry: 정확히 1회 respond (C-4) ----

    @Test // case: U-06, N-06
    fun timeout_respondsFallbackOnce_withContractValues() {
        registry.register(couponPending())
        scheduler.advance(PendingRequestRegistry.DEFAULT_TIMEOUT_MS - 1)
        assertEquals(0, couponResults.size)
        scheduler.advance(1)
        assertEquals(1, couponResults.size)
        val r = couponResults.single()
        assertEquals("c1", r.couponId)
        assertEquals(false, r.success)
        assertNull(r.message)
        assertEquals(ShopliveResultStatus.KEEP, r.status)
        assertEquals(ShopliveResultAlertType.TOAST, r.alertType)
        scheduler.advance(PendingRequestRegistry.DEFAULT_TIMEOUT_MS)
        assertEquals(1, couponResults.size)
    }

    @Test // case: T-03
    fun dartFirst_thenTimer_noFallback() {
        val id = registry.register(couponPending())
        val taken = registry.take(id)!!
        (taken as PendingRequest.Coupon).respond(ShopliveCouponResult("c1", true, null, ShopliveResultStatus.SHOW, null))
        assertEquals(0, scheduler.pendingTimers())
        scheduler.advance(PendingRequestRegistry.DEFAULT_TIMEOUT_MS * 2)
        assertEquals(1, couponResults.size)
        assertEquals(true, couponResults.single().success)
    }

    @Test // case: T-03
    fun timerFirst_thenDart_takeReturnsNull() {
        val id = registry.register(couponPending())
        scheduler.advance(PendingRequestRegistry.DEFAULT_TIMEOUT_MS)
        assertNull(registry.take(id))
        assertEquals(1, couponResults.size)
    }

    @Test // case: T-06
    fun duplicateTake_secondIsNull() {
        val id = registry.register(actionPending())
        assertTrue(registry.take(id) != null)
        assertNull(registry.take(id))
    }

    @Test // case: R-02, R-03
    fun flushAll_respondsEveryPendingOnce_andCancelsTimers() {
        registry.register(couponPending("c1"))
        registry.register(actionPending("a1"))
        registry.flushAll()
        assertEquals(1, couponResults.size)
        assertEquals(1, actionResults.size)
        assertEquals(false, actionResults.single().success)
        assertEquals(0, scheduler.pendingTimers())
        assertEquals(0, registry.size())
        registry.flushAll()
        assertEquals(1, couponResults.size)
    }

    @Test // case: B-08
    fun timeout_change_appliesToLaterRequestsOnly() {
        registry.register(couponPending("c1"))
        registry.setTimeoutMs(PendingRequestRegistry.MIN_TIMEOUT_MS)
        registry.register(couponPending("c2"))
        scheduler.advance(PendingRequestRegistry.MIN_TIMEOUT_MS)
        assertEquals(listOf("c2"), couponResults.map { it.couponId })
        scheduler.advance(PendingRequestRegistry.DEFAULT_TIMEOUT_MS)
        assertEquals(listOf("c2", "c1"), couponResults.map { it.couponId })
    }

    @Test // case: B-08
    fun timeout_range_boundaries() {
        for (bad in listOf(-5L, 0L, 999L, 120_001L, Long.MAX_VALUE)) {
            assertThrows("$bad", BridgeArgumentException::class.java) { registry.setTimeoutMs(bad) }
        }
        registry.setTimeoutMs(1_000L)
        registry.setTimeoutMs(120_000L)
    }

    @Test // case: F-03
    fun respondThrowing_isGuarded_andStillRemoved() {
        val id = registry.register(PendingRequest.Coupon("c1") { throw IllegalStateException("sdk") })
        scheduler.advance(PendingRequestRegistry.DEFAULT_TIMEOUT_MS)
        assertNull(registry.take(id))
    }

    @Test // case: N-04
    fun requestIds_areUniqueOpaqueStrings() {
        val a = registry.register(couponPending())
        val b = registry.register(couponPending())
        assertTrue(a != b)
    }

    // ---- Delegate 브릿지 ----

    private val gen = AttachGeneration().also { it.next() }
    private val events = EventEmitter("events", scheduler)
    private val requests = EventEmitter("requests", scheduler, onCancelled = { registry.flushAll() })
    private val eventSink = RecordingSink()
    private val requestSink = RecordingSink()
    private val bridge = PlayerDelegateBridge(gen, gen.current, scheduler, events, requests, registry)

    private fun coupon(id: String = "c1") = ShoplivePlayerRequest.Coupon(id) { couponResults += it }
    private fun action(id: String = "a1") = ShoplivePlayerRequest.CustomWebAction(id, "t", mapOf("k" to 1)) { actionResults += it }

    @Test // case: N-04
    fun noRequestListener_couponFallsBackImmediately() {
        bridge.onRequest(FakePort(), coupon())
        assertEquals(1, couponResults.size)
        assertEquals(false, couponResults.single().success)
        assertEquals(0, registry.size())
    }

    @Test // case: N-04
    fun withListener_couponIsEmittedAndRegistered() {
        requests.onListen(null, requestSink)
        bridge.onRequest(FakePort(), coupon("c9"))
        val emitted = requestSink.events.single() as Map<*, *>
        assertEquals("coupon", emitted["type"])
        assertEquals("c9", emitted["couponId"])
        assertEquals(1, registry.size())
        assertEquals(0, couponResults.size)
        assertTrue(registry.take(emitted["requestId"] as String) is PendingRequest.Coupon)
    }

    @Test // case: B-07
    fun withListener_emitFailure_fallsBackImmediately() {
        requests.onListen(null, RecordingSink(IllegalArgumentException("codec")))
        bridge.onRequest(FakePort(), action())
        assertEquals(1, actionResults.size)
        assertEquals(0, registry.size())
    }

    @Test // case: R-02
    fun requestsCancel_flushesPending() {
        requests.onListen(null, requestSink)
        bridge.onRequest(FakePort(), coupon())
        requests.onCancel(null)
        assertEquals(1, couponResults.size)
    }

    @Test // case: N-04
    fun navigation_emittedOrDropped_noRespond() {
        bridge.onRequest(FakePort(), ShoplivePlayerRequest.Navigation("u"))
        requests.onListen(null, requestSink)
        bridge.onRequest(FakePort(), ShoplivePlayerRequest.Navigation("u2"))
        assertEquals(listOf(mapOf("type" to "navigation", "url" to "u2")), requestSink.events)
    }

    @Test // case: N-03
    fun events_emitted_whenListening() {
        events.onListen(null, eventSink)
        bridge.onEvent(FakePort(), ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.Loading))
        assertEquals(mapOf("type" to "stateChanged", "state" to "loading"), eventSink.events.single())
    }

    @Test // case: R-03
    fun staleGeneration_requestsFallBack_eventsDropped() {
        events.onListen(null, eventSink)
        requests.onListen(null, requestSink)
        gen.next() // 엔진 detach 이후
        bridge.onEvent(FakePort(), ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.Loading))
        bridge.onRequest(FakePort(), coupon())
        assertEquals(0, eventSink.events.size)
        assertEquals(0, requestSink.events.size)
        assertEquals(1, couponResults.size)
    }

    @Test // case: T-05
    fun offMainRequest_isHandledOnMain() {
        scheduler.onMain = false
        bridge.onRequest(FakePort(), coupon())
        assertEquals(0, couponResults.size)
        scheduler.onMain = true
        scheduler.runPosted()
        assertEquals(1, couponResults.size)
    }

    @Test // case: R-03
    fun detachedDelegate_respondsFallbackToRequests_ignoresEvents() {
        DetachedDelegate.onRequest(FakePort(), coupon())
        DetachedDelegate.onRequest(FakePort(), action())
        DetachedDelegate.onRequest(FakePort(), ShoplivePlayerRequest.Navigation("u"))
        DetachedDelegate.onEvent(FakePort(), ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.Idle))
        assertEquals(1, couponResults.size)
        assertEquals(1, actionResults.size)
    }

    @Test // case: A2-1 (D3, 교차검증 1차 LOW) — 리스너 없이 shareRequested: 예외 없이 폐기(경고 로그), 구독 뒤에는 1건 전달
    fun shareRequested_withoutListener_isDroppedSafely_thenDeliveredOnceListening() {
        val share = ShoplivePlayerEvent.ShareRequested(ShopliveShareInfo(url = "https://s/1"))
        bridge.onEvent(FakePort(), share)
        events.onListen(null, eventSink)
        bridge.onEvent(FakePort(), share)
        assertEquals(1, eventSink.events.size)
        assertEquals("shareRequested", (eventSink.events.single() as Map<*, *>)["type"])
    }

    @Test // case: A4-5 (R-A8) — retire 뒤 판정: 이벤트 폐기, 요청 폴백 1회(DetachedDelegate와 같은 응답), navigation 버림
    fun retiredBridge_dropsEvents_fallsBackRequests() {
        events.onListen(null, eventSink)
        requests.onListen(null, requestSink)
        bridge.retire()
        bridge.onEvent(FakePort(), ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.Loading))
        bridge.onRequest(FakePort(), coupon())
        bridge.onRequest(FakePort(), ShoplivePlayerRequest.Navigation("u"))
        assertEquals(0, eventSink.events.size)
        assertEquals(0, requestSink.events.size)
        assertEquals(1, couponResults.size)
        assertEquals(0, registry.size())
    }
}
