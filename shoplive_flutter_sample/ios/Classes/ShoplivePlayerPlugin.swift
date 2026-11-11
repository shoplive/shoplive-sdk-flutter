import Flutter
import UIKit
import ShoplivePlayerSDK

/// shoplive_player plugin - channels `shoplive_player`, `shoplive_player/events`, `shoplive_player/requests`.
/// Lifecycle wiring only; methods are handled by PlayerMethodHandler, request responses by PendingRequests.
public final class ShoplivePlayerPlugin: NSObject, FlutterPlugin {
    static let methodChannelName = "shoplive_player"
    static let eventsChannelName = "shoplive_player/events"
    static let requestsChannelName = "shoplive_player/requests"
    private static let tag = "ShoplivePlayerPlugin"

    private let attach = AttachGeneration()
    private let scheduler = DispatchMainScheduler()
    private var methodChannel: FlutterMethodChannel?
    private var eventsChannel: FlutterEventChannel?
    private var requestsChannel: FlutterEventChannel?
    private var events: EventEmitter?
    private var requests: EventEmitter?
    private var registry: PendingRequests<PendingRequest>?
    private var handler: PlayerMethodHandler?
    private var campaigns: CampaignListCalls?
    // FlutterEventChannel keeps its stream handler weakly in some engine versions - keep them alive.
    private var streamHandlers: [EmitterStreamHandler] = []

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = ShoplivePlayerPlugin()
        instance.attachToEngine(registrar)
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)
    }

    private func attachToEngine(_ registrar: FlutterPluginRegistrar) {
        attach.next()
        let registry = PendingRequests<PendingRequest>(scheduler: scheduler)
        let events = EventEmitter(name: Self.eventsChannelName, scheduler: scheduler)
        // Dart cancelled the requests subscription -> answer every pending request once with the fallback.
        let requests = EventEmitter(name: Self.requestsChannelName, scheduler: scheduler,
                                    onCancelled: { [weak registry] in registry?.flushAll() })
        let attach = self.attach
        let scheduler = self.scheduler
        handler = PlayerMethodHandler(registry: registry, hostScreen: KeyWindowHostScreen()) { [weak events, weak requests, weak registry] handler in
            guard let events = events, let requests = requests, let registry = registry else { return nil }
            return PlayerDelegateBridge(handler: handler, events: events, requests: requests, registry: registry,
                                        attach: attach, scheduler: scheduler)
        }
        campaigns = CampaignListCalls(scheduler: scheduler)
        self.registry = registry
        self.events = events
        self.requests = requests
        let messenger = registrar.messenger()
        methodChannel = FlutterMethodChannel(name: Self.methodChannelName, binaryMessenger: messenger)
        let eventsHandler = EmitterStreamHandler(emitter: events)
        let requestsHandler = EmitterStreamHandler(emitter: requests)
        streamHandlers = [eventsHandler, requestsHandler]
        eventsChannel = FlutterEventChannel(name: Self.eventsChannelName, binaryMessenger: messenger)
        eventsChannel?.setStreamHandler(eventsHandler)
        requestsChannel = FlutterEventChannel(name: Self.requestsChannelName, binaryMessenger: messenger)
        requestsChannel?.setStreamHandler(requestsHandler)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        methodChannel?.setMethodCallHandler(nil)
        eventsChannel?.setStreamHandler(nil)
        requestsChannel?.setStreamHandler(nil)
        attach.next() // later SDK callbacks are stale: events dropped, requests answered with the fallback
        handler?.onEngineDetached()
        campaigns?.cancelAll()
        campaigns = nil
        registry?.flushAll()
        events?.clear()
        requests?.clear()
        handler = nil
        registry = nil
        streamHandlers = []
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let deferred = call.method == "getCampaigns" // the only method answered later, by CampaignListCalls (SMV-1899 D10-e)
        let outcome = bridgedCall { () -> Any? in
            switch call.method {
            case "getCampaigns":
                guard let campaigns = campaigns else { throw bridgeDetachedError }
                try campaigns.begin(try Args.of(call.arguments), reply: result)
                return nil
            case "cancelGetCampaigns":
                guard let campaigns = campaigns else { throw bridgeDetachedError }
                return try campaigns.cancel(try Args.of(call.arguments))
            default:
                guard let handler = handler else { throw bridgeDetachedError }
                return try handler.handle(call.method, try Args.of(call.arguments))
            }
        }
        if case .failure(let f) = outcome { bridgeLog(Self.tag, "\(call.method): \(f.code)") }
        // A started getCampaigns is replied by CampaignListCalls; only its early failures are delivered here (exactly once).
        if deferred, case .success = outcome { return }
        outcome.deliver(result)
    }
}
