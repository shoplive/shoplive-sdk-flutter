import Foundation
import UIKit
import ShoplivePlayerSDK

/// Thin subclass to observe dismissal (I-R-02), used by `start` only. ShoplivePlayerViewController is an open class.
/// A startPreview player is the SDK's own ShoplivePlayerViewController (SMV-2021 D2) and has no such hook - playerDidClose and
/// `close` release it instead.
final class BridgedPlayerViewController: ShoplivePlayerViewController {
    var onDismissed: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { onDismissed?() }
    }
}

/// Channel `shoplive_player` methods (Android design section 2.4, iOS design section 2.2).
/// The iOS SDK has no off-screen player: `start` creates a ShoplivePlayerViewController and presents it (I1); `startPreview` adopts
/// the player the SDK returns and shows itself (SMV-2021 D2). Instances come only from these two; without one, queries return
/// defaults/saved settings and setters only store. Main thread only (MethodChannel).
final class PlayerMethodHandler {
    private static let tag = "ShoplivePlayer"

    private let registry: PendingRequests<PendingRequest>
    private let hostScreen: HostScreenProviding
    /// Concrete PlayerDelegateBridge (single implementation, no protocol - SMV-1899 design 9); nil once the engine emitters are gone.
    private let makeDelegate: (PlayerMethodHandler) -> PlayerDelegateBridge?
    private let scheduler: MainScheduler

    /// The current session: a BridgedPlayerViewController from `start` or the SDK's startPreview player (public return type only -
    /// SMV-2021 design a-2). Screen facts are read through `onScreenViewController`.
    private var controller: (any ShoplivePlayerControlling)?
    /// The SDK holds the delegate weakly (Player:305/347) - keep it alive here (I-L-01).
    private var liveDelegate: PlayerDelegateBridge?
    /// startPreview calls waiting for their main hop (SMV-2021 design b-1). Held here because the SDK holds delegates weakly.
    private var pendingPreviews: [PreviewProbe] = []
    /// App intent generation (CG-11.2): bumped by every adoption (start, preview), close and engine detach. A preview whose call
    /// is older than the current generation was superseded while it waited and is not adopted (SMV-2021 D8).
    private var intentGeneration = 0

    // Last confirmed settings, carried to every new controller (R2-N1).
    private var savedConfiguration: ShoplivePlayerConfiguration?
    private var savedType = PlayerMapper.defaultType
    private var savedResizeMode: ShopliveResizeMode?
    private var savedOverlayUI: ShopliveOverlayUIMode?

    init(registry: PendingRequests<PendingRequest>, hostScreen: HostScreenProviding, scheduler: MainScheduler,
         makeDelegate: @escaping (PlayerMethodHandler) -> PlayerDelegateBridge?) {
        self.registry = registry
        self.hostScreen = hostScreen
        self.scheduler = scheduler
        self.makeDelegate = makeDelegate
    }

