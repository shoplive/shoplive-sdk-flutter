import Foundation
import UIKit
import ShoplivePlayerSDK

/// Dart wire map <-> Shoplive iOS player 3.0.3 types (design section 2.2-2.5). Pure functions.
enum PlayerMapper {
    // MARK: wire tables (Dart enum.name, design section 2.4)
    static let playerState: [String: ShoplivePlayerState] = [
        "idle": .idle, "loading": .loading, "playing": .playing, "paused": .paused, "inAppPip": .inAppPIP, "closed": .closed,
    ]
    static let campaignStatus: [String: ShopliveCampaignStatus] = ["ready": .ready, "live": .live, "ended": .ended]
    static let connectionState: [String: ShopliveConnectionState] = [
        "connecting": .connecting, "connected": .connected, "reconnecting": .reconnecting, "disconnected": .disconnected,
    ]
    static let resizeMode: [String: ShopliveResizeMode] = ["fill": .fill, "fit": .fit]
    static let overlayUI: [String: ShopliveOverlayUIMode] = ["builtIn": .builtIn, "hidden": .hidden]
    static let presentationStyle: [String: ShoplivePlayerPresentationStyle] = ["fullscreen": .fullScreen, "pip": .pip]
    static let pipPosition: [String: ShoplivePipPosition] = [
        "topLeft": .topLeft, "topCenter": .topCenter, "topRight": .topRight,
        "middleLeft": .middleLeft, "middleCenter": .middleCenter, "middleRight": .middleRight,
        "bottomLeft": .bottomLeft, "bottomCenter": .bottomCenter, "bottomRight": .bottomRight,
    ]
    static let navigationAction: [String: ShopliveNavigationAction] = ["pip": .pip, "keep": .keep, "close": .close]
    static let resultStatus: [String: ShopliveResultStatus] = ["show": .show, "hide": .hide, "keep": .keep]
    static let alertType: [String: ShopliveResultAlertType] = ["alert": .alert, "toast": .toast]
    /// Contract values validated but without an iOS counterpart (D-2 type is mapped to presets, D-3 aspectRatio ignored).
    static let playerType: [String: String] = ["live": "live", "preview": "preview"]
    static let pipRatio: [String: String] = [
        "ratio1x1": "ratio1x1", "ratio1x2": "ratio1x2", "ratio2x3": "ratio2x3", "ratio3x4": "ratio3x4", "ratio9x16": "ratio9x16",
    ]
    static let defaultType = "live"

    // MARK: input

    static func toPlayOptions(_ args: Args?) throws -> ShoplivePlayOptions {
        var options = ShoplivePlayOptions()
        guard let args = args else { return options }
        if args.has("referrer") { options.referrer = try args.optString("referrer") }
        if let keep = try nonNullBool(args, "keepWindowStateOnPlayExecuted") { options.keepWindowStateOnPlayExecuted = keep }
        if let style = try nonNullEnum(args, "presentationStyle", presentationStyle) { options.presentationStyle = style }
        return options
    }

