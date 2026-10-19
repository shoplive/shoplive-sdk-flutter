import Foundation
import ShopliveStreamerSDK

/// Shoplive iOS streamer 3.0.3 -> wire (design section 2.5/2.6). Pure functions.
enum StreamerMapper {
    static let broadcastState: [String: ShopliveBroadcastState] = [
        "idle": .idle, "preview": .preview, "connecting": .connecting, "live": .live, "reconnecting": .reconnecting, "ended": .ended,
    ]

    /// D-1: the iOS SDK has no rehearsal flag, so `isRehearsal` is omitted (Dart: bool?).
    static func eventToWire(_ event: ShopliveStreamerEvent) -> [String: Any] {
        switch event {
        case .stateChanged(let state):
            return ["type": "stateChanged", "state": wireOf(state, broadcastState)]
        case .error(let error):
            return ["type": "error", "error": ShopliveErrorWire.toWire(error)]
        @unknown default:
            return ["type": wireUnknown, "rawType": "unknown"]
        }
    }
}
