package cloud.shoplive.shoplive_core

import cloud.shoplive.core.publicsurface.ShopliveAttribution
import cloud.shoplive.core.publicsurface.ShopliveConfiguration
import cloud.shoplive.core.publicsurface.ShopliveConversionData
import cloud.shoplive.core.publicsurface.ShopliveConversionProduct
import cloud.shoplive.core.publicsurface.ShopliveGender
import cloud.shoplive.core.publicsurface.ShopliveUser
import android.util.Log
import io.flutter.plugin.common.MethodChannel

// =====================================================================================
// BridgeSupport 부분집합(core 판). design.md rev2 §3.3: core는 별도 BridgeSupport.kt 없이 이 파일에 둔다.
// 원본: shoplive_player/android/.../BridgeSupport.kt 의 BridgeErrorCode·예외·Bridge·Args 구간(동기화 대상).
// 공통 규칙: safeCall로 result 1회 완료 / 민감값 로깅 금지(메서드명·예외 클래스명·코드만) /
//   Bridge.constructing 안의 IllegalArgumentException → INVALID_ARGUMENT, 그 외 Exception·LinkageError → SDK_ERROR, 그 외 Error 전파.
// =====================================================================================

/** 채널 계약 에러 코드(design.md rev2 §2.2). */
internal object BridgeErrorCode {
    const val INVALID_ARGUMENT = "INVALID_ARGUMENT"
    const val NO_HOST_SCREEN = "NO_HOST_SCREEN"
    const val NOT_RUNNING = "NOT_RUNNING"
    const val SDK_ERROR = "SDK_ERROR"
}

/** Dart 인자가 계약과 맞지 않을 때. [actual]에는 값이 아니라 타입/상태만 담는다(민감값 금지). */
internal class BridgeArgumentException(
    val key: String,
    val expected: String,
    val actual: String,
) : IllegalArgumentException("$key: expected $expected, got $actual") {
    fun details(): Map<String, String> = mapOf("key" to key, "expected" to expected, "actual" to actual)
}

/** 계약상 상태 오류(NO_HOST_SCREEN·NOT_RUNNING 등). */
internal class BridgeStateException(val code: String, message: String) : IllegalStateException(message)

/** 미등록 메서드 표식 — safeCall이 result.notImplemented()로 완료한다. */
internal object MethodNotImplemented : RuntimeException() {
    private fun readResolve(): Any = MethodNotImplemented
}

internal object Bridge {

    /** MethodCall 1회 완료 래퍼. [block]의 반환값으로 success. */
    fun safeCall(tag: String, method: String, result: MethodChannel.Result, block: () -> Any?) {
        val reply: Any? = try {
            block()
        } catch (e: MethodNotImplemented) {
            result.notImplemented()
            return
        } catch (e: BridgeArgumentException) {
            Log.w(tag, "$method: ${BridgeErrorCode.INVALID_ARGUMENT} key=${e.key}")
            result.error(BridgeErrorCode.INVALID_ARGUMENT, e.message, e.details())
            return
        } catch (e: BridgeStateException) {
            Log.w(tag, "$method: ${e.code}")
            result.error(e.code, e.message, null)
            return
        } catch (t: Throwable) {
            // SDK 생성자·copy의 IllegalArgumentException은 Bridge.constructing에서만 INVALID_ARGUMENT로 바뀐다.
            // 그 밖의 SDK 호출 중 IllegalArgumentException은 SDK_ERROR(교차검증 round2 minor).
            if (!isSdkError(t)) throw t
            Log.w(tag, "$method: ${BridgeErrorCode.SDK_ERROR} ${t.javaClass.name}")
            result.error(BridgeErrorCode.SDK_ERROR, "SDK call failed: ${t.javaClass.simpleName}", sdkErrorDetails(t))
            return
        }
        result.success(reply)
    }

