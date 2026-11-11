package cloud.shoplive.shoplive_player

import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.math.BigDecimal
import java.math.BigInteger

internal class FakeScheduler(var onMain: Boolean = true) : MainScheduler {
    var now = 0L
    private var seq = 0
    private val tasks = mutableListOf<Triple<Int, Long, Runnable>>()
    val posted = mutableListOf<Runnable>()

    override fun isMainThread(): Boolean = onMain
    override fun post(task: Runnable) { posted += task }
    override fun postDelayed(task: Runnable, delayMs: Long): Cancellable {
        val id = seq++
        tasks += Triple(id, now + delayMs, task)
        return Cancellable { tasks.removeAll { it.first == id } }
    }

    fun pendingTimers(): Int = tasks.size

    fun advance(ms: Long) {
        now += ms
        while (true) {
            val due = tasks.filter { it.second <= now }.minByOrNull { it.second } ?: break
            tasks.remove(due)
            due.third.run()
        }
    }

    fun runPosted() { val copy = posted.toList(); posted.clear(); copy.forEach { it.run() } }
}

internal class RecordingSink(private val failWith: RuntimeException? = null) : EventChannel.EventSink {
    val events = mutableListOf<Any?>()
    override fun success(event: Any?) { failWith?.let { throw it }; events += event }
    override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {}
    override fun endOfStream() {}
}

class BridgeSupportTest {

    // ---- Args (player 확장) ----

    @Test // case: F-04
    fun args_requireBool() {
        assertEquals(true, Args.of(mapOf("b" to true)).requireBool("b"))
        assertThrows(BridgeArgumentException::class.java) { Args.of(mapOf("b" to "true")).requireBool("b") }
        assertThrows(BridgeArgumentException::class.java) { Args.of(emptyMap<String, Any>()).requireBool("b") }
    }

    @Test // case: B-06
    fun args_optFloat_acceptsIntAndDouble() {
        assertEquals(0.5f, Args.of(mapOf("f" to 0.5)).optFloat("f")!!, 0f)
        assertEquals(2f, Args.of(mapOf("f" to 2)).optFloat("f")!!, 0f)
    }

    @Test // case: F-04
    fun args_optStringMap_rejectsNonStringValue() {
        assertEquals(mapOf("a" to "b"), Args.of(mapOf("m" to mapOf("a" to "b"))).optStringStringMap("m"))
        assertThrows(BridgeArgumentException::class.java) {
            Args.of(mapOf("m" to mapOf("a" to 1))).optStringStringMap("m")
        }
    }

    @Test // case: G-6 (R6-A4, SMV-1899) — iOS Args.optNonNullStringList와 같은 규칙: 생략 null, 키+null·비리스트·비문자열 원소 INVALID
    fun args_optNonNullStringList() {
        assertEquals(listOf("a", "b"), Args.of(mapOf("l" to listOf("a", "b"))).optNonNullStringList("l"))
        assertEquals(emptyList<String>(), Args.of(mapOf("l" to emptyList<Any>())).optNonNullStringList("l"))
        assertNull(Args.of(emptyMap<String, Any>()).optNonNullStringList("l"))
        assertThrows(BridgeArgumentException::class.java) { Args.of(mapOf("l" to null)).optNonNullStringList("l") }
        assertThrows(BridgeArgumentException::class.java) { Args.of(mapOf("l" to "a")).optNonNullStringList("l") }
        val e = assertThrows(BridgeArgumentException::class.java) { Args.of(mapOf("l" to listOf("a", 1))).optNonNullStringList("l") }
        assertEquals("l[1]", e.key)
    }

    @Test // case: B-03
    fun args_hasNullable_distinguishesMissingAndNull() {
        val a = Args.of(mapOf("x" to null))
        assertTrue(a.has("x"))
        assertTrue(!a.has("y"))
    }

    // ---- ValueNormalizer (숨은 책임 ⑪, X-06) ----

