import Flutter
import Foundation
import ShopliveCore
import ShoplivePlayerSDK

/// In-flight getCampaigns calls (SMV-1899 D10): requestId (issued by Dart) -> SDK cancel handle + FlutterResult.
/// Exactly one reply: success / failure (SDK completion) or cancel (Dart cancelGetCampaigns), whichever takes the entry first;
/// a later completion is dropped. Main thread only: MethodChannel calls, and the completion is moved to main if it is not
/// there already (the SDK documents main, but the normal path's delivery belongs to the core client - not assumed).
/// No wait limit here (user decision T-a): the no-response bound is the SDK's HTTP setting.
final class CampaignListCalls {
    static let cancelledCode = "CANCELLED"

    private final class Call {
        let reply: FlutterResult
        var cancellable: ShopliveCancellable?
        init(reply: @escaping FlutterResult) { self.reply = reply }
    }

    private let scheduler: MainScheduler
    private var calls: [String: Call] = [:]

    init(scheduler: MainScheduler) { self.scheduler = scheduler }

    /// Throws only before registering (argument errors, duplicate id) - the caller then replies once. Otherwise this object replies.
    func begin(_ args: Args, reply: @escaping FlutterResult) throws {
        let id = try args.requireString("requestId")
        let request = try PlayerMapper.toCampaignListRequest(try args.optArgs("request"))
        guard calls[id] == nil else { throw BridgeArgumentError(key: "requestId", expected: "id not in flight", actual: "duplicate") }
        let call = Call(reply: reply)
        calls[id] = call
        call.cancellable = ShoplivePlayerAPI.getCampaigns(request) { [weak self] result in
            guard let self = self else { return }
            if self.scheduler.isMainThread() {
                self.complete(id, result)
            } else {
                self.scheduler.post { [weak self] in self?.complete(id, result) }
            }
        }
    }

    /// - Returns: true if a call in flight was cancelled (SDK cancel + one CANCELLED reply), false if none or already finished.
    func cancel(_ args: Args) throws -> Bool {
        guard let call = calls.removeValue(forKey: try args.requireString("requestId")) else { return false }
        call.cancellable?.cancel() // the SDK then never calls the completion (ShoplivePlayerAPI.swift:72-78)
        call.reply(FlutterError(code: Self.cancelledCode, message: "getCampaigns cancelled", details: nil))
        return true
    }

    /// Engine detach: cancel every SDK request. No reply - there is no Dart side left to receive it.
    func cancelAll() {
        let all = calls.values
        calls.removeAll()
        all.forEach { $0.cancellable?.cancel() }
    }

    private func complete(_ id: String, _ result: Result<ShopliveCampaignListResponse, ShopliveError>) {
        guard let call = calls.removeValue(forKey: id) else { return } // cancelled or detached - drop
        switch result {
        case .success(let response):
            call.reply(PlayerMapper.campaignListToWire(response))
        case .failure(let error):
            call.reply(FlutterError(code: BridgeErrorCode.sdkError, message: error.message, details: ShopliveErrorWire.toWire(error)))
        }
    }
}