    /** SDK 콜백·타이머 경로 보호: 예외를 SDK 스레드로 전파하지 않는다(VM Error 제외). */
    inline fun guardCallback(tag: String, what: String, block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            if (!isSdkError(t)) throw t
            Log.e(tag, "$what failed: ${t.javaClass.name}")
        }
    }

    fun isSdkError(t: Throwable): Boolean = t is Exception || t is LinkageError

    /** core ShopliveError(Exception)는 streamer 경로에서 던져질 수 있다 — 코드만 싣는다. */
    fun sdkErrorDetails(t: Throwable): Map<String, Any?> {
        val details = mutableMapOf<String, Any?>("exception" to t.javaClass.name)
        if (t is cloud.shoplive.core.publicsurface.ShopliveError) {
            details["code"] = t.code.name
            details["rawCode"] = t.rawCode
            details["recoverable"] = t.isRecoverable
        }
        return details
    }

    /** SDK 생성자·copy 호출을 감싼다: IllegalArgumentException → INVALID_ARGUMENT(key). */
    inline fun <T> constructing(key: String, block: () -> T): T = try {
        block()
    } catch (e: BridgeArgumentException) {
        throw e
    } catch (e: IllegalArgumentException) {
        throw BridgeArgumentException(key, "value accepted by SDK", "rejected(${e.javaClass.simpleName})")
    }
}

/** StandardMessageCodec 인자 Map 리더. 키 부재와 키+null을 구분한다(design §2.2). 키는 String만 허용. */
internal class Args private constructor(private val map: Map<*, *>) {

    fun isEmpty(): Boolean = map.isEmpty()

    fun has(key: String): Boolean = map.containsKey(key)

    /** 필수 String — 누락·null·빈/공백은 거부(pair #10 결정). */
    fun requireString(key: String): String {
        val v = optString(key) ?: throw BridgeArgumentException(key, "non-blank String", stateOf(key))
        if (v.isBlank()) throw BridgeArgumentException(key, "non-blank String", "blank")
        return v
    }

    fun optString(key: String): String? = when (val v = map[key]) {
        null -> null
        is String -> v
        else -> throw BridgeArgumentException(key, "String", typeName(v))
    }

    fun requireBool(key: String): Boolean = optBool(key) ?: throw BridgeArgumentException(key, "Boolean", stateOf(key))

    fun optBool(key: String): Boolean? = when (val v = map[key]) {
        null -> null
        is Boolean -> v
        else -> throw BridgeArgumentException(key, "Boolean", typeName(v))
    }

    fun requireInt(key: String): Int = optInt(key) ?: throw BridgeArgumentException(key, "Int", stateOf(key))

    fun optInt(key: String): Int? = when (val v = map[key]) {
        null -> null
        is Int -> v
        is Long, is Short, is Byte -> {
            val l = (v as Number).toLong()
            if (l < Int.MIN_VALUE || l > Int.MAX_VALUE) throw BridgeArgumentException(key, "Int range", "out of range")
            l.toInt()
        }
        else -> throw BridgeArgumentException(key, "Int", typeName(v))
    }

    fun optLong(key: String): Long? = when (val v = map[key]) {
        null -> null
        is Int, is Long, is Short, is Byte -> (v as Number).toLong()
        else -> throw BridgeArgumentException(key, "Long", typeName(v))
    }

    fun optDouble(key: String): Double? = when (val v = map[key]) {
        null -> null
        is Number -> v.toDouble()
        else -> throw BridgeArgumentException(key, "Double", typeName(v))
    }

    fun optFloat(key: String): Float? = optDouble(key)?.toFloat()

    fun optArgs(key: String): Args? = when (val v = map[key]) {
        null -> null
        is Map<*, *> -> of(v, prefix = "$key.")
        else -> throw BridgeArgumentException(key, "Map", typeName(v))
    }

    fun requireArgs(key: String): Args = optArgs(key) ?: throw BridgeArgumentException(key, "Map", stateOf(key))

    /** 키 부재 → null, 키+null → 거부(@NotNull 파라미터용). */
    fun optNonNullStringList(key: String): List<String>? {
        if (!has(key)) return null
        val v = map[key] ?: throw BridgeArgumentException(key, "List<String>", "null")
        if (v !is List<*>) throw BridgeArgumentException(key, "List<String>", typeName(v))
        return v.mapIndexed { i, e -> e as? String ?: throw BridgeArgumentException("$key[$i]", "String", typeName(e)) }
    }

    fun optList(key: String): List<*>? = when (val v = map[key]) {
        null -> null
        is List<*> -> v
        else -> throw BridgeArgumentException(key, "List", typeName(v))
    }

    /** SDK Map<String, Any?> 인자. 최상위 키만 String 검사, 값은 변형 없이 전달. */
    fun optStringKeyMap(key: String): Map<String, Any?>? {
        val v = map[key] ?: return null
        if (v !is Map<*, *>) throw BridgeArgumentException(key, "Map<String, Any?>", typeName(v))
        // TODO(SDP-VERIFY): 요확인 — 중첩 값의 null·비String 키를 SDK가 허용하는지(애너테이션으로 판별 불가). 변형 없이 통과시킴 · 근거 DRAFT-flutter-sdk-302-android/B-04 · 자동 통과 금지(실측)
        return v.entries.associate { (k, value) ->
            (k as? String ?: throw BridgeArgumentException("$key.<key>", "String", typeName(k))) to value
        }
    }

