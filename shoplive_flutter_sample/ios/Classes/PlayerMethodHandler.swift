import Foundation
import UIKit
import ShoplivePlayerSDK

/// Thin subclass to observe dismissal (I-R-02). ShoplivePlayerViewController is an open class.
final class BridgedPlayerViewController: ShoplivePlayerViewController {
    var onDismissed: (() -> Void)?

    override init(campaignKey: String, options: ShoplivePlayOptions, configuration: ShoplivePlayerConfiguration) {
        super.init(campaignKey: campaignKey, options: options, configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { onDismissed?() }
    }
}

/// Channel `shoplive_player` methods (Android design section 2.4, iOS design section 2.2).
/// The iOS SDK has no off-screen player: `start` creates a ShoplivePlayerViewController and presents it (I1).
/// Instances are created only by `start`; without one, queries return defaults/saved settings and setters only store.
/// Main thread only (MethodChannel).
final class PlayerMethodHandler {
    private static let tag = "ShoplivePlayer"

    private let registry: PendingRequests<PendingRequest>
    private let hostScreen: HostScreenProviding
    private let makeDelegate: (PlayerMethodHandler) -> ShoplivePlayerDelegate

    private var controller: BridgedPlayerViewController?
    /// The SDK holds the delegate weakly (Player:305/347) - keep it alive here (I-L-01).
    private var liveDelegate: ShoplivePlayerDelegate?

    // Last confirmed settings, carried to every new controller (R2-N1).
    private var savedConfiguration: ShoplivePlayerConfiguration?
    private var savedType = PlayerMapper.defaultType
    private var savedResizeMode: ShopliveResizeMode?
    private var savedOverlayUI: ShopliveOverlayUIMode?

    init(registry: PendingRequests<PendingRequest>, hostScreen: HostScreenProviding,
         makeDelegate: @escaping (PlayerMethodHandler) -> ShoplivePlayerDelegate) {
        self.registry = registry
        self.hostScreen = hostScreen
        self.makeDelegate = makeDelegate
    }

    func handle(_ method: String, _ args: Args) throws -> Any? {
        switch method {
        case "start": return try start(args)
        case "play":
            let key = try args.requireString("campaignKey")
            let options = try PlayerMapper.toPlayOptions(try args.optArgs("playOptions"))
            try running().play(campaignKey: key, options: options)
        case "stop": try running().stop()
        case "close": controller?.close() // no instance -> idempotent no-op
        case "reload": try running().reload()
        case "send":
            let command = try args.requireString("command")
            let payload = try args.optStringKeyMap("payload") ?? [:]
            try running().send(command: command, payload: payload)
        case "setMuted":
            let muted = try args.requireBool("muted")
            let c = try running()
            c.isMuted = muted
        case "isMuted": return controller?.isMuted ?? false
        case "setResizeMode":
            let mode = try args.requireWireEnum("mode", PlayerMapper.resizeMode)
            controller?.resizeMode = mode
            savedResizeMode = mode
        case "getResizeMode":
            return wireOf(controller?.resizeMode ?? savedResizeMode ?? currentConfiguration().appearance.resizeMode, PlayerMapper.resizeMode)
        case "setOverlayUI":
            let mode = try args.requireWireEnum("mode", PlayerMapper.overlayUI)
            controller?.overlayUI = mode
            savedOverlayUI = mode
        case "getOverlayUI":
            return wireOf(controller?.overlayUI ?? savedOverlayUI ?? currentConfiguration().overlay.ui, PlayerMapper.overlayUI)
        case "enterPictureInPicture": try running().enterPictureInPicture()
        case "exitPictureInPicture": try running().exitPictureInPicture()
        case "isInPictureInPicture": return controller?.isInPictureInPicture ?? false
        case "getState": return wireOf(controller?.state ?? .idle, PlayerMapper.playerState)
        case "getCurrentCampaign": return PlayerMapper.campaignToWire(controller?.currentCampaign)
        case "isRunning": return isRunning
        case "setConfiguration":
            let (merged, type) = try PlayerMapper.mergeConfiguration(currentConfiguration(), currentType: savedType,
                                                                      partial: try args.requireArgs("configuration"))
            // TODO(SDP-VERIFY): 요확인 — 실행 중 setConfiguration 효과(SDK가 무시하는지) · 근거 SMV-1749
            controller?.configuration = merged
            savedConfiguration = merged
            savedType = type
        case "getConfiguration":
            // Settings the next start uses (saved first), same meaning as Android: a running session may keep what it started with.
            return PlayerMapper.configurationToWire(currentConfiguration(), type: savedType)
        case "setRequestTimeout":
            guard let ms = try args.optInt("timeoutMs") else {
                throw BridgeArgumentError(key: "timeoutMs", expected: "Int", actual: "missing")
            }
            try registry.setTimeoutMs(ms)
        case "respondCoupon": return try respondCoupon(args)
        case "respondCustomAction": return try respondCustomAction(args)
        case "respondFallback":
            guard let pending = registry.take(try args.requireString("requestId")) else { return false }
            pending.respondFallback()
            return true
        default:
            throw BridgeNotImplemented()
        }
        return nil
    }