    @Test // case: B-07
    fun normalize_primitivesAndNumbers() {
        assertNull(ValueNormalizer.normalize(null))
        assertEquals(true, ValueNormalizer.normalize(true))
        assertEquals("s", ValueNormalizer.normalize("s"))
        assertEquals(1L, ValueNormalizer.normalize(1))
        assertEquals(2L, ValueNormalizer.normalize(2.toShort()))
        assertEquals(3L, ValueNormalizer.normalize(3.toByte()))
        assertEquals(4L, ValueNormalizer.normalize(4L))
        assertEquals(5L, ValueNormalizer.normalize(BigInteger.valueOf(5)))
        assertEquals(1.5, ValueNormalizer.normalize(1.5f))
        assertEquals(2.0, ValueNormalizer.normalize(2.0))
        assertEquals(1.25, ValueNormalizer.normalize(BigDecimal("1.25")))
        val huge = BigInteger.valueOf(Long.MAX_VALUE).add(BigInteger.ONE)
        assertEquals(huge.toDouble(), ValueNormalizer.normalize(huge))
    }

    @Test // case: B-07
    fun normalize_containersAndKeys() {
        val input = mapOf(1 to listOf("a", arrayOf(1, 2)), "k" to mapOf("n" to null))
        val out = ValueNormalizer.normalize(input) as Map<*, *>
        assertEquals(listOf("a", listOf(1L, 2L)), out["1"])
        assertEquals(mapOf("n" to null), out["k"])
    }

    @Test // case: B-07
    fun normalize_json() {
        val json = JSONObject().put("a", 1).put("b", JSONArray().put("x").put(JSONObject.NULL)).put("c", JSONObject.NULL)
        val out = ValueNormalizer.normalize(json) as Map<*, *>
        assertEquals(1L, out["a"])
        assertEquals(listOf("x", null), out["b"])
        assertTrue(out.containsKey("c"))
        assertNull(out["c"])
    }

    @Test // case: B-07
    fun normalize_unknownType_toString() {
        val obj = object { override fun toString() = "custom" }
        assertEquals("custom", ValueNormalizer.normalize(obj))
    }

    @Test // case: B-07
    fun normalize_depthLimit_stringifiesDeepNode() {
        var nested: Any = "leaf"
        repeat(ValueNormalizer.MAX_DEPTH + 2) { nested = listOf(nested) }
        // 예외 없이 끝나야 하며 상한 아래 노드는 문자열로 대체됨
        var cur: Any? = ValueNormalizer.normalize(nested)
        var depth = 0
        while (cur is List<*>) { cur = cur.single(); depth++ }
        assertTrue(cur is String)
        assertEquals(ValueNormalizer.MAX_DEPTH, depth)
    }

    // ---- EventEmitter ----

    @Test // case: R-01
    fun emitter_withoutSink_drops() {
        val e = EventEmitter("ch", FakeScheduler())
        e.emit(mapOf("type" to "x"))
        assertTrue(!e.hasListener())
    }

    @Test // case: U-01
    fun emitter_onMain_deliversImmediately() {
        val s = FakeScheduler()
        val e = EventEmitter("ch", s)
        val sink = RecordingSink()
        e.onListen(null, sink)
        e.emit(mapOf("type" to "x"))
        assertEquals(listOf(mapOf("type" to "x")), sink.events)
    }

    @Test // case: T-05
    fun emitter_offMain_hopsToMain() {
        val s = FakeScheduler(onMain = false)
        val e = EventEmitter("ch", s)
        val sink = RecordingSink()
        e.onListen(null, sink)
        e.emit(mapOf("type" to "x"))
        assertEquals(0, sink.events.size)
        s.runPosted()
        assertEquals(1, sink.events.size)
    }

    @Test // case: R-02
    fun emitter_afterCancel_drops_andNotifies() {
        var cancelled = 0
        val e = EventEmitter("ch", FakeScheduler(), onCancelled = { cancelled++ })
        val sink = RecordingSink()
        e.onListen(null, sink)
        e.onCancel(null)
        e.emit(mapOf("type" to "x"))
        assertEquals(0, sink.events.size)
        assertEquals(1, cancelled)
    }

    @Test // case: B-07
    fun emitter_sinkFailure_isSwallowedAndLogged_returnsFalse() {
        val e = EventEmitter("ch", FakeScheduler())
        e.onListen(null, RecordingSink(IllegalArgumentException("Unsupported value")))
        assertEquals(false, e.emit(mapOf("type" to "x")))
    }

    @Test // case: R-03
    fun emitter_clear_dropsSink() {
        val e = EventEmitter("ch", FakeScheduler())
        val sink = RecordingSink()
        e.onListen(null, sink)
        e.clear()
        e.emit(mapOf("a" to 1))
        assertEquals(0, sink.events.size)
    }
}
