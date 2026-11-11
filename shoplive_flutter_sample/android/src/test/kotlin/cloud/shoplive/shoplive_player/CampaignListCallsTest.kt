package cloud.shoplive.shoplive_player

import cloud.shoplive.core.publicsurface.ShopliveError
import cloud.shoplive.core.publicsurface.ShopliveErrorCode
import cloud.shoplive.player.ShopliveCampaignListCallback
import cloud.shoplive.player.ShopliveCampaignListRequest
import cloud.shoplive.player.ShopliveCampaignListResponse
import cloud.shoplive.player.ShopliveCancellable
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/** getCampaigns 진행 중 요청(SMV-1899 D10, R6-A5). SDK 대신 콜백을 붙잡는 fetch 대역으로 성공·실패·취소·늦은 도착을 만든다. */
class CampaignListCallsTest {

    private class Fetched(val request: ShopliveCampaignListRequest, val callback: ShopliveCampaignListCallback) {
        var cancels = 0
    }

    private val fetched = mutableListOf<Fetched>()
    private var fetchFailure: RuntimeException? = null
    private val calls = CampaignListCalls { request, callback ->
        fetchFailure?.let { throw it }
        val f = Fetched(request, callback).also { fetched += it }
        ShopliveCancellable { f.cancels++ }
    }

    private fun begin(id: String, request: Map<String, Any?>? = null): RecordingResult = RecordingResult().also { r ->
        calls.begin(Args.of(mapOf("requestId" to id, "request" to request)), r)
    }

    private fun cancel(id: String): Boolean = calls.cancel(Args.of(mapOf("requestId" to id)))

    @Test // case: G-1 — 성공은 SDK 콜백 때 1회, 요청은 매핑돼 SDK로
    fun success_repliesOnceWithWire() {
        val r = begin("a", mapOf("statuses" to listOf("closed"), "size" to 5))
        assertEquals(emptyList<String>(), r.calls) // 회신은 콜백 때
        assertEquals(ShopliveCampaignListRequest(size = 5, statuses = listOf(ShopliveCampaignListRequest.Status.CLOSED)), fetched.single().request)
        fetched.single().callback.onSuccess(ShopliveCampaignListResponse(emptyList(), hasMore = false))
        fetched.single().callback.onSuccess(ShopliveCampaignListResponse(emptyList(), hasMore = true)) // SDK가 두 번 불러도 회신은 1회
        assertEquals(listOf("success"), r.calls)
        assertEquals(mapOf("campaigns" to emptyList<Any>(), "hasMore" to false), r.value)
    }

    @Test // case: G-7 — 실패는 SDK_ERROR + details = ShopliveError wire(code·message·rawCode·recoverable)
    fun failure_isSdkErrorWithShopliveErrorDetails() {
        val r = begin("a")
        fetched.single().callback.onFailure(ShopliveError(ShopliveErrorCode.UNKNOWN, -200, "Failed to fetch campaign list.", null, false))
        assertEquals(listOf("error"), r.calls)
        assertEquals(BridgeErrorCode.SDK_ERROR, r.errorCode)
        assertEquals(mapOf("code" to "UNKNOWN", "message" to "Failed to fetch campaign list.", "rawCode" to -200, "recoverable" to false), r.errorDetails)
    }

    @Test // case: G-8·G-9 — 취소: SDK 취소 1회 + CANCELLED 1회, 그 뒤 도착한 콜백은 버림, 다시 취소하면 false
    fun cancel_cancelsSdkOnce_repliesCancelled_dropsLateCallback() {
        val r = begin("a")
        assertEquals(true, cancel("a"))
        assertEquals(1, fetched.single().cancels)
        assertEquals(listOf("error"), r.calls)
        assertEquals(PlayerContract.CANCELLED, r.errorCode)
        fetched.single().callback.onSuccess(ShopliveCampaignListResponse(emptyList(), hasMore = false))
        assertEquals(listOf("error"), r.calls)
        assertEquals(false, cancel("a"))
        assertEquals(false, cancel("never"))
    }

    @Test // case: G-10 — 동시 요청은 서로 독립(역순 도착)
    fun concurrent_requestsAreIndependent() {
        val a = begin("a")
        val b = begin("b")
        fetched[1].callback.onSuccess(ShopliveCampaignListResponse(emptyList(), hasMore = true))
        fetched[0].callback.onFailure(ShopliveError(ShopliveErrorCode.FAILED_NETWORK, 9900, "m", null, true))
        assertEquals(listOf("success"), b.calls)
        assertEquals(listOf("error"), a.calls)
    }

    @Test // case: G-12 — 진행 중인 id를 다시 쓰면 INVALID_ARGUMENT, 앞 요청은 그대로
    fun duplicateId_isInvalid_firstStays() {
        val first = begin("a")
        val e = assertThrows(BridgeArgumentException::class.java) { begin("a") }
        assertEquals(PlayerContract.REQUEST_ID, e.key)
        assertEquals(1, fetched.size)
        fetched.single().callback.onSuccess(ShopliveCampaignListResponse(emptyList(), hasMore = false))
        assertEquals(listOf("success"), first.calls)
    }

    @Test // case: G-6 — 인자 오류는 등록·SDK 호출 전에 던진다(호출자가 1회로 끝낸다)
    fun invalidArgs_throwBeforeRegistering() {
        assertThrows(BridgeArgumentException::class.java) { calls.begin(Args.of(mapOf("request" to null)), RecordingResult()) }
        assertThrows(BridgeArgumentException::class.java) { begin("a", mapOf("order" to "latest")) }
        assertEquals(0, fetched.size)
        assertEquals(false, cancel("a"))
    }

    @Test // case: G-1 — SDK 호출 자체가 던지면 등록을 되돌리고 던진다(회신은 호출자 1회)
    fun fetchThrows_unregistersAndRethrows() {
        fetchFailure = IllegalStateException("boom")
        assertThrows(IllegalStateException::class.java) { begin("a") }
        fetchFailure = null
        begin("a") // 같은 id를 다시 쓸 수 있다
        assertEquals(1, fetched.size)
    }

    @Test // case: G-11 — 엔진 detach: 진행 중 SDK 요청을 모두 취소하고 회신하지 않는다, 늦은 콜백도 버림
    fun cancelAll_cancelsEverything_withoutReplies() {
        val a = begin("a")
        val b = begin("b")
        calls.cancelAll()
        assertEquals(listOf(1, 1), fetched.map { it.cancels })
        fetched[0].callback.onSuccess(ShopliveCampaignListResponse(emptyList(), hasMore = false))
        assertEquals(emptyList<String>(), a.calls)
        assertEquals(emptyList<String>(), b.calls)
        assertEquals(false, cancel("b"))
    }
}