    // MARK: start (pre-validation order as on Android; a new controller per start - SMV-1749)

    private func start(_ args: Args) throws -> Any? {
        let campaignKey = try args.requireString("campaignKey")
        let options = try PlayerMapper.toPlayOptions(try args.optArgs("playOptions"))
        let partial = try args.optArgs("configuration")
        var effective = currentConfiguration()
        var type = savedType
        if let partial = partial {
            (effective, type) = try PlayerMapper.mergeConfiguration(effective, currentType: savedType, partial: partial)
        }
        if options.presentationStyle == .pip && !effective.pip.isInAppPipEnabled {
            // B-09: reject before creating anything.
            throw BridgeArgumentError(key: "playOptions.presentationStyle", expected: "fullscreen unless pip.isInAppPipEnabled", actual: "pip")
        }
        // Check the host before anything is closed: a start without a host screen must not end the running session.
        guard hostScreen.topViewController() != nil else { throw noHostScreen() }
        // SMV-1749: every start opens a new controller carrying this call's effective configuration. A started SDK player does not
        // take a new configuration (Android SDK 3.0.3 ConfigurationGuard accepts it only while IDLE; the iOS setter's effect on a
        // running controller is unverified - former I-S-01), so the IOS-M1 "switch campaign in the same controller" path is gone.
        var configuration = effective
        if let mode = savedResizeMode { configuration.appearance.resizeMode = mode }
        if let ui = savedOverlayUI { configuration.overlay.ui = ui }
        let next = BridgedPlayerViewController(campaignKey: campaignKey, options: options, configuration: configuration)
        let delegate = makeDelegate(self)
        next.delegate = delegate
        next.onDismissed = { [weak self, weak next] in
            guard let self = self, let next = next else { return }
            self.controllerDidDismiss(next)
        }
        guard let previous = controller else {
            guard present(next) else { throw detachUnpresented(next) }
            adopt(next, delegate: delegate, partial: partial, effective: effective, type: type)
            return nil
        }
        if previous.presentingViewController == nil || previous.isBeingDismissed {
            // Not on screen (in-app PIP / already going away): present the new player first and retire the previous session
            // only after the presentation started, so a failed start leaves the running session alone (R4-01).
            guard present(next) else { throw detachUnpresented(next) }
            retire(previous)
            adopt(next, delegate: delegate, partial: partial, effective: effective, type: type)
            return nil
        }
        // Still presented: it must be dismissed before the next one can be presented (presenting over it would stack two players,
        // and dismissing it later would also dismiss the new one), so present-first is impossible here. If the deferred
        // presentation fails, Dart gets one closed state for the retired session (R4-02).
        retire(previous)
        adopt(next, delegate: delegate, partial: partial, effective: effective, type: type)
        previous.dismiss(animated: false) { [weak self, weak next] in
            guard let self = self, let next = next, self.controller === next else { return }
            // TODO(SDP-VERIFY): 요확인 — 이전 플레이어 dismiss 후 새 플레이어 present 실패는 start가 이미 성공을 반환해 Dart에 closed 상태로만 알림(스트리머 IM-m3와 같은 구조), 전환 화면 실측 · 근거 SMV-1749
            if !self.present(next) {
                delegate.player(next, didReceive: .stateChanged(.closed)) // bridge -> playerDidClose releases it
                if self.controller === next { self.release(next); self.controller = nil }
            }
        }
        return nil
    }

    // MARK: lifecycle

    /// D-7: no SDK isRunning - a held controller whose state is not closed.
    private var isRunning: Bool {
        guard let c = controller else { return false }
        // TODO(SDP-VERIFY): 요확인 - closed 이후 VC가 스스로 dismiss 되는지, in-app PIP 중 VC 상태 · 근거 DRAFT-flutter-sdk-302-ios/D-7 · 자동 통과 금지(실측)
        return c.state != .closed
    }

    private func running() throws -> BridgedPlayerViewController {
        guard let c = controller, isRunning else {
            throw BridgeStateError(code: BridgeErrorCode.notRunning, message: "player is not running")
        }
        return c
    }

