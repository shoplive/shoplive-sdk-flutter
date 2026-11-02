package cloud.shoplive.shoplive_player

import android.util.Log
import cloud.shoplive.player.ShopliveCouponResult
import cloud.shoplive.player.ShopliveCustomActionResult
import cloud.shoplive.player.ShoplivePlayerControlling
import cloud.shoplive.player.ShoplivePlayerDelegate
import cloud.shoplive.player.ShoplivePlayerEvent
import cloud.shoplive.player.ShoplivePlayerRequest
import cloud.shoplive.player.ShopliveResultAlertType
import cloud.shoplive.player.ShopliveResultStatus

/** 응답 대기 중인 SDK 요청(Coupon·CustomWebAction). [respondFallback]은 계약 폴백 값(design §2.7-6). */
internal sealed class PendingRequest {
    abstract fun respondFallback()

    class Coupon(val couponId: String, val respond: (ShopliveCouponResult) -> Unit) : PendingRequest() {
        override fun respondFallback() = respond(FallbackResults.coupon(couponId))
    }

    class CustomAction(val id: String, val respond: (ShopliveCustomActionResult) -> Unit) : PendingRequest() {
        override fun respondFallback() = respond(FallbackResults.customAction(id))
    }
}

/** 폴백 값 단일 출처: success=false, message=null, status=KEEP, alertType=TOAST(사용자 결정, X-03). */
internal object FallbackResults {
    fun coupon(couponId: String) =
        ShopliveCouponResult(couponId, false, null, ShopliveResultStatus.KEEP, ShopliveResultAlertType.TOAST)

    fun customAction(id: String) =
        ShopliveCustomActionResult(id, false, null, ShopliveResultStatus.KEEP, ShopliveResultAlertType.TOAST)
}

/**
 * requestId → 대기 요청. 정확히 1회 respond(C-4): take()가 성공한 쪽만 응답한다.
 * 모든 연산은 메인 스레드에서 호출된다(MethodCall·Handler 타이머·SDK delegate 모두 main looper, design §2.7).
 */
internal class PendingRequestRegistry(private val scheduler: MainScheduler) {

    private class Entry(val request: PendingRequest, val timer: Cancellable)

    private val pending = LinkedHashMap<String, Entry>()
    private var seq = 0L
    private var timeoutMs = DEFAULT_TIMEOUT_MS

    fun size(): Int = pending.size

    /** 이후 등록되는 요청부터 적용. 범위 [MIN_TIMEOUT_MS, MAX_TIMEOUT_MS] 밖이면 INVALID_ARGUMENT(B-08 확정, pair #21). */
    fun setTimeoutMs(value: Long) {
        if (value < MIN_TIMEOUT_MS || value > MAX_TIMEOUT_MS) {
            throw BridgeArgumentException(PlayerContract.TIMEOUT_MS, "$MIN_TIMEOUT_MS..$MAX_TIMEOUT_MS", "out of range")
        }
        timeoutMs = value
    }

    fun register(request: PendingRequest): String {
        val id = (++seq).toString()
        val timer = scheduler.postDelayed({ take(id)?.let { respondFallback(it, "timeout") } }, timeoutMs)
        pending[id] = Entry(request, timer)
        return id
    }

    fun peek(id: String): PendingRequest? = pending[id]?.request

    /** 제거하고 타이머를 취소한다. 이미 처리된 id면 null(중복·만료 respond → false). */
    fun take(id: String): PendingRequest? {
        val entry = pending.remove(id) ?: return null
        entry.timer.cancel()
        return entry.request
    }

    /** 남은 대기를 모두 폴백으로 1회 respond(requests onCancel·엔진 detach, §2.7-7). */
    fun flushAll() {
        val ids = pending.keys.toList()
        ids.forEach { id -> take(id)?.let { respondFallback(it, "flush") } }
    }

    private fun respondFallback(request: PendingRequest, reason: String) =
        Bridge.guardCallback(TAG, "fallback($reason)") { request.respondFallback() }

    companion object {
        const val DEFAULT_TIMEOUT_MS = 10_000L
        const val MIN_TIMEOUT_MS = 1_000L
        const val MAX_TIMEOUT_MS = 120_000L
        private const val TAG = "ShoplivePendingRequests"
    }
}

