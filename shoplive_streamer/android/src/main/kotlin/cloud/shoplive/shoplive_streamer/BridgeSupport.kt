package cloud.shoplive.shoplive_streamer

// =====================================================================================
// BridgeSupport — 동기화 대상: shoplive_player·shoplive_streamer의 BridgeSupport.kt(package 선언 외 동일해야 함).
// shoplive_core는 이 파일의 부분집합을 CoreMapper.kt에 둔다(design.md rev2 §3.3).
//
// 공통 규칙
//  - 모든 MethodCall은 safeCall로 result를 정확히 1회 완료한다(숨은 책임 ①).
//  - 민감값 로깅 금지: 로그에는 메서드명·예외 클래스명·에러 코드만 남긴다(인자 값·예외 메시지 전문 금지).
//  - 예외 분류: BridgeArgumentException(Bridge.constructing이 SDK 생성자 IAE를 변환한 것 포함) → INVALID_ARGUMENT,
//    BridgeStateException → 해당 코드, Exception·LinkageError → SDK_ERROR, 그 외 Error는 전파(C-5 단서).
// =====================================================================================

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.math.BigInteger

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

    /** core ShopliveError(Exception)는 streamer 경로에서 던져질 수 있다 — 코드만 싣는다(message 제외: 민감값 금지). */
    fun sdkErrorDetails(t: Throwable): Map<String, Any?> {
        val details = mutableMapOf<String, Any?>("exception" to t.javaClass.name)
        if (t is cloud.shoplive.core.publicsurface.ShopliveError) details += errorToWire(t) - ERROR_MESSAGE
        return details
    }

    /**
     * Error 이벤트 payload `{code, message, rawCode, recoverable}`(design §2.5) — player·streamer 공통 단일 매핑.
     * SDK 3.0.3부터 player Error도 core ShopliveError(rawCode Int 상시). code는 SDK 상수명 그대로(불투명 문자열 — 값이 바뀌어도 그대로 전달).
     */
    fun errorToWire(e: cloud.shoplive.core.publicsurface.ShopliveError): Map<String, Any?> =
        mapOf("code" to e.code.name, ERROR_MESSAGE to e.message, "rawCode" to e.rawCode, "recoverable" to e.isRecoverable)

    private const val ERROR_MESSAGE = "message"

    /** SDK 생성자·copy 호출을 감싼다: IllegalArgumentException → INVALID_ARGUMENT(key). */
    inline fun <T> constructing(key: String, block: () -> T): T = try {
        block()
    } catch (e: BridgeArgumentException) {
        throw e
    } catch (e: IllegalArgumentException) {
        throw BridgeArgumentException(key, "value accepted by SDK", "rejected(${e.javaClass.simpleName})")
    }
}

/** 엔진 attach 세대. detach 이후 도착한 비동기 완료를 판별한다(pair #13). 메인 스레드 전용. */
internal class AttachGeneration {
    var current: Long = 0L
        private set

    fun next(): Long = ++current

    fun isCurrent(generation: Long): Boolean = generation == current
}

/**
 * webPageUrl 판정 규칙 — 플랫폼 URL 파서(java.net.URI / iOS URLComponents·URL)는 서로 판정이 달라 쓰지 않고(SMV-1749 R1-01)
 * 아래 문자열 규칙만 쓴다. iOS BridgeCore `WebURLRule`과 같은 정의이며 공용 벡터
 * (shoplive_streamer/test/fixtures/http_url_vectors.json)로 양쪽 테스트가 같은 결과를 확인한다.
 *  ① 비어 있지 않고 공백·제어문자([isSpaceOrControl])가 없다 ② `http://`·`https://`로 시작(ASCII 대소문자 무시)
 *  ③ 스킴 뒤 authority(첫 `/` `?` `#` 전)에 역슬래시가 없다 ④ authority에서 userinfo(마지막 `@` 앞)·포트(마지막 `:` 뒤,
 *  `[IPv6]`는 `]`까지가 host)를 뗀 host가 비어 있지 않다. 그 밖(비ASCII 경로·밑줄 호스트·포트 형식 등)은 판정하지 않고 SDK에 넘긴다.
 */
internal object WebUrlRule {
    const val EXPECTED = "http(s) URL without spaces"
    private val SCHEMES = listOf("http://", "https://")
    private const val AUTHORITY_END = "/?#"

    fun accepts(s: String): Boolean {
        if (s.isEmpty() || s.codePoints().anyMatch { isSpaceOrControl(it) }) return false
        val scheme = SCHEMES.firstOrNull { hasAsciiPrefixIgnoringCase(s, it) } ?: return false
        val rest = s.substring(scheme.length)
        val end = rest.indexOfFirst { it in AUTHORITY_END }
        val authority = if (end < 0) rest else rest.substring(0, end)
        return '\\' !in authority && host(authority).isNotEmpty()
    }

    /** authority → host: userinfo(마지막 `@` 앞)와 포트(마지막 `:` 뒤)를 뗀다. `[`로 시작하면 첫 `]`까지가 host(IPv6). */
    private fun host(authority: String): String {
        val hostPort = authority.substringAfterLast('@')
        if (hostPort.startsWith('[')) {
            val close = hostPort.indexOf(']')
            return if (close < 0) hostPort else hostPort.substring(0, close + 1)
        }
        return hostPort.substringBeforeLast(':')
    }

    /** C0·DEL·C1 제어문자 + Unicode White_Space. 플랫폼 isWhitespace 정의 차이를 피하려 코드포인트로 고정(iOS와 같은 목록). */
    fun isSpaceOrControl(cp: Int): Boolean =
        cp <= 0x20 || cp in 0x7F..0x9F || cp == 0xA0 || cp == 0x1680 || cp in 0x2000..0x200A ||
            cp == 0x2028 || cp == 0x2029 || cp == 0x202F || cp == 0x205F || cp == 0x3000

