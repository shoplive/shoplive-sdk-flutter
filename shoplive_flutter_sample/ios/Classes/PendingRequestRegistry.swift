import Foundation
import ShoplivePlayerSDK

/// A coupon / custom-action request awaiting a Dart respond (C-4).
enum PendingRequest {
    case coupon(couponId: String, respond: (ShopliveCouponResult) -> Void)
    case customAction(id: String, respond: (ShopliveCustomActionResult) -> Void)

    func respondFallback() {
        switch self {
        case .coupon(let couponId, let respond): respond(FallbackResults.coupon(couponId))
        case .customAction(let id, let respond): respond(FallbackResults.customAction(id))
        }
    }
}

/// Single source of the fallback values: success=false, message=nil, status=keep, alertType=toast.
enum FallbackResults {
    static func coupon(_ couponId: String) -> ShopliveCouponResult {
        ShopliveCouponResult(couponId: couponId, success: false, message: nil, status: .keep, alertType: .toast)
    }

    static func customAction(_ id: String) -> ShopliveCustomActionResult {
        ShopliveCustomActionResult(id: id, success: false, message: nil, status: .keep, alertType: .toast)
    }
}

/// Delegate for released / engine-detached players: answers requests with the fallback at once, drops events (X-01).
final class DetachedPlayerDelegate: ShoplivePlayerDelegate {
    static let shared = DetachedPlayerDelegate()

    func player(_ player: any ShoplivePlayerControlling, didReceive event: ShoplivePlayerEvent) {}

    func player(_ player: any ShoplivePlayerControlling, didRequest request: ShoplivePlayerRequest) {
        Self.respondFallback(request)
    }

    static func respondFallback(_ request: ShoplivePlayerRequest) {
        switch request {
        case .coupon(let id, let respond): respond(FallbackResults.coupon(id))
        case .customWebAction(let id, _, _, let respond): respond(FallbackResults.customAction(id))
        case .navigation: break
        @unknown default: break
        }
    }
}

/// Delegate of the live engine. Holds the handler, emitters and registry weakly (IOS-m3, no retain cycle);
/// events from a stale generation are dropped and their requests answered with the fallback.
final class PlayerDelegateBridge: ShoplivePlayerDelegate {
    private weak var handler: PlayerMethodHandler?
    private weak var events: EventEmitter?
    private weak var requests: EventEmitter?
    private weak var registry: PendingRequests<PendingRequest>?
    private weak var attach: AttachGeneration?
    private let generation: Int
    private let scheduler: MainScheduler

    init(handler: PlayerMethodHandler, events: EventEmitter, requests: EventEmitter, registry: PendingRequests<PendingRequest>,
         attach: AttachGeneration, scheduler: MainScheduler) {
        self.handler = handler
        self.events = events
        self.requests = requests
        self.registry = registry
        self.attach = attach
        self.generation = attach.current
        self.scheduler = scheduler
    }

    private var isCurrent: Bool { attach?.isCurrent(generation) ?? false }

    func player(_ player: any ShoplivePlayerControlling, didReceive event: ShoplivePlayerEvent) {
        onMain { [weak self] in
            guard let self = self, self.isCurrent else { return }
            if case .stateChanged(.closed) = event { self.handler?.playerDidClose(player) }
            // D3(a'): isCustomShareEnabled=true but Dart does not listen -> the SDK shows no sheet either, so log the cause.
            // The event is still emitted (EventEmitter drops it); judged at delivery, so a listener added after start works (SMV-1899 A2-1).
            if case .shareRequested = event, self.events?.hasListener != true {
                bridgeLog("ShoplivePlayerDelegate", "shareRequested dropped: navigation.isCustomShareEnabled is true but no Dart listener on ShoplivePlayer.events")
            }
            self.events?.emit(PlayerMapper.eventToWire(event))
        }
    }

    func player(_ player: any ShoplivePlayerControlling, didRequest request: ShoplivePlayerRequest) {
        onMain { [weak self] in
            guard let self = self, self.isCurrent else {
                DetachedPlayerDelegate.respondFallback(request)
                return
            }
            self.handle(request)
        }
    }

    private func handle(_ request: ShoplivePlayerRequest) {
        switch request {
        case .navigation(let url):
            requests?.emit(PlayerMapper.navigationToWire(url))
        case .coupon(let id, let respond):
            dispatch(.coupon(couponId: id, respond: respond)) { PlayerMapper.couponToWire(requestId: $0, couponId: id) }
        case .customWebAction(let id, let type, let payload, let respond):
            dispatch(.customAction(id: id, respond: respond)) {
                PlayerMapper.customWebActionToWire(requestId: $0, id: id, actionType: type, payload: payload)
            }
        @unknown default:
            requests?.emit(["type": wireUnknown, "rawType": "unknown"])
        }
    }

    /// No Dart listener -> fallback at once (user decision). Otherwise register, emit, and fall back if the emit fails.
    private func dispatch(_ pending: PendingRequest, wire: (String) -> [String: Any]) {
        guard let requests = requests, requests.hasListener, let registry = registry else {
            pending.respondFallback()
            return
        }
        let id = registry.register(pending) { $0.respondFallback() }
        if !requests.emit(wire(id)) { registry.take(id)?.respondFallback() }
    }

    private func onMain(_ block: @escaping () -> Void) {
        if scheduler.isMainThread() { block() } else { scheduler.post(block) }
    }
}