/**
 * 엔진 detach 이후·이전 인스턴스에 꽂는 delegate(X-01). 요청에는 즉시 폴백 respond, 이벤트·navigation은 버림.
 * SDK는 delegate가 null이면 요청을 respond 없이 버리므로(S6) null 대신 이 객체를 쓴다.
 */
internal object DetachedDelegate : ShoplivePlayerDelegate {
    private const val TAG = "ShopliveDetachedDelegate"

    override fun onEvent(sender: ShoplivePlayerControlling, event: ShoplivePlayerEvent) = Unit

    override fun onRequest(sender: ShoplivePlayerControlling, request: ShoplivePlayerRequest) =
        Bridge.guardCallback(TAG, "onRequest") {
            when (request) {
                is ShoplivePlayerRequest.Coupon -> request.respond(FallbackResults.coupon(request.id))
                is ShoplivePlayerRequest.CustomWebAction -> request.respond(FallbackResults.customAction(request.id))
                else -> Unit // navigation 등 응답 없는 요청은 버린다
            }
        }
}

/**
 * 살아 있는 엔진용 delegate. 이벤트 → events 채널, 요청 → requests 채널 + Registry(design §2.7).
 * [generation]이 현재 세대가 아니면(엔진 detach 이후 도착) DetachedDelegate와 같이 처리한다(pair #13).
 */
internal class PlayerDelegateBridge(
    private val attach: AttachGeneration,
    private val generation: Long,
    private val scheduler: MainScheduler,
    private val events: EventEmitter,
    private val requests: EventEmitter,
    private val registry: PendingRequestRegistry,
) : ShoplivePlayerDelegate {

    override fun onEvent(sender: ShoplivePlayerControlling, event: ShoplivePlayerEvent) = onMain {
        if (!attach.isCurrent(generation)) return@onMain
        // D3(a'): isCustomShareEnabled=true인데 Dart가 events를 듣지 않으면 SDK 기본 시트도 뜨지 않아 공유가 무반응 → 원인을 경고로 남긴다.
        // 이벤트는 그대로 emit(폐기는 EventEmitter). 판정은 전달 시점이라 start 뒤에 생긴 구독도 정상 전달(SMV-1899 A2-1).
        Bridge.guardCallback(TAG, "onEvent") {
            if (event is ShoplivePlayerEvent.ShareRequested && !events.hasListener()) {
                Log.w(TAG, "shareRequested dropped: navigation.isCustomShareEnabled is true but no Dart listener on ShoplivePlayer.events")
            }
            events.emit(PlayerMapper.eventToWire(event))
        }
    }

    override fun onRequest(sender: ShoplivePlayerControlling, request: ShoplivePlayerRequest) = onMain {
        if (!attach.isCurrent(generation)) {
            DetachedDelegate.onRequest(sender, request)
            return@onMain
        }
        Bridge.guardCallback(TAG, "onRequest") { handle(request) }
    }

    private fun handle(request: ShoplivePlayerRequest) {
        when (request) {
            is ShoplivePlayerRequest.Navigation -> requests.emit(PlayerMapper.navigationToWire(request.url))
            is ShoplivePlayerRequest.Coupon -> dispatch(PendingRequest.Coupon(request.id, request.respond)) { id ->
                PlayerMapper.couponToWire(id, request.id)
            }
            is ShoplivePlayerRequest.CustomWebAction -> dispatch(PendingRequest.CustomAction(request.id, request.respond)) { id ->
                PlayerMapper.customWebActionToWire(id, request.id, request.type, request.payload)
            }
            else -> {
                Log.w(TAG, "unknown request ${request.javaClass.simpleName}")
                requests.emit(PlayerMapper.unknownToWire(request))
            }
        }
    }

    /** 미구독이면 즉시 폴백(사용자 결정). 구독 중이면 등록 후 emit, emit 실패 시 즉시 폴백. */
    private fun dispatch(pending: PendingRequest, wire: (String) -> Map<String, Any?>) {
        if (!requests.hasListener()) {
            pending.respondFallback()
            return
        }
        val id = registry.register(pending)
        if (!requests.emit(wire(id))) {
            registry.take(id)?.respondFallback()
        }
    }

    private inline fun onMain(crossinline block: () -> Unit) {
        if (scheduler.isMainThread()) block() else scheduler.post { block() }
    }

    companion object {
        private const val TAG = "ShoplivePlayerDelegate"
    }
}
