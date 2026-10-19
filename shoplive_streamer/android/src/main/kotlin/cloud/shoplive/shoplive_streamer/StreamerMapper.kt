package cloud.shoplive.shoplive_streamer

import cloud.shoplive.streamer.ShopliveBroadcastState
import cloud.shoplive.streamer.ShopliveStreamerEvent

/** 채널 `shoplive_streamer` 계약 이름(design.md rev2 §2.1·§2.4·§2.5). */
internal object StreamerContract {
    const val METHOD_CHANNEL = "shoplive_streamer"
    const val EVENTS_CHANNEL = "shoplive_streamer/events"

    const val START = "start"
    const val GET_STATE = "getState"
    val METHODS = listOf(START, GET_STATE)

    const val CAMPAIGN_KEY = "campaignKey"
    const val WEB_PAGE_URL = "webPageUrl"
}

/** Shoplive streamer 3.0.3 타입 → wire (순수 함수). */
internal object StreamerMapper {

    /** wire(Dart ShopliveBroadcastState.name) ↔ SDK 상수(design §2.3). */
    val BROADCAST_STATE = mapOf(
        "idle" to ShopliveBroadcastState.IDLE,
        "preview" to ShopliveBroadcastState.PREVIEW,
        "connecting" to ShopliveBroadcastState.CONNECTING,
        "live" to ShopliveBroadcastState.LIVE,
        "reconnecting" to ShopliveBroadcastState.RECONNECTING,
        "ended" to ShopliveBroadcastState.ENDED,
    )

    fun eventToWire(event: ShopliveStreamerEvent): Map<String, Any?> = when (event) {
        is ShopliveStreamerEvent.StateChanged ->
            mapOf(TYPE to "stateChanged", "state" to wireOf(event.state, BROADCAST_STATE), "isRehearsal" to event.isRehearsal)
        is ShopliveStreamerEvent.Error -> mapOf(TYPE to "error", "error" to Bridge.errorToWire(event.error))
        else -> mapOf(TYPE to WIRE_UNKNOWN, "rawType" to event.javaClass.simpleName.replaceFirstChar { it.lowercase() })
    }

    private const val TYPE = EventEmitter.KEY_TYPE
}