    /** Map<String, String>(customParameters 등). */
    fun optStringStringMap(key: String): Map<String, String>? {
        val m = optStringKeyMap(key) ?: return null
        return m.mapValues { (k, v) -> v as? String ?: throw BridgeArgumentException("$key.$k", "String", typeName(v)) }
    }

    /** wire 값(Dart camelCase) → SDK enum. 키 부재 → null, 키+null·미지값 → 거부. 거부 시 값은 싣지 않는다. */
    fun <E> optWireEnum(key: String, table: Map<String, E>): E? {
        if (!has(key)) return null
        return table[map[key]] ?: throw BridgeArgumentException(key, "one of ${table.keys}", "unknown ${typeName(map[key])}")
    }

    fun <E> requireWireEnum(key: String, table: Map<String, E>): E =
        optWireEnum(key, table) ?: throw BridgeArgumentException(key, "one of ${table.keys}", "missing")

    private fun stateOf(key: String): String = if (!has(key)) "missing" else typeName(map[key])

    companion object {
        const val ROOT_KEY = "<arguments>"

        fun of(arguments: Any?): Args = when (arguments) {
            null -> Args(emptyMap<String, Any?>())
            is Map<*, *> -> of(arguments, prefix = "")
            else -> throw BridgeArgumentException(ROOT_KEY, "Map", typeName(arguments))
        }

        fun of(map: Map<*, *>, prefix: String): Args {
            map.keys.forEach { k -> if (k !is String) throw BridgeArgumentException("$prefix<key>", "String", typeName(k)) }
            return Args(map)
        }

        fun typeName(v: Any?): String = v?.javaClass?.simpleName ?: "null"
    }
}

// =====================================================================================
// CoreMapper — Dart wire Map → Shoplive core 3.0.3 타입 (순수 함수, design.md rev2 §2.4·§2.6)
// =====================================================================================

/** 채널 `shoplive_core` 메서드명·인자 키(계약 단일 출처 — CoreContractTest가 목록을 고정). */
internal object CoreContract {
    const val INITIALIZE = "initialize"
    const val SET_USER = "setUser"
    const val SET_STREAM_TOKEN = "setStreamToken"
    const val LOGOUT = "logout"
    const val SEND_CONVERSION_EVENT = "sendConversionEvent"
    const val GET_SDK_VERSION = "getSdkVersion"
    val METHODS = listOf(INITIALIZE, SET_USER, SET_STREAM_TOKEN, LOGOUT, SEND_CONVERSION_EVENT, GET_SDK_VERSION)

    const val ACCESS_KEY = "accessKey"
    const val DOMAINS = "allowedWebViewDomains"
    const val ATTRIBUTION = "attribution"
    const val APP_VERSION = "appVersion"
    const val UTM_SOURCE = "utmSource"
    const val UTM_MEDIUM = "utmMedium"
    const val UTM_CAMPAIGN = "utmCampaign"
    const val UTM_CONTENT = "utmContent"
    const val TYPE = "type"
    const val JWT = "jwt"
    const val ID = "id"
    const val NAME = "name"
    const val AGE = "age"
    const val GENDER = "gender"
    const val RANK = "rank"
    const val CUSTOM = "custom"
    const val TOKEN = "token"
    const val PRODUCTS = "products"
    const val ORDER_ID = "orderId"
    const val REFERRER = "referrer"
    const val PRODUCT_ID = "productId"
    const val CUSTOMER_PRODUCT_ID = "customerProductId"
    const val SKU = "sku"
    const val URL = "url"
    const val PURCHASE_QUANTITY = "purchaseQuantity"
    const val PURCHASE_UNIT_PRICE = "purchaseUnitPrice"

    const val USER_GUEST = "guest"
    const val USER_TOKEN = "token"
    const val USER_PROFILE = "profile"
}

internal object CoreMapper {
    private val K = CoreContract
    private const val TAG = "ShopliveCore"

    /** wire(Dart ShopliveGender.name) → SDK 상수(design.md rev2 §2.3). */
    val GENDER_BY_WIRE: Map<String, ShopliveGender> = mapOf(
        "male" to ShopliveGender.MALE,
        "female" to ShopliveGender.FEMALE,
        "neutral" to ShopliveGender.NEUTRAL,
        "undefined" to ShopliveGender.UNDEFINED,
    )