    /// stateChanged(.closed) from the SDK: release the controller, dismissing it if it is still on screen.
    func playerDidClose(_ player: any ShoplivePlayerControlling) {
        guard let c = controller, c === player as AnyObject else { return }
        if c.presentingViewController != nil, !c.isBeingDismissed { c.dismiss(animated: true) }
        release(c)
        controller = nil
    }

    private func controllerDidDismiss(_ dismissed: BridgedPlayerViewController) {
        // Dismissed without a closed state may be the SDK moving to in-app PIP - keep it then (I-R-02).
        guard dismissed === controller, dismissed.state == .closed else { return }
        release(dismissed)
        controller = nil
    }

    /// Detaches the replaced controller first (its closed/dismiss events must not follow the new session's events), answers its
    /// pending coupon/custom requests once with the fallback, then closes it. Later requests from it get DetachedPlayerDelegate.
    private func retire(_ previous: BridgedPlayerViewController) {
        release(previous)
        if controller === previous { controller = nil }
        registry.flushAll()
        if previous.state != .closed { previous.close() }
    }

    private func adopt(_ next: BridgedPlayerViewController, delegate: ShoplivePlayerDelegate, partial: Args?,
                       effective: ShoplivePlayerConfiguration, type: String) {
        controller = next
        liveDelegate = delegate
        if partial != nil {
            savedConfiguration = effective
            savedType = type
        }
    }

    /// D-9: overFullScreen keeps the Flutter screen underneath (in-app PIP).
    private func present(_ next: BridgedPlayerViewController) -> Bool {
        // TODO(SDP-VERIFY): 요확인 - PIP 중 아래 Flutter 화면 터치 가능 여부, .overFullScreen 적합성 · 근거 DRAFT-flutter-sdk-302-ios/D-9 · 자동 통과 금지(실측)
        presentOnHostScreen(next, host: hostScreen, style: .overFullScreen)
    }

    private func detachUnpresented(_ next: BridgedPlayerViewController) -> BridgeStateError {
        next.onDismissed = nil
        next.delegate = DetachedPlayerDelegate.shared
        return noHostScreen()
    }

    private func noHostScreen() -> BridgeStateError {
        BridgeStateError(code: BridgeErrorCode.noHostScreen, message: "no host screen (view controller) to present the player")
    }

    private func release(_ c: BridgedPlayerViewController?) {
        guard let c = c else { return }
        c.onDismissed = nil
        c.delegate = DetachedPlayerDelegate.shared
        if c === controller { liveDelegate = nil }
    }

    /// Engine detach (X-01): the session stays; requests are answered by DetachedPlayerDelegate.
    func onEngineDetached() {
        // TODO(SDP-VERIFY): 요확인 - 엔진 재attach 후 이전 엔진 세션 제어 불가(새 핸들러가 VC를 모름) · 근거 DRAFT-flutter-sdk-302-ios/U-04 · 자동 통과 금지(실측)
        controller?.onDismissed = nil
        controller?.delegate = DetachedPlayerDelegate.shared
        controller = nil
        liveDelegate = nil
        savedConfiguration = nil
        savedType = PlayerMapper.defaultType
        savedResizeMode = nil
        savedOverlayUI = nil
    }

    /// Merge base: saved -> held controller -> SDK default instance.
    private func currentConfiguration() -> ShoplivePlayerConfiguration {
        savedConfiguration ?? controller?.configuration ?? ShoplivePlayerConfiguration()
    }

    // MARK: respond (C-4)

    private func respondCoupon(_ args: Args) throws -> Bool {
        let id = try args.requireString("requestId")
        guard let pending = registry.peek(id) else { return false }
        guard case .coupon(let couponId, let respond) = pending else { throw kindMismatch() }
        let result = try PlayerMapper.toCouponResult(couponId: couponId, args) // invalid args keep the entry
        guard registry.take(id) != nil else { return false }
        respond(result)
        return true
    }

    private func respondCustomAction(_ args: Args) throws -> Bool {
        let id = try args.requireString("requestId")
        guard let pending = registry.peek(id) else { return false }
        guard case .customAction(let actionId, let respond) = pending else { throw kindMismatch() }
        let result = try PlayerMapper.toCustomActionResult(id: actionId, args)
        guard registry.take(id) != nil else { return false }
        respond(result)
        return true
    }

    private func kindMismatch() -> BridgeArgumentError {
        BridgeArgumentError(key: "requestId", expected: "request id of matching kind", actual: "other kind")
    }
}
