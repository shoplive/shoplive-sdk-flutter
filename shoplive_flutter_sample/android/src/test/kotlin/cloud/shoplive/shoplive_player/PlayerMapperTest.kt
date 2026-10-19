package cloud.shoplive.shoplive_player

import cloud.shoplive.core.publicsurface.ShopliveError
import cloud.shoplive.core.publicsurface.ShopliveErrorCode
import cloud.shoplive.player.ShopliveAnalyticsInfo
import cloud.shoplive.player.ShopliveBrand
import cloud.shoplive.player.ShopliveCampaign
import cloud.shoplive.player.ShopliveCampaignInfo
import cloud.shoplive.player.ShopliveCampaignStatus
import cloud.shoplive.player.ShopliveConnectionState
import cloud.shoplive.player.ShopliveNavigationAction
import cloud.shoplive.player.ShopliveOverlayUIMode
import cloud.shoplive.player.ShopliveInsets
import cloud.shoplive.player.ShoplivePipPosition
import cloud.shoplive.player.ShoplivePipRatio
import cloud.shoplive.player.ShoplivePlayOptions
import cloud.shoplive.player.ShoplivePlaybackEvent
import cloud.shoplive.player.ShoplivePlayerConfiguration
import cloud.shoplive.player.ShoplivePlayerEvent
import cloud.shoplive.player.ShoplivePlayerPresentationStyle
import cloud.shoplive.player.ShoplivePlayerState
import cloud.shoplive.player.ShoplivePlayerType
import cloud.shoplive.player.ShopliveResizeMode
import cloud.shoplive.player.ShopliveResultAlertType
import cloud.shoplive.player.ShopliveResultStatus
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class PlayerMapperTest {

    // ---- wire 테이블: SDK 상수 전부를 덮는다(design §2.3) ----

    @Test // case: B-01, B-02
    fun wireTables_coverAllSdkConstants() {
        fun <E> check(table: Map<String, E>, all: Array<E>) = assertEquals(all.toSet(), table.values.toSet())
        check(PlayerMapper.PLAYER_STATE, ShoplivePlayerState.values())
        check(PlayerMapper.CAMPAIGN_STATUS, ShopliveCampaignStatus.values())
        check(PlayerMapper.CONNECTION_STATE, ShopliveConnectionState.values())
        check(PlayerMapper.RESIZE_MODE, ShopliveResizeMode.values())
        check(PlayerMapper.OVERLAY_UI, ShopliveOverlayUIMode.values())
        check(PlayerMapper.PRESENTATION_STYLE, ShoplivePlayerPresentationStyle.values())
        check(PlayerMapper.PLAYER_TYPE, ShoplivePlayerType.values())
        check(PlayerMapper.PIP_POSITION, ShoplivePipPosition.values())
        check(PlayerMapper.PIP_RATIO, ShoplivePipRatio.values())
        check(PlayerMapper.NAVIGATION_ACTION, ShopliveNavigationAction.values())
        check(PlayerMapper.RESULT_STATUS, ShopliveResultStatus.values())
        check(PlayerMapper.ALERT_TYPE, ShopliveResultAlertType.values())
    }

    @Test // case: B-01
    fun wireNames_areCamelCase() {
        assertEquals("inAppPip", wireOf(ShoplivePlayerState.IN_APP_PIP, PlayerMapper.PLAYER_STATE))
        assertEquals("ratio9x16", wireOf(ShoplivePipRatio.RATIO_9X16, PlayerMapper.PIP_RATIO))
        assertEquals("builtIn", wireOf(ShopliveOverlayUIMode.BUILT_IN, PlayerMapper.OVERLAY_UI))
        assertEquals("bottomRight", wireOf(ShoplivePipPosition.BOTTOM_RIGHT, PlayerMapper.PIP_POSITION))
    }

    // ---- PlayOptions ----

    @Test // case: B-03
    fun playOptions_omitted_isSdkDefault() {
        val d = ShoplivePlayOptions()
        val o = PlayerMapper.toPlayOptions(null)
        assertEquals(d.referrer, o.referrer)
        assertEquals(d.keepWindowStateOnPlayExecuted, o.keepWindowStateOnPlayExecuted)
        assertEquals(d.presentationStyle, o.presentationStyle)
    }

    @Test // case: N-02
    fun playOptions_full() {
        val o = PlayerMapper.toPlayOptions(
            Args.of(mapOf("referrer" to "r", "keepWindowStateOnPlayExecuted" to true, "presentationStyle" to "pip")),
        )
        assertEquals("r", o.referrer)
        assertEquals(true, o.keepWindowStateOnPlayExecuted)
        assertEquals(ShoplivePlayerPresentationStyle.PIP, o.presentationStyle)
    }

    @Test // case: B-06 (DRAFT-flutter-sdk-302-ios: Dart 0xFF00FF00 is 4278255360, beyond Int)
    fun indicatorColor_unsignedArgb_roundTrips() {
        val merged = PlayerMapper.mergeConfiguration(
            ShoplivePlayerConfiguration(),
            Args.of(mapOf("appearance" to mapOf("indicatorColor" to 0xFF00FF00L))),
        )
        assertEquals(0xFF00FF00.toInt(), merged.appearance.indicatorColor)
        assertEquals(0xFF00FF00L, (PlayerMapper.configurationToWire(merged)["appearance"] as Map<*, *>)["indicatorColor"])
        val signed = PlayerMapper.mergeConfiguration(ShoplivePlayerConfiguration(), Args.of(mapOf("appearance" to mapOf("indicatorColor" to -16711936))))
        assertEquals(0xFF00FF00.toInt(), signed.appearance.indicatorColor)
        assertThrows(BridgeArgumentException::class.java) {
            PlayerMapper.mergeConfiguration(ShoplivePlayerConfiguration(), Args.of(mapOf("appearance" to mapOf("indicatorColor" to 0x1_0000_0000L))))
        }
    }

    @Test // case: B-03
    fun playOptions_keyWithNull_forNonNullField_isInvalid() {
        val e = assertThrows(BridgeArgumentException::class.java) {
            PlayerMapper.toPlayOptions(Args.of(mapOf("keepWindowStateOnPlayExecuted" to null)))
        }
        assertEquals("keepWindowStateOnPlayExecuted", e.key)
        assertThrows(BridgeArgumentException::class.java) { PlayerMapper.toPlayOptions(Args.of(mapOf("presentationStyle" to null))) }
        assertNull(PlayerMapper.toPlayOptions(Args.of(mapOf("referrer" to null))).referrer)
    }

    @Test // case: B-01
    fun playOptions_unknownStyle_isInvalid() {
        val e = assertThrows(BridgeArgumentException::class.java) {
            PlayerMapper.toPlayOptions(Args.of(mapOf("presentationStyle" to "PIP")))
        }
        assertEquals("presentationStyle", e.key)
    }

    // ---- Configuration 병합(CFG-01) ----

    @Test // case: CFG-01
    fun merge_partial_keepsCurrentValues() {
        val current = ShoplivePlayerConfiguration()
        val partial = Args.of(mapOf("pip" to mapOf("isInAppPipEnabled" to true), "sound" to mapOf("muteOnStart" to true)))
        val merged = PlayerMapper.mergeConfiguration(current, partial)
        assertEquals(true, merged.pip.isInAppPipEnabled)
        assertEquals(true, merged.sound.muteOnStart)
        assertEquals(current.pip.isOSPipEnabled, merged.pip.isOSPipEnabled)
        assertEquals(current.pip.aspectRatio, merged.pip.aspectRatio)
        assertEquals(current.sound.mixWithOthers, merged.sound.mixWithOthers)
        assertEquals(current.type, merged.type)
        assertEquals(current.appearance.loadingAnimation, merged.appearance.loadingAnimation)
        assertEquals(current.appearance.chatInputTypeface, merged.appearance.chatInputTypeface)
    }

    @Test // case: CFG-01
    fun merge_overPreviouslyMerged_accumulates() {
        val first = PlayerMapper.mergeConfiguration(ShoplivePlayerConfiguration(), Args.of(mapOf("pip" to mapOf("isInAppPipEnabled" to true))))
        val second = PlayerMapper.mergeConfiguration(first, Args.of(mapOf("overlay" to mapOf("ui" to "hidden"))))
        assertEquals(true, second.pip.isInAppPipEnabled)
        assertEquals(ShopliveOverlayUIMode.HIDDEN, second.overlay.ui)
    }

    @Test // case: CFG-01, CS-03
    fun merge_full_includingAndroidMap() {
        val merged = PlayerMapper.mergeConfiguration(
            ShoplivePlayerConfiguration(),
            Args.of(
                mapOf(
                    "type" to "preview",
                    "pip" to mapOf(
                        "isInAppPipEnabled" to true, "isOSPipEnabled" to false, "defaultPosition" to "topLeft",
                        "scale" to 0.5, "aspectRatio" to "ratio1x1", "padding" to mapOf("left" to 1, "top" to 2, "right" to 3, "bottom" to 4),
                    ),
                    "sound" to mapOf("muteOnStart" to true, "mixWithOthers" to true),
                    "appearance" to mapOf("indicatorColor" to 0xFF00FF00.toInt()),
                    "navigation" to mapOf("actionOnNavigation" to "close", "shareScheme" to "app://share"),
                    "overlay" to mapOf("ui" to "hidden"),
                    "customParameters" to mapOf("k" to "v"),
                    "android" to mapOf(
                        "enterOSPipOnBackPressed" to true, "isVolumeKeyEnabled" to false, "autoResumeOnFocusGained" to false,
                        "isStatusBarVisible" to false, "allowScreenCapture" to false, "closeWhenAppDestroyed" to false,
                    ),
                ),
            ),
        )
        assertEquals(ShoplivePlayerType.PREVIEW, merged.type)
        assertEquals(ShoplivePipPosition.TOP_LEFT, merged.pip.defaultPosition)
        assertEquals(0.5f, merged.pip.scale, 0f)
        assertEquals(ShoplivePipRatio.RATIO_1X1, merged.pip.aspectRatio)
        assertEquals(3, merged.pip.padding.right)
        assertEquals(true, merged.pip.enterOSPipOnBackPressed)
        assertEquals(false, merged.sound.isVolumeKeyEnabled)
        assertEquals(false, merged.sound.autoResumeOnFocusGained)
        assertEquals(0xFF00FF00.toInt(), merged.appearance.indicatorColor)
        assertEquals(false, merged.appearance.isStatusBarVisible)
        assertEquals(false, merged.appearance.allowScreenCapture)
        assertEquals(ShopliveNavigationAction.CLOSE, merged.navigation.actionOnNavigation)
        assertEquals("app://share", merged.navigation.shareScheme)
        assertEquals(false, merged.navigation.closeWhenAppDestroyed)
        assertEquals(mapOf("k" to "v"), merged.customParameters)
    }

    @Test // case: CFG-01, B-03
    fun merge_nullableFields_keyWithNull_isExplicitNull() {
        val start = PlayerMapper.mergeConfiguration(
            ShoplivePlayerConfiguration(),
            Args.of(mapOf("navigation" to mapOf("shareScheme" to "s"), "android" to mapOf("isVolumeKeyEnabled" to true))),
        )
        val cleared = PlayerMapper.mergeConfiguration(
            start,
            Args.of(mapOf("navigation" to mapOf("shareScheme" to null), "android" to mapOf("isVolumeKeyEnabled" to null))),
        )
        assertNull(cleared.navigation.shareScheme)
        assertNull(cleared.sound.isVolumeKeyEnabled)
        val kept = PlayerMapper.mergeConfiguration(start, Args.of(mapOf("navigation" to emptyMap<String, Any>())))
        assertEquals("s", kept.navigation.shareScheme)
    }

    @Test // case: CFG-01, F-04
    fun merge_nonNullFieldWithNull_isInvalid() {
        assertThrows(BridgeArgumentException::class.java) {
            PlayerMapper.mergeConfiguration(ShoplivePlayerConfiguration(), Args.of(mapOf("pip" to mapOf("isInAppPipEnabled" to null))))
        }
        assertThrows(BridgeArgumentException::class.java) {
            PlayerMapper.mergeConfiguration(ShoplivePlayerConfiguration(), Args.of(mapOf("type" to "LIVE")))
        }
    }

    @Test // case: SMV-1749 PIP isDragOutToCloseEnabled 생략/true/false/null/비Boolean
    fun merge_pipDragOutToClose() {
        val base = ShoplivePlayerConfiguration()
        assertEquals(true, base.pip.isDragOutToCloseEnabled) // SDK 기본값 true(3.0.3) — 생략 시 이 값 유지
        val off = PlayerMapper.mergeConfiguration(base, Args.of(mapOf("pip" to mapOf("isDragOutToCloseEnabled" to false))))
        assertEquals(false, off.pip.isDragOutToCloseEnabled)
        val kept = PlayerMapper.mergeConfiguration(off, Args.of(mapOf("pip" to mapOf("isInAppPipEnabled" to true))))
        assertEquals(false, kept.pip.isDragOutToCloseEnabled)
        val on = PlayerMapper.mergeConfiguration(off, Args.of(mapOf("pip" to mapOf("isDragOutToCloseEnabled" to true))))
        assertEquals(true, on.pip.isDragOutToCloseEnabled)
        for (bad in listOf(null, "true", 1)) {
            val e = assertThrows(BridgeArgumentException::class.java) {
                PlayerMapper.mergeConfiguration(base, Args.of(mapOf("pip" to mapOf("isDragOutToCloseEnabled" to bad))))
            }
            assertEquals("isDragOutToCloseEnabled", e.key)
        }
        assertEquals(false, (PlayerMapper.configurationToWire(off)["pip"] as Map<*, *>)["isDragOutToCloseEnabled"])
    }

    @Test // case: SMV-1749 error code 불투명 문자열 그대로(3.0.3 신규 상수 포함), rawCode 상시
    fun errorEvent_passesSdkCodeNameThrough() {
        for (code in ShopliveErrorCode.values()) {
            val wire = PlayerMapper.eventToWire(ShoplivePlayerEvent.Error(ShopliveError(code, 7, null, null, false)))
            assertEquals(mapOf("code" to code.name, "message" to null, "rawCode" to 7, "recoverable" to false), wire["error"])
        }
    }

    @Test // case: CFG-02
    fun configuration_roundTrip_wire() {
        val merged = PlayerMapper.mergeConfiguration(
            ShoplivePlayerConfiguration(),
            Args.of(mapOf("pip" to mapOf("isInAppPipEnabled" to true, "isDragOutToCloseEnabled" to false, "padding" to mapOf("left" to 5)), "customParameters" to mapOf("a" to "b"))),
        )
        val wire = PlayerMapper.configurationToWire(merged)
        val again = PlayerMapper.mergeConfiguration(ShoplivePlayerConfiguration(), Args.of(wire))
        assertEquals(PlayerMapper.configurationToWire(again), wire)
        assertEquals(true, (wire["pip"] as Map<*, *>)["isInAppPipEnabled"])
        assertEquals(5, ((wire["pip"] as Map<*, *>)["padding"] as Map<*, *>)["left"])
        assertEquals(mapOf("a" to "b"), wire["customParameters"])
    }

    // ---- 결과 ----

    @Test // case: N-06
    fun couponResult_requiredAndOptional() {
        val r = PlayerMapper.toCouponResult("c1", Args.of(mapOf("success" to true, "status" to "show")))
        assertEquals("c1", r.couponId)
        assertEquals(true, r.success)
        assertEquals(ShopliveResultStatus.SHOW, r.status)
        assertNull(r.message)
        assertNull(r.alertType)
        val full = PlayerMapper.toCustomActionResult("a1", Args.of(mapOf("success" to false, "status" to "hide", "message" to "m", "alertType" to "alert")))
        assertEquals("a1", full.id)
        assertEquals("m", full.message)
        assertEquals(ShopliveResultAlertType.ALERT, full.alertType)
    }

    @Test // case: N-06
    fun couponResult_missingStatusOrSuccess_isInvalid() {
        assertThrows(BridgeArgumentException::class.java) { PlayerMapper.toCouponResult("c", Args.of(mapOf("success" to true))) }
        assertThrows(BridgeArgumentException::class.java) { PlayerMapper.toCouponResult("c", Args.of(mapOf("status" to "keep"))) }
    }

    // ---- 이벤트 → wire (design §2.5) ----

    @Test // case: N-03
    fun events_allNineTypes() {
        assertEquals(mapOf("type" to "stateChanged", "state" to "playing"), PlayerMapper.eventToWire(ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.PLAYING)))
        assertEquals(mapOf("type" to "campaignStatusChanged", "status" to "live"), PlayerMapper.eventToWire(ShoplivePlayerEvent.CampaignStatusChanged(ShopliveCampaignStatus.LIVE)))
        assertEquals(
            mapOf("type" to "campaignInfoReceived", "campaignKey" to "k", "title" to null, "status" to null),
            PlayerMapper.eventToWire(ShoplivePlayerEvent.CampaignInfoReceived(ShopliveCampaignInfo("k", null, null))),
        )
        assertEquals(mapOf("type" to "connectionStateChanged", "state" to "reconnecting"), PlayerMapper.eventToWire(ShoplivePlayerEvent.ConnectionStateChanged(ShopliveConnectionState.RECONNECTING)))
        assertEquals(
            mapOf("type" to "error", "error" to mapOf("code" to "CONNECTION_ISSUE", "message" to "m", "rawCode" to 3001, "recoverable" to true)),
            PlayerMapper.eventToWire(ShoplivePlayerEvent.Error(ShopliveError(ShopliveErrorCode.CONNECTION_ISSUE, 3001, "m", null, true))),
        )
        assertEquals(
            mapOf(
                "type" to "analytics", "campaignKey" to "k", "isPlaying" to true, "isMuted" to false, "durationMs" to 10L,
                "campaign" to mapOf("title" to "t", "status" to "ended"), "brand" to mapOf("name" to "b", "identifier" to null, "imageUrl" to null),
            ),
            PlayerMapper.eventToWire(
                ShoplivePlayerEvent.Analytics(ShopliveAnalyticsInfo("k", true, false, 10L, ShopliveCampaign("t", ShopliveCampaignStatus.ENDED), ShopliveBrand("b", null, null))),
            ),
        )
        assertEquals(
            mapOf("type" to "webCommandReceived", "name" to "n", "payload" to mapOf("a" to 1L)),
            PlayerMapper.eventToWire(ShoplivePlayerEvent.WebCommandReceived("n", mapOf("a" to 1))),
        )
        assertEquals(
            mapOf("type" to "userNameUpdateRequested", "payload" to mapOf("j" to mapOf("x" to 2L))),
            PlayerMapper.eventToWire(ShoplivePlayerEvent.UserNameUpdateRequested(mapOf("j" to JSONObject().put("x", 2)))),
        )
    }

    @Test // case: N-03
    fun analytics_nullCampaignAndBrand() {
        val w = PlayerMapper.eventToWire(ShoplivePlayerEvent.Analytics(ShopliveAnalyticsInfo("k", false, true, 0L, null, null)))
        assertNull(w["campaign"])
        assertNull(w["brand"])
    }

    @Test // case: N-03
    fun playback_allNineKinds() {
        val cases = listOf(
            ShoplivePlaybackEvent.Requested(1L) to "requested",
            ShoplivePlaybackEvent.Started(1L) to "started",
            ShoplivePlaybackEvent.AudioLoaded(1L) to "audioLoaded",
            ShoplivePlaybackEvent.Rendering(1L) to "rendering",
            ShoplivePlaybackEvent.Buffering(1L) to "buffering",
            ShoplivePlaybackEvent.RebufferingStarted(1L) to "rebufferingStarted",
            ShoplivePlaybackEvent.RebufferingEnded(1L) to "rebufferingEnded",
            ShoplivePlaybackEvent.Ended(null) to "ended",
        )
        for ((e, kind) in cases) {
            val w = PlayerMapper.eventToWire(ShoplivePlayerEvent.Playback(e))
            assertEquals("playback", w["type"])
            assertEquals(kind, w["event"])
            assertEquals(e.timestampMs, w["timestampMs"])
        }
        assertEquals(
            mapOf("type" to "playback", "event" to "failed", "timestampMs" to 5L, "code" to 7, "message" to "x"),
            PlayerMapper.eventToWire(ShoplivePlayerEvent.Playback(ShoplivePlaybackEvent.Failed(5L, 7, "x"))),
        )
    }

    // ---- 요청 → wire ----

    @Test // case: N-04
    fun requests_wire() {
        assertEquals(mapOf("type" to "navigation", "url" to "u"), PlayerMapper.navigationToWire("u"))
        assertEquals(mapOf("type" to "coupon", "requestId" to "r1", "couponId" to "c"), PlayerMapper.couponToWire("r1", "c"))
        assertEquals(
            mapOf("type" to "customWebAction", "requestId" to "r2", "id" to "i", "actionType" to "t", "payload" to mapOf("k" to 1L)),
            PlayerMapper.customWebActionToWire("r2", "i", "t", JSONObject().put("k", 1)),
        )
    }

    @Test // case: N-02
    fun campaign_wire() {
        assertNull(PlayerMapper.campaignToWire(null))
        assertEquals(mapOf("campaignKey" to "k", "title" to "t", "status" to "ready"), PlayerMapper.campaignToWire(ShopliveCampaignInfo("k", "t", ShopliveCampaignStatus.READY)))
    }

    @Test // case: CFG-01
    fun insets_partial_keepsCurrent() {
        val cur = ShoplivePlayerConfiguration().pip.padding
        val merged = PlayerMapper.mergeConfiguration(ShoplivePlayerConfiguration(), Args.of(mapOf("pip" to mapOf("padding" to mapOf("top" to 9)))))
        assertEquals(9, merged.pip.padding.top)
        assertEquals(cur.left, merged.pip.padding.left)
        assertEquals(ShopliveInsets::class.java, merged.pip.padding.javaClass)
    }
}
