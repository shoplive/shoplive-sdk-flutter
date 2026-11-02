package cloud.shoplive.shoplive_player

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import cloud.shoplive.player.ShoplivePlayer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * shoplive_player 플러그인 — 채널 `shoplive_player`, `shoplive_player/events`, `shoplive_player/requests`(design.md rev2 §2.1).
 * 생명주기 배선만 담당하고 메서드 처리는 PlayerMethodHandler, 요청 응답은 PendingRequestRegistry가 맡는다.
 */
class ShoplivePlayerPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    private val attach = AttachGeneration()
    private var methodChannel: MethodChannel? = null
    private var eventsChannel: EventChannel? = null
    private var requestsChannel: EventChannel? = null
    private var events: EventEmitter? = null
    private var requests: EventEmitter? = null
    private var registry: PendingRequestRegistry? = null
    private var handler: PlayerMethodHandler<Activity>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val generation = attach.next()
        val scheduler = HandlerMainScheduler()
        val registry = PendingRequestRegistry(scheduler)
        val events = EventEmitter(PlayerContract.EVENTS_CHANNEL, scheduler)
        // requests 구독 해제 → 남은 대기 요청을 폴백으로 1회 응답(design §2.7-7)
        val requests = EventEmitter(PlayerContract.REQUESTS_CHANNEL, scheduler, onCancelled = { registry.flushAll() })
        val handler = PlayerMethodHandler<Activity>(
            registry = registry,
            portFactory = { activity -> SdkPlayerPort(ShoplivePlayer(activity)) },
            liveDelegate = { PlayerDelegateBridge(attach, generation, scheduler, events, requests, registry) },
            drawableId = drawableResolver(binding.applicationContext),
        )
        this.registry = registry
        this.events = events
        this.requests = requests
        this.handler = handler
        val messenger = binding.binaryMessenger
        methodChannel = MethodChannel(messenger, PlayerContract.METHOD_CHANNEL).also { it.setMethodCallHandler(this) }
        eventsChannel = EventChannel(messenger, PlayerContract.EVENTS_CHANNEL).also { it.setStreamHandler(events) }
        requestsChannel = EventChannel(messenger, PlayerContract.REQUESTS_CHANNEL).also { it.setStreamHandler(requests) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventsChannel?.setStreamHandler(null)
        requestsChannel?.setStreamHandler(null)
        methodChannel = null
        eventsChannel = null
        requestsChannel = null
        attach.next() // 이후 도착하는 delegate 콜백은 stale 세대 → 이벤트 드롭·요청 폴백
        handler?.onEngineDetached()
        registry?.flushAll()
        events?.clear()
        requests?.clear()
        handler = null
        registry = null
        events = null
        requests = null
    }

    /**
     * PIP 버튼 nativeImageName → 앱 drawable 리소스 ID(SMV-1899 A3). applicationContext만 캡처(Activity 누수 없음, host가 없어도 설정 가능).
     * 이름 → ID만 하고 Drawable 로드는 SDK가 PIP 진입 때 한다(다크 모드·밀도 반영). 0(없음)은 PlayerMapper.resolveImage가 null로 바꾼다.
     * getIdentifier는 이름 기반 조회라 lint가 권장하지 않지만, Dart에서 이름으로만 지정할 수 있어 대안이 없다.
     */
    @SuppressLint("DiscouragedApi")
    private fun drawableResolver(context: Context): (String) -> Int? = { name ->
        // TODO(SDP-VERIFY): 요확인 — release shrinkResources 시 Dart에서만 이름으로 참조하는 drawable이 유지되는지(keep.xml), applicationIdSuffix 빌드에서 packageName 기준 getIdentifier가 해석되는지 실측 · 근거 SMV-1899
        context.resources.getIdentifier(name, "drawable", context.packageName)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Bridge.safeCall(TAG, call.method, result) {
            val h = handler ?: throw BridgeStateException(BridgeErrorCode.SDK_ERROR, DETACHED_MESSAGE)
            h.handle(call.method, Args.of(call.arguments))
        }
    }

    // ---- ActivityAware: 호스트 화면 바인딩(F-02, T-04, R-04) ----

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        HostLifecycleShim.ensure(binding.activity)
        handler?.attachHost(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        handler?.detachHost()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        HostLifecycleShim.ensure(binding.activity)
        handler?.attachHost(binding.activity)
    }

    override fun onDetachedFromActivity() {
        handler?.detachHost()
    }

    companion object {
        const val METHOD_CHANNEL = PlayerContract.METHOD_CHANNEL
        internal const val DETACHED_MESSAGE = "plugin detached"
        private const val TAG = "ShoplivePlayerPlugin"
    }
}