    func handle(_ method: String, _ args: Args) throws -> Any? {
        switch method {
        case "start": return try start(args)
        // startPreview is answered later - beginStartPreview, called by the plugin.
        case "play":
            let key = try args.requireString("campaignKey")
            let options = try PlayerMapper.toPlayOptions(try args.optArgs("playOptions"))
            try running().play(campaignKey: key, options: options) // the SDK ignores the same live campaign (3.0.6)
        case "stop": try running().stop()
        case "close": close()
        case "reload": try running().reload() // SDK 3.0.6: loading -> playing, no closed (ShoplivePlayerView.swift:846-876)
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
        case "getState": return PlayerMapper.stateToWire(controller?.state ?? .idle) // "closed" without the reason (SMV-1899 D2)
        case "getCurrentCampaign": return PlayerMapper.campaignToWire(controller?.currentCampaign)
        case "isRunning": return isRunning
        case "setConfiguration":
            let partial = try args.requireArgs("configuration")
            let (merged, type) = try PlayerMapper.mergeConfiguration(currentConfiguration(), currentType: savedType, partial: partial)
            // SMV-1899 D12: the controller gets the partial on top of its own configuration, not the saved one. Since SDK 3.0.5 the
            // configuration owns resizeMode / overlayUI and applies them at once (ShoplivePlayerView.swift:15-30, :491-493,
            // :971-973), so assigning the saved merge reset setResizeMode / setOverlayUI on a running player, and a preview
            // preset would be replaced. `type` is left out: it applies from the next start (start always presents a new
            // controller, so the current controller's type never reaches a later start).
            let instance = try controller.map {
                try PlayerMapper.mergeConfiguration($0.configuration, currentType: savedType, partial: partial,
                                                    applyType: false, warnUnresolvedImage: false).0
            }
            if let c = controller, let instance = instance { c.configuration = instance }
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
        // SMV-1749: every start opens a new controller carrying this call's effective configuration. The SDK accepts a new
        // configuration at any time (3.0.5 applies navigation.shareScheme, overlay.ui and sound.muteOnStart at once and the rest
        // from the next start/play/reload - SMV-1899 D12); the new controller per start is kept because it isolates the previous
        // session's events and requests (retire), so there is still no IOS-M1 "switch campaign in the same controller" path.
        var configuration = effective
        if let mode = savedResizeMode { configuration.appearance.resizeMode = mode }
        if let ui = savedOverlayUI { configuration.overlay.ui = ui }
        let next = BridgedPlayerViewController(campaignKey: campaignKey, options: options, configuration: configuration)
        try presentNewSession(next) {
            if partial != nil {
                savedConfiguration = effective
                savedType = type
            }
        }
        return nil
    }

    // MARK: startPreview (SMV-2021 D2: the iOS SDK 3.0.6 ShoplivePlayer.startPreview, design b-1)

    /// Throws only before the SDK call (argument errors, no host screen) - the caller then replies once. Otherwise `reply` runs
    /// exactly once: at once for the current player, or on the main hop after the SDK's own next-run-loop notices (settlePreview).
    /// It runs zero times if the engine detaches before the hop (no Dart side left). The SDK decides viewing / same key /
    /// other key (design 1.1); the bridge reads only the returned instance, its start facts and its rejection notice.
    /// Like Android, the preview uses the SDK presets plus muteOnFullScreen only - saved settings stay for the next start.
    func beginStartPreview(_ args: Args, reply: @escaping (BridgeOutcome) -> Void) throws {
        let campaignKey = try args.requireString("campaignKey") // blank key: before the SDK (D11-d)
        let muteOnFullScreen = try args.optBool("muteOnFullScreen") ?? false
        guard hostScreen.topViewController() != nil else { throw noHostScreen() }
        // The SDK API is @MainActor; this handler runs on the main thread only (MethodChannel).
        let player = MainActor.assumeIsolated {
            ShoplivePlayer.startPreview(campaignKey: campaignKey, muteOnFullScreen: muteOnFullScreen)
        }
        if let c = controller, c === player {
            // Same key -> the SDK keeps it; other key while floating -> the SDK swaps the campaign in the same player, no closed.
            // TODO(SDP-VERIFY): 요확인 — 같은 VC에서 캠페인 교체(swapFloating) 뒤 앞 캠페인의 대기 쿠폰·커스텀 요청 respond와 늦은 통지가 무해한지(브릿지는 flush하지 않음, registry 타임아웃 폴백), 실측 · 근거 SMV-2021
            reply(.success(nil))
            return
        }
        if let waiting = pendingPreviews.first(where: { $0.player === player }) {
            waiting.replies.append(reply) // the SDK returned the player still waiting for its hop (same key / retargeted key)
            // The later call wins (D8): a start / close between the two calls must not cancel this one (cross-check R-1).
            waiting.intent = intentGeneration
            return
        }
        let probe = PreviewProbe(player: player, session: makeDelegate(self), intent: intentGeneration,
                                 startedBeforeProbe: Self.isStarted(player), reply: reply)
        player.delegate = probe // right after the call: the SDK starts and notifies on the next main run loop (Preview.swift:43)
        pendingPreviews.append(probe)
        // TODO(SDP-VERIFY): 요확인 — SDK 거부 통지(9520·9000, 호출 안에서 DispatchQueue.main.async로 예약)가 이 홉보다 먼저 도는지(FIFO 가정), 실기기 확인 · 근거 SMV-2021
        scheduler.post { [weak self] in self?.settlePreview(probe) }
    }

    /// The hop verdict (design 2(b) table). Results are judged from what arrived and what the player reports now - never assumed.
    private func settlePreview(_ probe: PreviewProbe) {
        guard let index = pendingPreviews.firstIndex(where: { $0 === probe }) else { return } // engine detached: no reply
        pendingPreviews.remove(at: index)
        let player = probe.player
        if let rejection = probe.rejection {
            // Watching (9520) or not initialized (9000): the screen did not change. The notice is the call's result only.
            probe.discard()
            probe.finish(.failure(BridgeFailure(code: BridgeErrorCode.sdkError, message: rejection.message,
                                                details: ShopliveErrorWire.toWire(rejection))))
            return
        }
        guard probe.intent == intentGeneration else {
            // A start / close came while this call waited: the later call wins (an engine detach drops the probe in
            // onEngineDetached instead - no reply, the preview is left running) (D8 - this call still succeeds,
            // started or not yet; close() of an unstarted SDK preview drops its pending play - ShoplivePlayerViewController.close).
            probe.discard() // first, so the closed below does not reach Dart
            player.close() // always (§1(4) D8: the later start / close wins, cross-check N-1)
            probe.finish(.success(nil))
            return
        }
        guard Self.isStarted(player) else {
            probe.discard()
            probe.finish(.failure(BridgeFailure(code: BridgeErrorCode.sdkError, message: "startPreview: preview not started",
                                                details: nil)))
            return
        }
        if let previous = controller, previous !== player { retire(previous) }
        // TODO(SDP-VERIFY): 요확인 — 앱 네이티브 코드가 띄운 미리보기를 SDK가 같은 키·다른 키로 돌려주면 그 delegate를 브릿지가 가져감(반환값만으로 구분 불가), 혼용 앱 실측 · 근거 SMV-2021
        player.delegate = probe.session ?? DetachedPlayerDelegate.shared
        adopt(player, delegate: probe.session)
        probe.replayHeld(into: probe.session) // after the previous session was retired: its late events never follow these
        if probe.startedBeforeProbe {
            // Already running when returned (engine re-attach, an app-native preview): its earlier events went elsewhere, so
            // Dart gets the current state once (as Android St-a).
            probe.session?.player(player, didReceive: .stateChanged(player.state))
        }
        probe.finish(.success(nil))
    }

    /// Start fact of a player (no SDK isRunning, D-7): floating, or a state other than idle / closed.
    private static func isStarted(_ player: any ShoplivePlayerControlling) -> Bool {
        player.isInPictureInPicture || !(player.state == .idle || player.state.isClosed)
    }

    /// `start` only (a preview is shown by the SDK): wires the delegate, presents `next` and replaces the previous controller with
    /// the D6 retire rules. `onAdopt` runs when `next` becomes the current controller (synchronously in every branch).
    private func presentNewSession(_ next: BridgedPlayerViewController, onAdopt: () -> Void) throws {
        let delegate = makeDelegate(self)
        if let delegate = delegate { next.delegate = delegate } else { next.delegate = DetachedPlayerDelegate.shared }
        next.onDismissed = { [weak self, weak next] in
            guard let self = self, let next = next else { return }
            self.controllerDidDismiss(next)
        }
        guard let previous = controller else {
            guard present(next) else { throw detachUnpresented(next) }
            adopt(next, delegate: delegate)
            onAdopt()
            return
        }
        guard let previousScreen = onScreenViewController(previous) else {
            // Not on screen (in-app PIP / already going away): present the new player first and retire the previous session
            // only after the presentation started, so a failed start leaves the running session alone (R4-01).
            // SMV-1899 A0-7 (D6): mark the previous session's bridge retired before presenting, so a closed the SDK may send
            // to it when the new playback starts (Android closes other sessions; iOS unverified) never reaches Dart.
            // TODO(SDP-VERIFY): 요확인 — iOS SDK(3.0.5)가 새 재생(present) 때 다른 controller 세션을 닫는지 실측, HostScreen.swift:40-41 present 거부 경로(top.present 후 presentingViewController == nil)에서 새 VC가 로드되는지 확인 · 근거 SMV-1899
            let previousBridge = liveDelegate // `previous` is `controller` here (guard above)
            previousBridge?.isRetired = true
            guard present(next) else {
                // Unmark only, no synthetic closed (design 9): the certain failure path is no host screen (HostScreen.swift:30),
                // decided synchronously on the main thread before the new controller loads, so nothing can have closed the
                // previous session meanwhile - it stays the current one. (The :40-41 present-refused path is covered by the SDP-VERIFY marker above.)
                previousBridge?.isRetired = false
                throw detachUnpresented(next)
            }
            retire(previous)
            adopt(next, delegate: delegate)
            onAdopt()
            return
        }
        // Still presented: it must be dismissed before the next one can be presented (presenting over it would stack two players,
        // and dismissing it later would also dismiss the new one), so present-first is impossible here. If the deferred
        // presentation fails, Dart gets one closed state for the retired session (R4-02).
        retire(previous)
        adopt(next, delegate: delegate)
        onAdopt()
        previousScreen.dismiss(animated: false) { [weak self, weak next] in
            guard let self = self, let next = next, self.controller === next else { return }
            // TODO(SDP-VERIFY): 요확인 — 이전 플레이어 dismiss 후 새 플레이어 present 실패는 start가 이미 성공을 반환해 Dart에 closed 상태로만 알림(스트리머 IM-m3와 같은 구조), 전환 화면 실측 · 근거 SMV-1749
            if !self.present(next) {
                // Reason appRequest: replacing the broadcast is an app request, like SDK close() (SMV-1899 A4-3).
                delegate?.player(next, didReceive: .stateChanged(.closed(.appRequest))) // bridge -> playerDidClose releases it
                if self.controller === next { self.release(next); self.controller = nil }
            }
        }
    }

    // MARK: lifecycle

    /// D-7: no SDK isRunning - a held controller whose state is not closed.
    private var isRunning: Bool {
        guard let c = controller else { return false }
        // TODO(SDP-VERIFY): 요확인 - closed 이후 VC가 스스로 dismiss 되는지, in-app PIP 중 VC 상태 · 근거 DRAFT-flutter-sdk-302-ios/D-7 · 자동 통과 금지(실측)
        return !c.state.isClosed
    }

    private func running() throws -> any ShoplivePlayerControlling {
        guard let c = controller, isRunning else {
            throw BridgeStateError(code: BridgeErrorCode.notRunning, message: "player is not running")
        }
        return c
    }

    /// stateChanged(.closed) of the current session, matched by its bridge (each controller gets its own): the SDK reports the
    /// event with its ShoplivePlayerView as the sender, not the controller (3.0.5 PlayerDelegateAdapter.swift:241, the controller
    /// hands its delegate to the view - ShoplivePlayerViewController.swift:420-422; the same since 3.0.2), so a sender check never
    /// matched an SDK closed (SMV-1899 code cross-check M2).
    /// - Not on screen (in-app PIP / OS PIP closed, the SDK already dismissing it, the synthetic closed of a failed deferred
    ///   presentation, an SDK preview that never was expanded) -> release it now; nothing else would.
    /// - Still on screen (stop) -> keep it. The SDK leaves a stopped screen to the app (Dart close dismisses it). It is released
    ///   when it goes away (start: controllerDidDismiss; SDK preview: `close`) or is replaced (retire). (SDK 3.0.6 reload sends
    ///   no closed.)
    /// - An expanded SDK preview has no dismissal hook: its user close relies on the SDK announcing closed after the dismissal
    ///   started (SDK close(): ShoplivePlayerViewController.swift:469-496).
    func playerDidClose(reportedBy bridge: PlayerDelegateBridge) {
        guard let c = controller, bridge === liveDelegate else { return }
        // TODO(SDP-VERIFY): 요확인 — 키운 SDK 미리보기를 사용자가 ×로 닫을 때도 closed가 내림 시작 뒤에 오는지(아니면 닫힌 VC를 계속 쥐고 getState가 closed), Dart stop 뒤 사용자가 화면을 닫는 경로의 해제(다음 close·세션까지 VC 보유 — R-5), 실측 · 근거 SMV-2021
        guard onScreenViewController(c) == nil else { return }
        release(c)
        controller = nil
    }

    private func controllerDidDismiss(_ dismissed: BridgedPlayerViewController) {
        // Dismissed without a closed state may be the SDK moving to in-app PIP - keep it then (I-R-02).
        guard dismissed === controller, dismissed.state.isClosed else { return }
        release(dismissed)
        controller = nil
    }

    /// Detaches the replaced controller first (its closed/dismiss events must not follow the new session's events), answers its
    /// pending coupon/custom requests once with the fallback, then closes it. Later requests from it get DetachedPlayerDelegate.
    private func retire(_ previous: any ShoplivePlayerControlling) {
        // D6 (SMV-1899 A4-5): only this replacement path marks the bridge retired, so callbacks already queued for the main
        // hop are dropped when they run. release() on the current session (playerDidClose, controllerDidDismiss, the
        // synthetic-closed cleanup) does not mark it.
        if previous === controller { liveDelegate?.isRetired = true }
        release(previous)
        if controller === previous { controller = nil }
        registry.flushAll()
        if !previous.state.isClosed { previous.close() }
    }

    /// The only place a session becomes current; it supersedes a startPreview still waiting for its hop (intentGeneration).
    private func adopt(_ next: any ShoplivePlayerControlling, delegate: PlayerDelegateBridge?) {
        controller = next
        liveDelegate = delegate
        intentGeneration += 1
    }

    /// Dart close. No instance -> idempotent no-op (a waiting preview is still superseded).
    private func close() {
        intentGeneration += 1
        guard let c = controller else { return }
        let wasClosed = c.state.isClosed
        c.close()
        // Already closed (a stopped screen): the SDK sends no second closed. A start controller is released by its dismissal
        // hook; an SDK preview has none, so it is released here - otherwise the handler would hold it until the next session.
        if wasClosed, !(c is BridgedPlayerViewController), controller === c {
            release(c)
            controller = nil
        }
    }

    /// Screen fact of a session: the view controller when it is presented and not going away, nil otherwise (in-app PIP, an SDK
    /// preview window, dismissing, or a player that is not a UIViewController - SDK return type is only the protocol).
    private func onScreenViewController(_ c: any ShoplivePlayerControlling) -> UIViewController? {
        guard let vc = c as? UIViewController, vc.presentingViewController != nil, !vc.isBeingDismissed else { return nil }
        return vc
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

    private func release(_ c: (any ShoplivePlayerControlling)?) {
        guard let c = c else { return }
        (c as? BridgedPlayerViewController)?.onDismissed = nil
        c.delegate = DetachedPlayerDelegate.shared
        if c === controller { liveDelegate = nil }
    }

    /// Engine detach (X-01): the session stays; requests are answered by DetachedPlayerDelegate.
    func onEngineDetached() {
        // TODO(SDP-VERIFY): 요확인 - 엔진 재attach 후 이전 엔진 세션 제어 불가(새 핸들러가 VC를 모름) · 근거 DRAFT-flutter-sdk-302-ios/U-04 · 자동 통과 금지(실측)
        (controller as? BridgedPlayerViewController)?.onDismissed = nil
        controller?.delegate = DetachedPlayerDelegate.shared
        controller = nil
        liveDelegate = nil
        intentGeneration += 1
        let waiting = pendingPreviews
        pendingPreviews.removeAll()
        waiting.forEach { $0.discard() } // no reply - there is no Dart side left (as CampaignListCalls.cancelAll)
        savedConfiguration = nil
        savedType = PlayerMapper.defaultType
        savedResizeMode = nil
        savedOverlayUI = nil
    }

    /// Merge base = what the next start uses: saved -> SDK default. Never the controller's own configuration - a preview preset or
    /// SDK-changed values would otherwise become the saved settings of the next start (SMV-1899 D12).
    private func currentConfiguration() -> ShoplivePlayerConfiguration {
        savedConfiguration ?? ShoplivePlayerConfiguration()
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

/// Delegate of a startPreview player until its main hop (SMV-2021 design b-1). Single implementation, owned by
/// PlayerMethodHandler (CG-1.1, CG-2.1). Keeps the SDK rejection notice (9520 / 9000) as the call's result - it is not also
/// emitted as an event (CG-4.2) - and holds every other event and request in arrival order until the verdict.
private final class PreviewProbe: ShoplivePlayerDelegate {
    private enum Held {
        case event(any ShoplivePlayerControlling, ShoplivePlayerEvent)
        case request(any ShoplivePlayerControlling, ShoplivePlayerRequest)
    }

    let player: any ShoplivePlayerControlling
    /// The bridge the player gets when adopted; nil once the engine emitters are gone.
    let session: PlayerDelegateBridge?
    /// Intent generation of the latest call waiting on this probe (a joining call refreshes it - the later call wins).
    var intent: Int
    /// Started before the probe was attached - its earlier events were not seen (settlePreview supplements the state).
    let startedBeforeProbe: Bool
    var replies: [(BridgeOutcome) -> Void]
    private(set) var rejection: ShopliveError?
    private var held: [Held] = []

    init(player: any ShoplivePlayerControlling, session: PlayerDelegateBridge?, intent: Int, startedBeforeProbe: Bool,
         reply: @escaping (BridgeOutcome) -> Void) {
        self.player = player
        self.session = session
        self.intent = intent
        self.startedBeforeProbe = startedBeforeProbe
        replies = [reply]
    }

    func player(_ player: any ShoplivePlayerControlling, didReceive event: ShoplivePlayerEvent) {
        if rejection == nil, case .error(let e) = event, Self.isRejection(e.code) {
            rejection = e
            return
        }
        held.append(.event(player, event))
    }

    func player(_ player: any ShoplivePlayerControlling, didRequest request: ShoplivePlayerRequest) {
        held.append(.request(player, request))
    }

    /// Codes with which the SDK refuses to start a preview and reports it on the next main run loop (iOS 3.0.6 PreviewLauncher).
    private static func isRejection(_ code: ShopliveErrorCode) -> Bool {
        switch code {
        case .previewIgnoredWhileViewing, .notInitializedAccessKey: return true
        default: return false
        }
    }

    /// Not adopted: later callbacks go to DetachedPlayerDelegate; held requests get the fallback once, held events are dropped.
    func discard() {
        player.delegate = DetachedPlayerDelegate.shared
        let pending = held
        held.removeAll()
        for case .request(_, let request) in pending { DetachedPlayerDelegate.respondFallback(request) }
    }

    /// Adopted: hands the held callbacks to the session bridge in arrival order (fallback for requests without one).
    func replayHeld(into session: PlayerDelegateBridge?) {
        let pending = held
        held.removeAll()
        let target: ShoplivePlayerDelegate = session ?? DetachedPlayerDelegate.shared
        for item in pending {
            switch item {
            case .event(let sender, let event): target.player(sender, didReceive: event)
            case .request(let sender, let request): target.player(sender, didRequest: request)
            }
        }
    }

    /// Exactly one reply per joined call.
    func finish(_ outcome: BridgeOutcome) {
        let pending = replies
        replies.removeAll()
        pending.forEach { $0(outcome) }
    }
}
