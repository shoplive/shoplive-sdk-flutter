package cloud.shoplive.shoplive_core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

/** pair #7·#10 보강: 계약 상수 목록 고정, 필수 String 공백 거부, 키+null, 중첩 비String 키. */
class CoreContractTest {

    @Test // case: U-07
    fun methodNames_matchContract() {
        assertEquals(
            listOf("initialize", "setUser", "setStreamToken", "logout", "sendConversionEvent", "getSdkVersion"),
            CoreContract.METHODS,
        )
    }

    @Test // case: U-07
    fun argumentKeys_matchContract() {
        val k = CoreContract
        assertEquals(
            listOf("accessKey", "allowedWebViewDomains", "attribution", "appVersion", "utmSource", "utmMedium", "utmCampaign", "utmContent"),
            listOf(k.ACCESS_KEY, k.DOMAINS, k.ATTRIBUTION, k.APP_VERSION, k.UTM_SOURCE, k.UTM_MEDIUM, k.UTM_CAMPAIGN, k.UTM_CONTENT),
        )
        assertEquals(
            listOf("type", "jwt", "id", "name", "age", "gender", "rank", "custom", "token"),
            listOf(k.TYPE, k.JWT, k.ID, k.NAME, k.AGE, k.GENDER, k.RANK, k.CUSTOM, k.TOKEN),
        )
        assertEquals(
            listOf("products", "orderId", "referrer", "productId", "customerProductId", "sku", "url", "purchaseQuantity", "purchaseUnitPrice"),
            listOf(k.PRODUCTS, k.ORDER_ID, k.REFERRER, k.PRODUCT_ID, k.CUSTOMER_PRODUCT_ID, k.SKU, k.URL, k.PURCHASE_QUANTITY, k.PURCHASE_UNIT_PRICE),
        )
        assertEquals(listOf("guest", "token", "profile"), listOf(k.USER_GUEST, k.USER_TOKEN, k.USER_PROFILE))
    }

    @Test // case: F-04
    fun blankRequiredStrings_areInvalid() {
        val cases = listOf(
            "accessKey" to { CoreMapper.toConfiguration(Args.of(mapOf("accessKey" to " "))) },
            "id" to { CoreMapper.toUser(Args.of(mapOf("type" to "profile", "id" to ""))) },
            "jwt" to { CoreMapper.toUser(Args.of(mapOf("type" to "token", "jwt" to "\t"))) },
            "token" to { CoreMapper.toStreamToken(Args.of(mapOf("token" to ""))) },
        )
        for ((key, block) in cases) {
            val e = assertThrows(key, BridgeArgumentException::class.java) { block() }
            assertEquals(key, e.key)
        }
    }

    @Test // case: B-03
    fun attributionAndAppVersion_keyWithNull_useDefaults() {
        val c = CoreMapper.toConfiguration(Args.of(mapOf("accessKey" to "ak", "attribution" to null, "appVersion" to null)))
        assertNull(c.attribution)
    }

    @Test // case: F-04
    fun productWithNonStringKey_isInvalid() {
        val e = assertThrows(BridgeArgumentException::class.java) {
            CoreMapper.toConversionData(Args.of(mapOf("products" to listOf(mapOf(1 to "x")))))
        }
        assertEquals("products[0].<key>", e.key)
    }
}