    /// Merges a partial configuration over `current` (CFG-01). D-2/IM-m1: a `type` different from the current one selects
    /// the `.preview`/`.default` preset as the new base; the same type keeps the current fields (Android parity).
    static func mergeConfiguration(_ current: ShoplivePlayerConfiguration, currentType: String,
                                   partial: Args) throws -> (ShoplivePlayerConfiguration, String) {
        var config = current
        var type = currentType
        if let newType = try nonNullEnum(partial, "type", playerType), newType != currentType {
            // TODO(SDP-VERIFY): 요확인 - .preview/.default 프리셋의 실제 값(swiftinterface에 내용 없음) · 근거 DRAFT-flutter-sdk-302-ios/D-2 · 자동 통과 금지(실측)
            config = newType == "preview" ? .preview : .default
            // SDK 3.0.3 adds ShoplivePlayerConfiguration.type; set it explicitly whatever the preset holds (SMV-1749).
            config.type = newType == "preview" ? .preview : .live
            type = newType
        }
        if let pip = try partial.optArgs("pip") {
            if let v = try nonNullBool(pip, "isInAppPipEnabled") { config.pip.isInAppPipEnabled = v }
            if let v = try nonNullBool(pip, "isOSPipEnabled") { config.pip.isOSPipEnabled = v }
            if let v = try nonNullEnum(pip, "defaultPosition", pipPosition) { config.pip.defaultPosition = v }
            if let v = try nonNullDouble(pip, "scale") { config.pip.scale = CGFloat(v) }
            // SDK 3.0.3. Missing = keep the SDK value, key+null or non-Bool = INVALID_ARGUMENT (Android parity).
            // SDK default is true (measured on iOS 18.4 simulator, SMV-1749).
            if let v = try nonNullBool(pip, "isDragOutToCloseEnabled") { config.pip.isDragOutToCloseEnabled = v }
            if try nonNullEnum(pip, "aspectRatio", pipRatio) != nil {
                bridgeLog("ShoplivePlayer", "configuration.pip.aspectRatio is not supported by the iOS SDK and is ignored")
            }
            if let padding = try pip.optArgs("padding") {
                var insets = config.pip.padding
                if let v = try nonNullInt(padding, "left") { insets.left = CGFloat(v) }
                if let v = try nonNullInt(padding, "top") { insets.top = CGFloat(v) }
                if let v = try nonNullInt(padding, "right") { insets.right = CGFloat(v) }
                if let v = try nonNullInt(padding, "bottom") { insets.bottom = CGFloat(v) }
                config.pip.padding = insets
            } else if pip.has("padding") {
                throw BridgeArgumentError(key: "padding", expected: "non-null value", actual: "null")
            }
        }
        if let sound = try partial.optArgs("sound") {
            if let v = try nonNullBool(sound, "muteOnStart") { config.sound.muteOnStart = v }
            if let v = try nonNullBool(sound, "mixWithOthers") { config.sound.mixWithOthers = v }
        }
        if let appearance = try partial.optArgs("appearance") {
            if let v = try nonNullInt(appearance, "indicatorColor") {
                // ARGB as unsigned 32-bit (Dart 0xFF00FF00 = 4278255360); signed input accepted too (same as Android).
                guard v >= Int(Int32.min), v <= Int(UInt32.max) else {
                    throw BridgeArgumentError(key: "indicatorColor", expected: "ARGB 0..0xFFFFFFFF", actual: "out of range")
                }
                config.appearance.indicatorColor = color(argb: v)
            }
        }
        if let navigation = try partial.optArgs("navigation") {
            if let v = try nonNullEnum(navigation, "actionOnNavigation", navigationAction) { config.navigation.actionOnNavigation = v }
            if navigation.has("shareScheme") { config.navigation.shareScheme = try navigation.optString("shareScheme") }
        }
        if let overlay = try partial.optArgs("overlay") {
            if let v = try nonNullEnum(overlay, "ui", overlayUI) { config.overlay.ui = v }
        }
        if let params = try partial.optStringStringMap("customParameters") {
            config.customParameters = params
        } else if partial.has("customParameters") {
            throw BridgeArgumentError(key: "customParameters", expected: "non-null value", actual: "null")
        }
        if try partial.optArgs("android") != nil {
            // D-3: Android-only options are ignored on iOS.
        }
        return (config, type)
    }

    static func toCouponResult(couponId: String, _ a: Args) throws -> ShopliveCouponResult {
        ShopliveCouponResult(couponId: couponId, success: try a.requireBool("success"), message: try a.optString("message"),
                             status: try a.requireWireEnum("status", resultStatus), alertType: try alert(a))
    }

    static func toCustomActionResult(id: String, _ a: Args) throws -> ShopliveCustomActionResult {
        ShopliveCustomActionResult(id: id, success: try a.requireBool("success"), message: try a.optString("message"),
                                   status: try a.requireWireEnum("status", resultStatus), alertType: try alert(a))
    }

    /// The contract makes alertType optional (D-11): missing -> toast (3.0.2 behavior kept; SDK 3.0.3 init default is .alert).
    private static func alert(_ a: Args) throws -> ShopliveResultAlertType {
        // TODO(SDP-VERIFY): 요확인 — alertType 생략 시 기본값(현재 Android=null 웹 기본, iOS=.toast) 3.0.3 네이티브 기본 ALERT로 맞출지 사용자 결정 대기 · 근거 SMV-1749
        try a.optWireEnum("alertType", alertType) ?? .toast
    }

    // MARK: output

    static func configurationToWire(_ c: ShoplivePlayerConfiguration, type: String) -> [String: Any] {
        [
            "type": type,
            "pip": [
                "isInAppPipEnabled": c.pip.isInAppPipEnabled,
                "isOSPipEnabled": c.pip.isOSPipEnabled,
                "defaultPosition": wireOf(c.pip.defaultPosition, pipPosition),
                "scale": Double(c.pip.scale),
                "isDragOutToCloseEnabled": c.pip.isDragOutToCloseEnabled,
                "padding": ["left": Int(c.pip.padding.left), "top": Int(c.pip.padding.top),
                            "right": Int(c.pip.padding.right), "bottom": Int(c.pip.padding.bottom)],
            ] as [String: Any],
            "sound": ["muteOnStart": c.sound.muteOnStart, "mixWithOthers": c.sound.mixWithOthers],
            "appearance": ["indicatorColor": argb(c.appearance.indicatorColor)],
            "navigation": ["actionOnNavigation": wireOf(c.navigation.actionOnNavigation, navigationAction),
                           "shareScheme": c.navigation.shareScheme as Any? ?? NSNull()] as [String: Any],
            "overlay": ["ui": wireOf(c.overlay.ui, overlayUI)],
            "customParameters": c.customParameters,
        ]
    }

    static func campaignToWire(_ info: ShopliveCampaignInfo?) -> Any {
        guard let info = info else { return NSNull() }
        return ["campaignKey": info.campaignKey, "title": info.title as Any? ?? NSNull(),
                "status": info.status.map { wireOf($0, campaignStatus) } as Any? ?? NSNull()] as [String: Any]
    }

