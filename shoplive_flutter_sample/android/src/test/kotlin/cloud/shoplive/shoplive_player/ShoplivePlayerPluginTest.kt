package cloud.shoplive.shoplive_player

import io.flutter.plugin.common.MethodCall
import org.junit.Assert.assertEquals
import org.junit.Test

class ShoplivePlayerPluginTest {

    @Test // case: U-07
    fun methodChannelName_matchesContract() {
        assertEquals("shoplive_player", ShoplivePlayerPlugin.METHOD_CHANNEL)
    }

    @Test // case: R-03
    fun beforeAttach_callCompletesOnce_withSdkErrorPluginDetached() {
        val result = RecordingResult()
        ShoplivePlayerPlugin().onMethodCall(MethodCall("getState", null), result)
        assertEquals(listOf("error"), result.calls)
        assertEquals(BridgeErrorCode.SDK_ERROR, result.errorCode)
        assertEquals("plugin detached", result.errorMessage)
    }

    @Test // case: G-7 (R6-A5, SMV-1899) — 나중에 회신하는 getCampaigns도 붙기 전·인자 오류는 1회로 즉시 끝난다
    fun beforeAttach_campaignCalls_completeOnce() {
        for (method in listOf("getCampaigns", "cancelGetCampaigns")) {
            val result = RecordingResult()
            ShoplivePlayerPlugin().onMethodCall(MethodCall(method, mapOf("requestId" to "1")), result)
            assertEquals(method, listOf("error"), result.calls)
            assertEquals(BridgeErrorCode.SDK_ERROR, result.errorCode)
        }
    }
}