    fun toConfiguration(args: Args): ShopliveConfiguration = Bridge.constructing(K.ACCESS_KEY) {
        val base = ShopliveConfiguration(accessKey = args.requireString(K.ACCESS_KEY))
        // D-3: SDK 3.0.3에서 ShopliveConfiguration.appVersion 제거(SDK가 앱 버전을 직접 읽음) — iOS와 같이 타입만 검증하고 무시.
        // 3.0.2 Dart API 호환을 위해 키는 계속 받는다(비String → INVALID_ARGUMENT) · 근거 SMV-1749
        if (args.optString(K.APP_VERSION) != null) {
            Log.w(TAG, "initialize: appVersion is not supported by the Android SDK 3.0.3 and is ignored")
        }
        base.copy(
            allowedWebViewDomains = args.optNonNullStringList(K.DOMAINS) ?: base.allowedWebViewDomains,
            attribution = args.optArgs(K.ATTRIBUTION)?.let(::toAttribution) ?: base.attribution,
        )
    }

    private fun toAttribution(a: Args): ShopliveAttribution = Bridge.constructing(K.ATTRIBUTION) {
        ShopliveAttribution(
            utmSource = a.optString(K.UTM_SOURCE),
            utmMedium = a.optString(K.UTM_MEDIUM),
            utmCampaign = a.optString(K.UTM_CAMPAIGN),
            utmContent = a.optString(K.UTM_CONTENT),
        )
    }

    fun toUser(args: Args): ShopliveUser = when (args.optString(K.TYPE)) {
        K.USER_GUEST -> ShopliveUser.Guest
        K.USER_TOKEN -> Bridge.constructing(K.JWT) { ShopliveUser.Token(args.requireString(K.JWT)) }
        K.USER_PROFILE -> toProfile(args)
        else -> throw BridgeArgumentException(K.TYPE, "one of [${K.USER_GUEST}, ${K.USER_TOKEN}, ${K.USER_PROFILE}]", "unknown")
    }

    private fun toProfile(args: Args): ShopliveUser.Profile = Bridge.constructing(K.ID) {
        val base = ShopliveUser.Profile(id = args.requireString(K.ID))
        base.copy(
            name = args.optString(K.NAME),
            age = args.optInt(K.AGE),
            gender = args.optWireEnum(K.GENDER, GENDER_BY_WIRE) ?: base.gender,
            rank = args.optInt(K.RANK),
            custom = args.optStringKeyMap(K.CUSTOM),
        )
    }

    fun toStreamToken(args: Args): String = args.requireString(K.TOKEN)

    fun toConversionData(args: Args): ShopliveConversionData = Bridge.constructing(K.PRODUCTS) {
        // type·products는 @Nullable이지만 default 없음 → 생략 시 null 전달(design §2.6)
        val base = ShopliveConversionData(
            type = args.optString(K.TYPE),
            products = args.optList(K.PRODUCTS)?.let(::toProducts),
        )
        base.copy(
            orderId = args.optString(K.ORDER_ID) ?: base.orderId,
            referrer = args.optString(K.REFERRER) ?: base.referrer,
            custom = args.optStringKeyMap(K.CUSTOM) ?: base.custom,
        )
    }

    private fun toProducts(list: List<*>): List<ShopliveConversionProduct> {
        // TODO(SDP-VERIFY): 요확인 — 빈 products 리스트를 SDK·서버가 정상 처리하는지(변형 없이 전달) · 근거 DRAFT-flutter-sdk-302-android/B-05 · 자동 통과 금지(실측)
        return list.mapIndexed { i, e ->
            val key = "${K.PRODUCTS}[$i]"
            val m = e as? Map<*, *> ?: throw BridgeArgumentException(key, "Map", Args.typeName(e))
            toProduct(Args.of(m, prefix = "$key."))
        }
    }

    private fun toProduct(a: Args): ShopliveConversionProduct = ShopliveConversionProduct(
        productId = a.optString(K.PRODUCT_ID),
        customerProductId = a.optString(K.CUSTOMER_PRODUCT_ID),
        sku = a.optString(K.SKU),
        url = a.optString(K.URL),
        purchaseQuantity = a.optInt(K.PURCHASE_QUANTITY),
        purchaseUnitPrice = a.optDouble(K.PURCHASE_UNIT_PRICE),
    )
}
