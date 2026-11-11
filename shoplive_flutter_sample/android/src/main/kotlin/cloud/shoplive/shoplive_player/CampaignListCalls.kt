package cloud.shoplive.shoplive_player

import cloud.shoplive.core.publicsurface.ShopliveError
import cloud.shoplive.player.ShopliveCampaignListCallback
import cloud.shoplive.player.ShopliveCampaignListRequest
import cloud.shoplive.player.ShopliveCampaignListResponse
import cloud.shoplive.player.ShoplivePlayerAPI
import cloud.shoplive.player.ShopliveCancellable
import io.flutter.plugin.common.MethodChannel

/**
 * 진행 중인 getCampaigns 요청(SMV-1899 D10). requestId(Dart 발급) → SDK 취소 핸들 + MethodChannel 회신.
 * 회신은 정확히 1번: 성공·실패(SDK 콜백), 취소(Dart cancelGetCampaigns) 중 먼저 [take]한 쪽만 보낸다 — 늦은 콜백은 버린다.
 * 모든 연산은 메인 스레드다(MethodCall, SDK 콜백은 Dispatchers.Main — 3.0.6 ShoplivePlayerAPI.kt:117).
 * 대기 상한은 두지 않는다(사용자 결정 T-a): 무응답 상한은 SDK HTTP 설정(callTimeout 30초)을 따른다.
 * [fetch]: SDK 호출 경계 — JVM 테스트가 콜백을 붙잡는 대역을 넣는다(portFactory와 같은 관례).
 */
internal class CampaignListCalls(
    private val fetch: (ShopliveCampaignListRequest, ShopliveCampaignListCallback) -> ShopliveCancellable = ShoplivePlayerAPI::getCampaigns,
) {
    private class Call(val reply: MethodChannel.Result) {
        var cancellable: ShopliveCancellable? = null
    }

    private val calls = HashMap<String, Call>()

    /**
     * 등록 전(인자 오류·중복 id)과 SDK 호출 자체가 던질 때만 예외를 던진다 — 그때는 등록을 되돌려 호출자가 1번 회신한다.
     * 정상이면 회신은 이 객체가 맡는다.
     */
    fun begin(args: Args, reply: MethodChannel.Result) {
        val id = args.requireString(PlayerContract.REQUEST_ID)
        val request = PlayerMapper.toCampaignListRequest(args.optArgs(PlayerContract.REQUEST))
        if (calls.containsKey(id)) throw BridgeArgumentException(PlayerContract.REQUEST_ID, "id not in flight", "duplicate")
        val call = Call(reply)
        calls[id] = call
        try {
            call.cancellable = fetch(request, object : ShopliveCampaignListCallback {
                override fun onSuccess(response: ShopliveCampaignListResponse) = complete(id) { it.success(PlayerMapper.campaignListToWire(response)) }
                override fun onFailure(error: ShopliveError) = complete(id) {
                    it.error(BridgeErrorCode.SDK_ERROR, error.message, Bridge.errorToWire(error))
                }
            })
        } catch (t: Throwable) {
            calls.remove(id)
            throw t
        }
    }

    /** @return 진행 중이던 요청을 취소했으면 true(SDK 취소 + CANCELLED 회신 1번), 없거나 이미 끝났으면 false. */
    fun cancel(args: Args): Boolean {
        val call = calls.remove(args.requireString(PlayerContract.REQUEST_ID)) ?: return false
        call.cancellable?.cancel() // 메인에서 취소하면 이후 SDK 콜백은 오지 않는다(ShoplivePlayerAPI.kt:60-64)
        call.reply.error(PlayerContract.CANCELLED, "getCampaigns cancelled", null)
        return true
    }

    /** 엔진 detach: SDK 요청을 모두 취소한다. 받을 Dart가 없으므로 회신하지 않는다. */
    fun cancelAll() {
        val all = calls.values.toList()
        calls.clear()
        all.forEach { it.cancellable?.cancel() }
    }

    private fun complete(id: String, send: (MethodChannel.Result) -> Unit) {
        val call = calls.remove(id) ?: return // 취소·detach 뒤 도착 — 버린다
        Bridge.guardCallback(TAG, "getCampaigns reply") { send(call.reply) }
    }

    private companion object {
        const val TAG = "ShopliveCampaignList"
    }
}
