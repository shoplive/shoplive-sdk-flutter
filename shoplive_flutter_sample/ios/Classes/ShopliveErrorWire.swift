// ShopliveError -> channel error payload (design D-5). Keep in sync: identical copies in shoplive_player and shoplive_streamer.
import Foundation
import ShopliveCore

enum ShopliveErrorWire {
    /// {code, message, rawCode, recoverable}. code uses the Android UPPER_SNAKE names (opaque string on the Dart side).
    /// rawCode: SDK 3.0.3 `ShopliveError.rawCode` for every code (Android parity); unknown(n) keeps n as in 3.0.2.
    static func toWire(_ error: ShopliveError) -> [String: Any] {
        var rawCode = error.rawCode
        let code: String
        switch error.code {
        case .authenticationFailed: code = "AUTHENTICATION_FAILED"
        case .guestLoginNotAllowed: code = "GUEST_LOGIN_NOT_ALLOWED"
        case .customAccountNotFound: code = "CUSTOM_ACCOUNT_NOT_FOUND"
        case .customAccountExpired: code = "CUSTOM_ACCOUNT_EXPIRED"
        case .invalidSignature: code = "INVALID_SIGNATURE"
        case .duplicateSession: code = "DUPLICATE_SESSION"
        case .expiredSession: code = "EXPIRED_SESSION"
        case .serverError: code = "SERVER_ERROR"
        case .campaignNotOnAir: code = "CAMPAIGN_NOT_ON_AIR"
        case .connectionIssue: code = "CONNECTION_ISSUE"
        case .notInitializedAccessKey: code = "NOT_INITIALIZED_ACCESS_KEY"
        case .notInitializedShareURL: code = "NOT_INITIALIZED_SHARE_URL"
        case .notInitializedShortformConfig: code = "NOT_INITIALIZED_SHORTFORM_CONFIG"
        case .noVideoForPip: code = "NO_VIDEO_FOR_PIP"
        case .noPlayableStreamUrl: code = "NO_PLAYABLE_STREAM_URL"
        case .liveNotBroadcasting: code = "LIVE_NOT_BROADCASTING"
        case .campaignNotFound: code = "CAMPAIGN_NOT_FOUND"
        case .failedEncoding: code = "FAILED_ENCODING"
        case .removedVideo: code = "REMOVED_VIDEO"
        case .unsupportedOSPipMode: code = "UNSUPPORTED_OS_PIP_MODE"
        case .unsupportedMedia: code = "UNSUPPORTED_MEDIA"
        case .failedToStartOSPip: code = "FAILED_TO_START_OS_PIP"
        case .failedNetwork: code = "FAILED_NETWORK"
        case .failedJSONParsing: code = "FAILED_JSON_PARSING"
        case .unexpectedError: code = "UNEXPECTED_ERROR"
        case .unknown(let raw):
            code = "UNKNOWN"
            rawCode = raw
        @unknown default: code = "UNKNOWN"
        }
        return ["code": code, "message": error.message, "rawCode": rawCode, "recoverable": error.isRecoverable]
    }
}