    /** [prefix]는 소문자 ASCII. 비ASCII 문자의 대소문자 접기(locale·Unicode 규칙)는 적용하지 않는다. */
    private fun hasAsciiPrefixIgnoringCase(s: String, prefix: String): Boolean =
        s.length >= prefix.length && prefix.indices.all { i -> (if (s[i] in 'A'..'Z') s[i] + ASCII_CASE_OFFSET else s[i]) == prefix[i] }

    private const val ASCII_CASE_OFFSET = 'a' - 'A'
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

    /**
     * http(s) 웹 URL 문자열(키 부재·null → null). [WebUrlRule] 위반 → INVALID_ARGUMENT(값은 싣지 않음). 통과한 문자열은 변형 없이 반환.
     */
    fun optHttpUrl(key: String): String? {
        val raw = optString(key) ?: return null
        if (!WebUrlRule.accepts(raw)) throw BridgeArgumentException(key, WebUrlRule.EXPECTED, "not http(s) URL")
        return raw
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

/** wire 테이블 역방향 조회(SDK enum → wire). 테이블에 없는 상수는 "unknown"(Dart가 unknown으로 받음, B-02). */
internal fun <E> wireOf(value: E?, table: Map<String, E>): String? {
    if (value == null) return null
    return table.entries.firstOrNull { it.value == value }?.key ?: WIRE_UNKNOWN
}

internal const val WIRE_UNKNOWN = "unknown"

/**
 * 네이티브→Dart payload 정규화(숨은 책임 ⑪, design §2.5). StandardMessageCodec이 받는 타입만 남긴다.
 * 정수형→Long, 그 외 Number→Double, Map 키→String, 배열/JSONArray→List, JSONObject→Map, JSONObject.NULL→null, 기타→toString.
 */
internal object ValueNormalizer {
    const val MAX_DEPTH = 32

    fun normalize(value: Any?): Any? = normalize(value, 0)

    private fun normalize(value: Any?, depth: Int): Any? {
        if (value == null || value == JSONObject.NULL) return null
        return when (value) {
            is Boolean, is String -> value
            is Byte, is Short, is Int, is Long -> (value as Number).toLong()
            is BigInteger -> if (value.bitLength() < Long.SIZE_BITS) value.toLong() else value.toDouble()
            is Number -> value.toDouble()
            else -> if (depth >= MAX_DEPTH) {
                value.toString()
            } else {
                normalizeContainer(value, depth + 1)
            }
        }
    }

    private fun normalizeContainer(value: Any, depth: Int): Any? = when (value) {
        is Map<*, *> -> value.entries.associate { (k, v) -> k.toString() to normalize(v, depth) }
        is JSONObject -> value.keys().asSequence().associateWith { normalize(value.opt(it), depth) }
        is Iterable<*> -> value.map { normalize(it, depth) }
        is JSONArray -> (0 until value.length()).map { normalize(value.opt(it), depth) }
        is Array<*> -> value.map { normalize(it, depth) }
        is IntArray -> value.map { it.toLong() }
        is LongArray -> value.toList()
        is DoubleArray -> value.toList()
        is BooleanArray -> value.toList()
        else -> value.toString()
    }
}

/** 메인 스레드 스케줄러(테스트에서 대체). */
internal interface MainScheduler {
    fun isMainThread(): Boolean
    fun post(task: Runnable)
    fun postDelayed(task: Runnable, delayMs: Long): Cancellable
}

internal fun interface Cancellable {
    fun cancel()
}

internal class HandlerMainScheduler : MainScheduler {
    private val handler = Handler(Looper.getMainLooper())
    override fun isMainThread(): Boolean = Looper.myLooper() == Looper.getMainLooper()
    override fun post(task: Runnable) {
        handler.post(task)
    }
    override fun postDelayed(task: Runnable, delayMs: Long): Cancellable {
        handler.postDelayed(task, delayMs)
        return Cancellable { handler.removeCallbacks(task) }
    }
}

/**
 * EventChannel 하나의 sink 보관·emit. 메인이 아니면 hop, sink 없으면 드롭, sink.success 실패는 로그 후 드롭(X-06).
 * [onCancelled]: Dart 구독 해제 시 호출(requests 채널의 flushAll 등).
 */
internal class EventEmitter(
    private val name: String,
    private val scheduler: MainScheduler,
    private val onCancelled: () -> Unit = {},
) : EventChannel.StreamHandler {

    private var sink: EventChannel.EventSink? = null

    fun hasListener(): Boolean = sink != null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        onCancelled()
    }

    fun clear() {
        sink = null
    }

    /** @return 메인에서 즉시 전달됐으면 true, 드롭·실패면 false, 메인 hop 예약이면 true. */
    fun emit(event: Map<String, Any?>): Boolean {
        if (!scheduler.isMainThread()) {
            scheduler.post { deliver(event) }
            return true
        }
        return deliver(event)
    }

    private fun deliver(event: Map<String, Any?>): Boolean {
        val s = sink ?: run {
            Log.d(TAG, "$name: no listener, dropped ${event[KEY_TYPE]}")
            return false
        }
        return try {
            s.success(event)
            true
        } catch (e: Exception) {
            Log.e(TAG, "$name: emit failed ${e.javaClass.name}")
            false
        }
    }

    companion object {
        private const val TAG = "ShopliveEventEmitter"
        const val KEY_TYPE = "type"
    }
}