    static func eventToWire(_ event: ShoplivePlayerEvent) -> [String: Any] {
        switch event {
        case .stateChanged(let state):
            return ["type": "stateChanged", "state": wireOf(state, playerState)]
        case .campaignStatusChanged(let status):
            return ["type": "campaignStatusChanged", "status": wireOf(status, campaignStatus)]
        case .campaignInfoReceived(let info):
            var wire = campaignToWire(info) as? [String: Any] ?? [:]
            wire["type"] = "campaignInfoReceived"
            return wire
        case .playback(let playback):
            return playbackToWire(playback)
        case .connectionStateChanged(let state):
            return ["type": "connectionStateChanged", "state": wireOf(state, connectionState)]
        case .userNameUpdateRequested(let payload):
            return ["type": "userNameUpdateRequested", "payload": ValueNormalizer.normalize(payload)]
        case .analytics(let info):
            return analyticsToWire(info)
        case .error(let error):
            return ["type": "error", "error": ShopliveErrorWire.toWire(error)]
        case .webCommand(let name, let payload):
            // Contract payload is a non-null map: nil -> {} (I-E-03).
            return ["type": "webCommandReceived", "name": name, "payload": ValueNormalizer.normalize(payload ?? [:])]
        @unknown default:
            return ["type": wireUnknown, "rawType": "unknown"]
        }
    }

    private static func playbackToWire(_ p: PlaybackEvent) -> [String: Any] {
        let kind: String
        switch p.event {
        case .request: kind = "requested"
        case .started: kind = "started"
        case .audioLoaded: kind = "audioLoaded"
        case .rendering: kind = "rendering"
        case .buffering: kind = "buffering"
        case .rebufferingStarted: kind = "rebufferingStarted"
        case .rebufferingEnded: kind = "rebufferingEnded"
        case .ended: kind = "ended"
        case .error: kind = "failed"
        @unknown default: kind = wireUnknown
        }
        var wire: [String: Any] = ["type": "playback", "event": kind, "timestampMs": p.timestamp.map { Int64($0) } as Any? ?? NSNull()]
        if p.event == .error {
            // TODO(SDP-VERIFY): 요확인 - PlaybackEvent.datas 의 code/message 키 이름(미공개) — 확인 전 null · 근거 DRAFT-flutter-sdk-302-ios/D-6 · 자동 통과 금지(실측)
            wire["code"] = NSNull()
            wire["message"] = NSNull()
        }
        return wire
    }

    private static func analyticsToWire(_ i: ShopliveAnalyticsInfo) -> [String: Any] {
        [
            "type": "analytics",
            "campaignKey": i.campaignKey,
            "isPlaying": i.isPlaying,
            "isMuted": i.isMuted,
            "durationMs": i.durationMs,
            "campaign": i.campaign.map { ["title": $0.title as Any? ?? NSNull(), "status": wireOf($0.status, campaignStatus)] as [String: Any] } as Any? ?? NSNull(),
            "brand": i.brand.map { ["name": $0.name as Any? ?? NSNull(), "identifier": $0.identifier as Any? ?? NSNull(),
                                    "imageUrl": $0.imageUrl as Any? ?? NSNull()] as [String: Any] } as Any? ?? NSNull(),
        ]
    }

    static func navigationToWire(_ url: URL) -> [String: Any] { ["type": "navigation", "url": url.absoluteString] }

    static func couponToWire(requestId: String, couponId: String) -> [String: Any] {
        ["type": "coupon", "requestId": requestId, "couponId": couponId]
    }

    static func customWebActionToWire(requestId: String, id: String, actionType: String, payload: Any?) -> [String: Any] {
        ["type": "customWebAction", "requestId": requestId, "id": id, "actionType": actionType, "payload": ValueNormalizer.normalize(payload)]
    }

    // MARK: helpers

    static func color(argb: Int) -> UIColor {
        let value = UInt32(truncatingIfNeeded: argb)
        return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: CGFloat((value >> 24) & 0xFF) / 255)
    }

    static func argb(_ color: UIColor) -> Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return Int(UInt32(0xFF00_0000)) }
        func byte(_ c: CGFloat) -> UInt32 { UInt32(max(0, min(255, (c * 255).rounded()))) }
        return Int(byte(a) << 24 | byte(r) << 16 | byte(g) << 8 | byte(b)) // unsigned 32-bit ARGB
    }

    private static func nonNullBool(_ a: Args, _ key: String) throws -> Bool? {
        if a.has(key), a.isNull(key) { throw BridgeArgumentError(key: key, expected: "non-null value", actual: "null") }
        return try a.optBool(key)
    }

    private static func nonNullInt(_ a: Args, _ key: String) throws -> Int? {
        if a.has(key), a.isNull(key) { throw BridgeArgumentError(key: key, expected: "non-null value", actual: "null") }
        return try a.optInt(key)
    }

    private static func nonNullDouble(_ a: Args, _ key: String) throws -> Double? {
        if a.has(key), a.isNull(key) { throw BridgeArgumentError(key: key, expected: "non-null value", actual: "null") }
        return try a.optDouble(key)
    }

    private static func nonNullEnum<E>(_ a: Args, _ key: String, _ table: [String: E]) throws -> E? {
        try a.optWireEnum(key, table)
    }
}
