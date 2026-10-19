package cloud.shoplive.shoplive_core

import cloud.shoplive.core.publicsurface.ShopliveConfiguration
import cloud.shoplive.core.publicsurface.ShopliveConversionData
import cloud.shoplive.core.publicsurface.ShopliveError
import cloud.shoplive.core.publicsurface.ShopliveErrorCode
import cloud.shoplive.core.publicsurface.ShopliveUser
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class ShopliveCorePluginTest {

    private class RecordingResult : MethodChannel.Result {
        val calls = mutableListOf<String>()
        var value: Any? = null
        var errorCode: String? = null
        var errorMessage: String? = null
        var errorDetails: Any? = null
        override fun success(result: Any?) { calls += "success"; value = result }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            calls += "error"; this.errorCode = errorCode; this.errorMessage = errorMessage; this.errorDetails = errorDetails
        }
        override fun notImplemented() { calls += "notImplemented" }
    }

    private class FakeSdk(var failWith: Throwable? = null) : CoreSdk {
        val calls = mutableListOf<Pair<String, Any?>>()
        private fun record(name: String, arg: Any?) { calls += name to arg; failWith?.let { throw it } }
        override fun initialize(configuration: ShopliveConfiguration) = record("initialize", configuration)
        override fun setUser(user: ShopliveUser) = record("setUser", user)
        override fun setStreamToken(token: String) = record("setStreamToken", token)
        override fun logout() = record("logout", null)
        override fun sendConversionEvent(data: ShopliveConversionData) = record("sendConversionEvent", data)
        override fun getSdkVersion(): String { record("getSdkVersion", null); return "3.0.3" }
    }

    private fun call(sdk: CoreSdk, method: String, args: Any? = null): RecordingResult {
        val r = RecordingResult()
        ShopliveCorePlugin(sdk).onMethodCall(MethodCall(method, args), r)
        return r
    }

    @Test // case: U-07
    fun channelName_matchesContract() {
        assertEquals("shoplive_core", ShopliveCorePlugin.METHOD_CHANNEL)
    }

    @Test // case: U-01, N-01
    fun eachContractMethod_callsSdkOnce_andSucceedsOnce() {
        val cases = listOf(
            "initialize" to mapOf("accessKey" to "ak"),
            "setUser" to mapOf("type" to "guest"),
            "setStreamToken" to mapOf("token" to "t"),
            "logout" to null,
            "sendConversionEvent" to emptyMap<String, Any>(),
        )
        for ((method, args) in cases) {
            val sdk = FakeSdk()
            val r = call(sdk, method, args)
            assertEquals(method, listOf("success"), r.calls)
            assertNull(method, r.value)
            assertEquals(method, listOf(method), sdk.calls.map { it.first })
        }
    }

    @Test // case: N-01
    fun getSdkVersion_returnsString() {
        val r = call(FakeSdk(), "getSdkVersion")
        assertEquals(listOf("success"), r.calls)
        assertEquals("3.0.3", r.value)
    }

    @Test // case: F-05
    fun unknownMethod_notImplementedOnce() {
        val sdk = FakeSdk()
        val r = call(sdk, "start")
        assertEquals(listOf("notImplemented"), r.calls)
        assertEquals(0, sdk.calls.size)
    }

    @Test // case: F-04
    fun invalidArgument_errorsOnce_andDoesNotCallSdk() {
        val sdk = FakeSdk()
        val r = call(sdk, "setUser", mapOf("type" to "profile"))
        assertEquals(listOf("error"), r.calls)
        assertEquals("INVALID_ARGUMENT", r.errorCode)
        assertEquals("id", (r.errorDetails as Map<*, *>)["key"])
        assertEquals(0, sdk.calls.size)
    }

    @Test // case: F-04
    fun nonMapArguments_isInvalidArgument() {
        val r = call(FakeSdk(), "initialize", listOf("x"))
        assertEquals(listOf("error"), r.calls)
        assertEquals("INVALID_ARGUMENT", r.errorCode)
    }

    @Test // case: F-03
    fun sdkRuntimeException_isSdkError() {
        val r = call(FakeSdk(IllegalStateException("boom")), "logout")
        assertEquals(listOf("error"), r.calls)
        assertEquals("SDK_ERROR", r.errorCode)
        assertEquals(IllegalStateException::class.java.name, (r.errorDetails as Map<*, *>)["exception"])
    }

    @Test // case: F-03
    fun sdkShopliveError_detailsCarryCode() {
        val err = ShopliveError(ShopliveErrorCode.NOT_INITIALIZED_ACCESS_KEY, 1001, "no key", null, false)
        val r = call(FakeSdk(err), "setUser", mapOf("type" to "guest"))
        assertEquals("SDK_ERROR", r.errorCode)
        val d = r.errorDetails as Map<*, *>
        assertEquals("NOT_INITIALIZED_ACCESS_KEY", d["code"])
        assertEquals(1001, d["rawCode"])
        assertEquals(false, d["recoverable"])
    }

    @Test // case: F-03
    fun sdkLinkageError_isSdkError() {
        val r = call(FakeSdk(UnsatisfiedLinkError("no lib")), "logout")
        assertEquals(listOf("error"), r.calls)
        assertEquals("SDK_ERROR", r.errorCode)
    }

    @Test(expected = OutOfMemoryError::class) // case: F-03
    fun vmError_isNotSwallowed() {
        call(FakeSdk(OutOfMemoryError("oom")), "logout")
    }

    @Test // case: R-03
    fun detachedPlugin_withoutSdk_isSdkError() {
        val r = RecordingResult()
        ShopliveCorePlugin().onMethodCall(MethodCall("logout", null), r)
        assertEquals(listOf("error"), r.calls)
        assertEquals("SDK_ERROR", r.errorCode)
        assertEquals("plugin detached", r.errorMessage)
    }

    @Test // case: F-03
    fun sdkIllegalArgument_duringSdkCall_isSdkError_withoutMessageLeak() {
        // SDK 호출 중 IAE는 SDK_ERROR(생성자·copy 단계만 INVALID_ARGUMENT — CoreContractTest/SafeCallTest.constructing)
        val r = call(FakeSdk(IllegalArgumentException("secret-ak")), "logout")
        assertEquals("SDK_ERROR", r.errorCode)
        assertEquals(false, r.errorMessage!!.contains("secret"))
    }

    @Test // case: F-03
    fun sdkErrorMessage_doesNotLeakExceptionMessage() {
        val r = call(FakeSdk(IllegalStateException("secret-ak")), "logout")
        assertEquals(false, r.errorMessage!!.contains("secret"))
    }

    @Test // case: N-01
    fun setUser_passesMappedUser() {
        val sdk = FakeSdk()
        call(sdk, "setUser", mapOf("type" to "guest"))
        assertSame(ShopliveUser.Guest, sdk.calls.single().second)
    }
}
