package cloud.shoplive.shoplive_streamer

import android.app.Activity
import cloud.shoplive.streamer.ShopliveBroadcastState
import cloud.shoplive.streamer.ShopliveStreamer
import cloud.shoplive.streamer.ShopliveStreamerDelegate
import cloud.shoplive.streamer.ShopliveStreamerEvent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** ShopliveStreamer 위임 경계(테스트에서 대체). */
internal interface StreamerPort {
    var delegate: ShopliveStreamerDelegate?
    val state: ShopliveBroadcastState
    /** [webPageUrl] null = 웹페이지 없음(SDK 기본, 3.0.2 동작). */
    fun start(campaignKey: String, webPageUrl: String?)
}

internal class SdkStreamerPort(private val streamer: ShopliveStreamer) : StreamerPort {
    override var delegate: ShopliveStreamerDelegate?
        get() = streamer.streamerDelegate
        set(value) { streamer.streamerDelegate = value }
    override val state: ShopliveBroadcastState get() = streamer.state
    // URL이 없으면 3.0.2와 같은 호출 그대로(SDK 기본값 경로)
    override fun start(campaignKey: String, webPageUrl: String?) =
        if (webPageUrl == null) streamer.start(campaignKey) else streamer.start(campaignKey, webPageUrl = webPageUrl)
}

/** 살아 있는 엔진용 delegate. 세대가 바뀌었으면(엔진 detach 이후) 드롭(pair #13). SDK는 메인으로 전달(S7), 방어적으로 hop. */
internal class StreamerDelegateBridge(
    private val attach: AttachGeneration,
    private val generation: Long,
    private val scheduler: MainScheduler,
    private val events: EventEmitter,
) : ShopliveStreamerDelegate {

    override fun onEvent(streamer: ShopliveStreamer, event: ShopliveStreamerEvent) = handle(event)

    fun handle(event: ShopliveStreamerEvent) {
        if (!scheduler.isMainThread()) {
            scheduler.post { handle(event) }
            return
        }
        if (!attach.isCurrent(generation)) return
        Bridge.guardCallback(TAG, "onEvent") { events.emit(StreamerMapper.eventToWire(event)) }
    }

    companion object {
        private const val TAG = "ShopliveStreamerDelegate"
    }
}

/**
 * 채널 `shoplive_streamer` 메서드 처리(design.md rev2 §2.4·§4.3, ST-01). [H]는 호스트 화면(Android: Activity).
 * start마다 현재 호스트로 새 인스턴스(Streamer는 Context를 strong 참조 — S8), 이전 인스턴스 delegate 해제.
 */
internal class StreamerMethodHandler<H : Any>(
    private val portFactory: (H) -> StreamerPort,
    private val liveDelegate: () -> ShopliveStreamerDelegate,
) {
    private var host: H? = null
    private var port: StreamerPort? = null

    /** 해제한 인스턴스의 마지막 상태 — 회전 등으로 해제된 뒤 getState가 idle로 후퇴하지 않게 보존(pair #26). */
    private var lastState: ShopliveBroadcastState? = null

    fun attachHost(newHost: H) {
        host = newHost
    }

    /**
     * 호스트 detach: IDLE 인스턴스만 delegate·참조 해제. ENDED는 유지한다 — SDK가 ENDED에서 같은 인스턴스로
     * 재시작(restartInPlace)할 수 있어, 해제하면 그 이벤트가 유실되고 getState가 어긋난다(교차검증 F3-M1).
     * 옛 Activity 참조는 인스턴스 1개로 한정해 수용(README 한계).
     */
    fun detachHost() {
        host = null
        val p = port ?: return
        if (p.state == ShopliveBroadcastState.IDLE) release()
    }

    fun onEngineDetached() {
        host = null
        release()
    }


    fun handle(method: String, args: Args): Any? = when (method) {
        StreamerContract.START -> start(args)
        StreamerContract.GET_STATE -> wireOf(port?.state ?: lastState ?: ShopliveBroadcastState.IDLE, StreamerMapper.BROADCAST_STATE)
        else -> throw MethodNotImplemented
    }

    private fun start(args: Args): Any? {
        val currentHost = host ?: throw BridgeStateException(BridgeErrorCode.NO_HOST_SCREEN, "no host screen (Activity) attached")
        val campaignKey = args.requireString(StreamerContract.CAMPAIGN_KEY)
        // SDK 3.0.3 webPageUrl: 생략·null = 웹페이지 없음(3.0.2 동작). 인자 검증을 인스턴스 생성·이전 세션 해제보다 먼저
        val webPageUrl = args.optHttpUrl(StreamerContract.WEB_PAGE_URL)
        // TODO(SDP-VERIFY): 요확인 — 이전 인스턴스가 진행 중(LIVE 등)일 때 새 start의 SDK 동작과, 이전 인스턴스 delegate 해제로 그 ENDED/Error 이벤트가 Dart에 오지 않는 문제(R2-m6) · 근거 DRAFT-flutter-sdk-302-android/ST-01 · 자동 통과 금지(실측)
        release()
        val p = portFactory(currentHost)
        p.delegate = liveDelegate()
        port = p
        p.start(campaignKey, webPageUrl)
        return null
    }

    internal fun currentPortForTest(): StreamerPort? = port

    private fun release() {
        val p = port ?: return
        lastState = p.state
        p.delegate = null
        port = null
    }
}

/** shoplive_streamer 플러그인 — 채널 `shoplive_streamer`, `shoplive_streamer/events`(design.md rev2 §2.1). */
class ShopliveStreamerPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    private val attach = AttachGeneration()
    private var methodChannel: MethodChannel? = null
    private var eventsChannel: EventChannel? = null
    private var events: EventEmitter? = null
    private var handler: StreamerMethodHandler<Activity>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val generation = attach.next()
        val scheduler = HandlerMainScheduler()
        val events = EventEmitter(StreamerContract.EVENTS_CHANNEL, scheduler)
        this.events = events
        handler = StreamerMethodHandler(
            portFactory = { activity -> SdkStreamerPort(ShopliveStreamer(activity)) },
            liveDelegate = { StreamerDelegateBridge(attach, generation, scheduler, events) },
        )
        methodChannel = MethodChannel(binding.binaryMessenger, StreamerContract.METHOD_CHANNEL).also { it.setMethodCallHandler(this) }
        eventsChannel = EventChannel(binding.binaryMessenger, StreamerContract.EVENTS_CHANNEL).also { it.setStreamHandler(events) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventsChannel?.setStreamHandler(null)
        methodChannel = null
        eventsChannel = null
        attach.next()
        handler?.onEngineDetached()
        events?.clear()
        handler = null
        events = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Bridge.safeCall(TAG, call.method, result) {
            val h = handler ?: throw BridgeStateException(BridgeErrorCode.SDK_ERROR, DETACHED_MESSAGE)
            h.handle(call.method, Args.of(call.arguments))
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        handler?.attachHost(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        handler?.detachHost()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        handler?.attachHost(binding.activity)
    }

    override fun onDetachedFromActivity() {
        handler?.detachHost()
    }

    companion object {
        const val METHOD_CHANNEL = StreamerContract.METHOD_CHANNEL
        internal const val DETACHED_MESSAGE = "plugin detached"
        private const val TAG = "ShopliveStreamerPlugin"
    }
}
