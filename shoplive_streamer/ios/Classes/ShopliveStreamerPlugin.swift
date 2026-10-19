import Flutter
import UIKit
import ShopliveStreamerSDK

/// Live delegate; holds the emitter weakly, drops stale-generation events, hops to main.
final class StreamerDelegateBridge: ShopliveStreamerDelegate {
    private weak var events: EventEmitter?
    private weak var attach: AttachGeneration?
    private let generation: Int
    private let scheduler: MainScheduler

    init(events: EventEmitter, attach: AttachGeneration, scheduler: MainScheduler) {
        self.events = events
        self.attach = attach
        self.generation = attach.current
        self.scheduler = scheduler
    }

    func streamer(_ streamer: ShopliveStreamerViewController, didReceive event: ShopliveStreamerEvent) {
        let block = { [weak self] in
            guard let self = self, self.attach?.isCurrent(self.generation) ?? false else { return }
            self.events?.emit(StreamerMapper.eventToWire(event))
        }
        if scheduler.isMainThread() { block() } else { scheduler.post(block) }
    }
}

/// Channel `shoplive_streamer` methods (design section 2.6). Every `start` creates a new broadcast view controller;
/// an `ended` session is kept (F3-M1), getState reports the held controller or the last released state.
final class StreamerMethodHandler {
    private let hostScreen: HostScreenProviding
    private let makeDelegate: () -> ShopliveStreamerDelegate?
    private var controller: ShopliveStreamerViewController?
    /// streamerDelegate is weak in the SDK (Streamer:161) - keep it alive here.
    private var liveDelegate: ShopliveStreamerDelegate?
    private var lastState: ShopliveBroadcastState?

    init(hostScreen: HostScreenProviding, makeDelegate: @escaping () -> ShopliveStreamerDelegate?) {
        self.hostScreen = hostScreen
        self.makeDelegate = makeDelegate
    }

    func handle(_ method: String, _ args: Args) throws -> Any? {
        switch method {
        case "start":
            let campaignKey = try args.requireString("campaignKey")
            // SDK 3.0.3 webPageURL: missing/null = no web page (3.0.2 behavior). Validated before any controller is created.
            try start(campaignKey, webPageURL: try args.optHttpURL("webPageUrl"))
            return nil
        case "getState":
            return wireOf(controller?.state ?? lastState ?? .idle, StreamerMapper.broadcastState)
        default:
            throw BridgeNotImplemented()
        }
    }

    private func start(_ campaignKey: String, webPageURL: URL?) throws {
        // No URL keeps the exact 3.0.2 call (convenience init) - the designated init's nil semantics are not in the interface.
        let next = webPageURL.map { ShopliveStreamerViewController(campaignKey: campaignKey, webPageURL: $0) }
            ?? ShopliveStreamerViewController(campaignKey: campaignKey)
        let delegate = makeDelegate()
        next.streamerDelegate = delegate
        let previous = controller
        // TODO(SDP-VERIFY): 요확인 - 방송 중 재start 시 이전 방송 화면 처리(여기서는 dismiss 후 새 화면 present). 이 경로는 success를 먼저 반환하므로 dismiss 이후 present 실패가 Dart에 전달되지 않음(IM-m3) · 근거 DRAFT-flutter-sdk-302-ios/I-L-02 · 자동 통과 금지(실측)
        if let previous = previous, previous.presentingViewController != nil, !previous.isBeingDismissed {
            release()
            controller = next
            liveDelegate = delegate
            previous.dismiss(animated: false) { [weak self, weak next] in
                guard let self = self, let next = next else { return }
                if !presentOnHostScreen(next, host: self.hostScreen, style: .fullScreen) { self.release() }
            }
            return
        }
        guard presentOnHostScreen(next, host: hostScreen, style: .fullScreen) else {
            next.streamerDelegate = nil
            throw BridgeStateError(code: BridgeErrorCode.noHostScreen, message: "no host screen (view controller) to present the broadcast")
        }
        release()
        controller = next
        liveDelegate = delegate
    }

    private func release() {
        guard let c = controller else { return }
        lastState = c.state
        c.streamerDelegate = nil
        controller = nil
        liveDelegate = nil
    }

    func onEngineDetached() { release() }
}

/// shoplive_streamer plugin - channels `shoplive_streamer`, `shoplive_streamer/events`.
public final class ShopliveStreamerPlugin: NSObject, FlutterPlugin {
    static let methodChannelName = "shoplive_streamer"
    static let eventsChannelName = "shoplive_streamer/events"
    private static let tag = "ShopliveStreamerPlugin"

    private let attach = AttachGeneration()
    private let scheduler = DispatchMainScheduler()
    private var methodChannel: FlutterMethodChannel?
    private var eventsChannel: FlutterEventChannel?
    private var events: EventEmitter?
    private var handler: StreamerMethodHandler?
    private var streamHandler: EmitterStreamHandler?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = ShopliveStreamerPlugin()
        instance.attach.next()
        let events = EventEmitter(name: eventsChannelName, scheduler: instance.scheduler)
        let attach = instance.attach
        let scheduler = instance.scheduler
        instance.events = events
        instance.handler = StreamerMethodHandler(hostScreen: KeyWindowHostScreen()) { [weak events] in
            events.map { StreamerDelegateBridge(events: $0, attach: attach, scheduler: scheduler) }
        }
        let messenger = registrar.messenger()
        let channel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
        instance.methodChannel = channel
        let streamHandler = EmitterStreamHandler(emitter: events)
        instance.streamHandler = streamHandler
        let eventsChannel = FlutterEventChannel(name: eventsChannelName, binaryMessenger: messenger)
        eventsChannel.setStreamHandler(streamHandler)
        instance.eventsChannel = eventsChannel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        methodChannel?.setMethodCallHandler(nil)
        eventsChannel?.setStreamHandler(nil)
        attach.next()
        handler?.onEngineDetached()
        events?.clear()
        handler = nil
        streamHandler = nil
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let outcome = bridgedCall { () -> Any? in
            guard let handler = handler else { throw bridgeDetachedError }
            return try handler.handle(call.method, try Args.of(call.arguments))
        }
        if case .failure(let f) = outcome { bridgeLog(Self.tag, "\(call.method): \(f.code)") }
        outcome.deliver(result)
    }
}
