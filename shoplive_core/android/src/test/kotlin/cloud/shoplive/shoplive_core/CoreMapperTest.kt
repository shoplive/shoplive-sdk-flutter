package cloud.shoplive.shoplive_core

import cloud.shoplive.core.publicsurface.ShopliveGender
import cloud.shoplive.core.publicsurface.ShopliveUser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreMapperTest {

    // ---- Args ----

    @Test // case: F-04
    fun args_nonMapArguments_isInvalid() {
        val e = assertThrows(BridgeArgumentException::class.java) { Args.of("not a map") }
        assertEquals(Args.ROOT_KEY, e.key)
    }

    @Test
    fun args_nullArguments_isEmpty() {
        assertTrue(Args.of(null).isEmpty())
    }

    @Test // case: B-06
    fun args_intFromLong_inRange_andOutOfRange() {
        assertEquals(7, Args.of(mapOf("n" to 7L)).optInt("n"))
        val e = assertThrows(BridgeArgumentException::class.java) {
            Args.of(mapOf("n" to Long.MAX_VALUE)).optInt("n")
        }
        assertEquals("n", e.key)
    }

    @Test // case: B-06
    fun args_intFromDouble_isInvalid() {
        assertThrows(BridgeArgumentException::class.java) { Args.of(mapOf("n" to 1.5)).optInt("n") }
    }

    @Test // case: B-06
    fun args_doubleAcceptsInteger() {
        assertEquals(1000.0, Args.of(mapOf("d" to 1000)).optDouble("d")!!, 0.0)
    }

    @Test // case: F-04
    fun args_requireString_missingOrWrongType_isInvalid() {
        assertThrows(BridgeArgumentException::class.java) { Args.of(emptyMap<String, Any>()).requireString("k") }
        assertThrows(BridgeArgumentException::class.java) { Args.of(mapOf("k" to 1)).requireString("k") }
        assertThrows(BridgeArgumentException::class.java) { Args.of(mapOf("k" to null)).requireString("k") }
    }

    @Test // case: B-04
    fun args_mapWithNonStringKey_isInvalid() {
        assertThrows(BridgeArgumentException::class.java) { Args.of(mapOf("m" to mapOf(1 to "a"))).optStringKeyMap("m") }
    }

    // ---- initialize ----

    @Test // case: B-03, N-01
    fun configuration_minimal_usesSdkDefaults() {
        val c = CoreMapper.toConfiguration(Args.of(mapOf("accessKey" to "ak")))
        assertEquals("ak", c.accessKey)
        assertEquals(emptyList<String>(), c.allowedWebViewDomains)
        assertNull(c.attribution)
    }

    @Test // case: N-01, SMV-1749 appVersion 무시
    fun configuration_full() {
        val c = CoreMapper.toConfiguration(
            Args.of(
                mapOf(
                    "accessKey" to "ak",
                    "allowedWebViewDomains" to listOf("a.com", "b.com"),
                    "attribution" to mapOf("utmSource" to "s", "utmMedium" to "m", "utmCampaign" to "c", "utmContent" to "t"),
                    "appVersion" to "1.2.3",
                ),
            ),
        )
        assertEquals(listOf("a.com", "b.com"), c.allowedWebViewDomains)
        assertEquals("s", c.attribution!!.utmSource)
        assertEquals("m", c.attribution!!.utmMedium)
        assertEquals("c", c.attribution!!.utmCampaign)
        assertEquals("t", c.attribution!!.utmContent)
        // SDK 3.0.3: appVersion은 SDK에 전달되지 않는다(설정 객체에 필드 없음) — 나머지 필드만 반영
        assertEquals(CoreMapper.toConfiguration(Args.of(mapOf(
            "accessKey" to "ak",
            "allowedWebViewDomains" to listOf("a.com", "b.com"),
            "attribution" to mapOf("utmSource" to "s", "utmMedium" to "m", "utmCampaign" to "c", "utmContent" to "t"),
        ))), c)
    }

    @Test // case: SMV-1749 appVersion 비String은 3.0.2와 같이 INVALID_ARGUMENT(무시 전 타입 검증)
    fun configuration_appVersionWrongType_isInvalid() {
        val e = assertThrows(BridgeArgumentException::class.java) {
            CoreMapper.toConfiguration(Args.of(mapOf("accessKey" to "ak", "appVersion" to 1)))
        }
        assertEquals("appVersion", e.key)
    }

    @Test // case: F-04
    fun configuration_missingAccessKey_isInvalid() {
        val e = assertThrows(BridgeArgumentException::class.java) { CoreMapper.toConfiguration(Args.of(emptyMap<String, Any>())) }
        assertEquals("accessKey", e.key)
    }

    @Test // case: B-03
    fun configuration_explicitNullDomains_isInvalid() {
        // allowedWebViewDomains는 @NotNull(default emptyList) — 키+null은 거부(design §2.6)
        val e = assertThrows(BridgeArgumentException::class.java) {
            CoreMapper.toConfiguration(Args.of(mapOf("accessKey" to "ak", "allowedWebViewDomains" to null)))
        }
        assertEquals("allowedWebViewDomains", e.key)
    }

    @Test // case: F-04
    fun configuration_nonStringDomain_isInvalid() {
        assertThrows(BridgeArgumentException::class.java) {
            CoreMapper.toConfiguration(Args.of(mapOf("accessKey" to "ak", "allowedWebViewDomains" to listOf("a", 1))))
        }
    }

    // ---- setUser ----

    @Test // case: N-01
    fun user_guest() {
        assertSame(ShopliveUser.Guest, CoreMapper.toUser(Args.of(mapOf("type" to "guest"))))
    }

    @Test // case: N-01
    fun user_token() {
        val u = CoreMapper.toUser(Args.of(mapOf("type" to "token", "jwt" to "j"))) as ShopliveUser.Token
        assertEquals("j", u.jwt)
    }

    @Test // case: F-04
    fun user_token_missingJwt_isInvalid() {
        val e = assertThrows(BridgeArgumentException::class.java) { CoreMapper.toUser(Args.of(mapOf("type" to "token"))) }
        assertEquals("jwt", e.key)
    }

    @Test // case: B-03
    fun user_profile_minimal_defaultGender() {
        val u = CoreMapper.toUser(Args.of(mapOf("type" to "profile", "id" to "u1"))) as ShopliveUser.Profile
        assertEquals("u1", u.id)
        assertEquals(ShopliveUser.Profile("u1").gender, u.gender)
        assertNull(u.name)
        assertNull(u.age)
        assertNull(u.rank)
        assertNull(u.custom)
    }

    @Test // case: B-04
    fun user_profile_full_withNestedCustom() {
        val custom = mapOf("tier" to "gold", "tags" to listOf("a", "b"), "nested" to mapOf("k" to 1L))
        val u = CoreMapper.toUser(
            Args.of(
                mapOf(
                    "type" to "profile", "id" to "u1", "name" to "N", "age" to 30, "gender" to "female",
                    "rank" to 2L, "custom" to custom,
                ),
            ),
        ) as ShopliveUser.Profile
        assertEquals("N", u.name)
        assertEquals(30, u.age)
        assertEquals(ShopliveGender.FEMALE, u.gender)
        assertEquals(2, u.rank)
        assertEquals(custom, u.custom)
    }

    @Test // case: B-03
    fun user_profile_missingId_isInvalid() {
        val e = assertThrows(BridgeArgumentException::class.java) { CoreMapper.toUser(Args.of(mapOf("type" to "profile"))) }
        assertEquals("id", e.key)
    }

    @Test // case: B-01
    fun user_profile_unknownGender_isInvalid() {
        val e = assertThrows(BridgeArgumentException::class.java) {
            CoreMapper.toUser(Args.of(mapOf("type" to "profile", "id" to "u1", "gender" to "FEMALE")))
        }
        assertEquals("gender", e.key)
    }

    @Test // case: B-03
    fun user_profile_explicitNullGender_isInvalid() {
        assertThrows(BridgeArgumentException::class.java) {
            CoreMapper.toUser(Args.of(mapOf("type" to "profile", "id" to "u1", "gender" to null)))
        }
    }

    @Test // case: B-01
    fun user_unknownType_isInvalid() {
        val e = assertThrows(BridgeArgumentException::class.java) { CoreMapper.toUser(Args.of(mapOf("type" to "admin"))) }
        assertEquals("type", e.key)
    }

    @Test // case: B-01
    fun gender_wireTable_coversAllSdkConstants() {
        assertEquals(ShopliveGender.values().toSet(), CoreMapper.GENDER_BY_WIRE.values.toSet())
    }

    // ---- setStreamToken ----

    @Test // case: B-03
    fun streamToken_nullOrMissing_isInvalid() {
        assertThrows(BridgeArgumentException::class.java) { CoreMapper.toStreamToken(Args.of(mapOf("token" to null))) }
        assertThrows(BridgeArgumentException::class.java) { CoreMapper.toStreamToken(Args.of(emptyMap<String, Any>())) }
        assertEquals("t", CoreMapper.toStreamToken(Args.of(mapOf("token" to "t"))))
    }

    // ---- sendConversionEvent ----

    @Test // case: B-03
    fun conversion_empty_allNull() {
        val d = CoreMapper.toConversionData(Args.of(emptyMap<String, Any>()))
        assertNull(d.type)
        assertNull(d.products)
        assertNull(d.orderId)
        assertNull(d.referrer)
        assertNull(d.custom)
    }

    @Test // case: B-06, N-01
    fun conversion_products_numberConversion() {
        val d = CoreMapper.toConversionData(
            Args.of(
                mapOf(
                    "type" to "purchase", "orderId" to "o1", "referrer" to "r", "custom" to mapOf("x" to true),
                    "products" to listOf(
                        mapOf("productId" to "p1", "sku" to "s1", "purchaseQuantity" to 2L, "purchaseUnitPrice" to 1000),
                        emptyMap<String, Any>(),
                    ),
                ),
            ),
        )
        assertEquals("purchase", d.type)
        assertEquals("o1", d.orderId)
        assertEquals("r", d.referrer)
        assertEquals(mapOf("x" to true), d.custom)
        val p = d.products!!
        assertEquals(2, p.size)
        assertEquals("p1", p[0].productId)
        assertEquals("s1", p[0].sku)
        assertEquals(2, p[0].purchaseQuantity)
        assertEquals(1000.0, p[0].purchaseUnitPrice!!, 0.0)
        assertNull(p[1].productId)
        assertNull(p[1].purchaseQuantity)
    }

    @Test // case: B-05
    fun conversion_emptyProducts_passedThrough() {
        val d = CoreMapper.toConversionData(Args.of(mapOf("products" to emptyList<Any>())))
        assertEquals(0, d.products!!.size)
    }

    @Test // case: F-04
    fun conversion_nonMapProduct_isInvalid() {
        val e = assertThrows(BridgeArgumentException::class.java) {
            CoreMapper.toConversionData(Args.of(mapOf("products" to listOf("p"))))
        }
        assertEquals("products[0]", e.key)
    }
}
