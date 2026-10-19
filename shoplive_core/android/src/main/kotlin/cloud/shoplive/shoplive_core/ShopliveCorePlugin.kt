package cloud.shoplive.shoplive_core

import android.content.Context
import cloud.shoplive.core.publicsurface.Shoplive
import cloud.shoplive.core.publicsurface.ShopliveConfiguration
import cloud.shoplive.core.publicsurface.ShopliveConversionData
import cloud.shoplive.core.publicsurface.ShopliveUser
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Shoplive core 3.0.3 호출 경계(테스트에서 대체). */
internal interface CoreSdk {
    fun initialize(configuration: ShopliveConfiguration)
    fun setUser(user: ShopliveUser)
    fun setStreamToken(token: String)
    fun logout()
    fun sendConversionEvent(data: ShopliveConversionData)
    fun getSdkVersion(): String
}

private class ShopliveCoreSdk(private val appContext: Context) : CoreSdk {
    // TODO(SDP-VERIFY): 요확인 — initialize 반복 호출(핫 리스타트·다중 엔진)의 SDK 동작(재초기화/무시/예외) · 근거 DRAFT-flutter-sdk-302-android/F-01·pair#17 · 자동 통과 금지(실측)
    override fun initialize(configuration: ShopliveConfiguration) = Shoplive.initialize(appContext, configuration)
    override fun setUser(user: ShopliveUser) = Shoplive.setUser(user)
    override fun setStreamToken(token: String) = Shoplive.setStreamToken(token)
    override fun logout() = Shoplive.logout()
    override fun sendConversionEvent(data: ShopliveConversionData) = Shoplive.sendConversionEvent(data)

    // Shoplive.sdkVersion은 @JvmStatic @NotNull 프로퍼티(javap -v getSdkVersion → NotNull, design §2.6)
    override fun getSdkVersion(): String = Shoplive.sdkVersion
}

/**
 * shoplive_core 플러그인 — 채널 `shoplive_core`(design.md rev2 §2.4).
 * 모든 호출은 Bridge.safeCall로 result를 정확히 1회 완료한다(숨은 책임 ①).
 * 미초기화 상태 가드는 두지 않는다 — SDK에 위임(개발자 확정, F-01).
 */
class ShopliveCorePlugin internal constructor(private var sdk: CoreSdk?) :
    FlutterPlugin, MethodChannel.MethodCallHandler {

    constructor() : this(null)

    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        sdk = ShopliveCoreSdk(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        sdk = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) =
        Bridge.safeCall(TAG, call.method, result) { dispatch(call) }

    private fun dispatch(call: MethodCall): Any? {
        val sdk = this.sdk ?: throw BridgeStateException(BridgeErrorCode.SDK_ERROR, DETACHED_MESSAGE)
        val args = Args.of(call.arguments)
        return when (call.method) {
            CoreContract.INITIALIZE -> sdk.initialize(CoreMapper.toConfiguration(args)).let { null }
            CoreContract.SET_USER -> sdk.setUser(CoreMapper.toUser(args)).let { null }
            CoreContract.SET_STREAM_TOKEN -> sdk.setStreamToken(CoreMapper.toStreamToken(args)).let { null }
            CoreContract.LOGOUT -> sdk.logout().let { null }
            CoreContract.SEND_CONVERSION_EVENT -> sdk.sendConversionEvent(CoreMapper.toConversionData(args)).let { null }
            CoreContract.GET_SDK_VERSION -> sdk.getSdkVersion()
            else -> throw MethodNotImplemented
        }
    }

    companion object {
        const val METHOD_CHANNEL = "shoplive_core"
        internal const val DETACHED_MESSAGE = "plugin detached"
        private const val TAG = "ShopliveCorePlugin"
    }
}
