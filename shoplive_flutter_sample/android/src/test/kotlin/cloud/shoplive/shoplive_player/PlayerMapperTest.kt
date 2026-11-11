package cloud.shoplive.shoplive_player

import cloud.shoplive.core.publicsurface.ShopliveError
import cloud.shoplive.core.publicsurface.ShopliveErrorCode
import cloud.shoplive.player.ShopliveAnalyticsInfo
import cloud.shoplive.player.ShopliveCampaignLifecycle
import cloud.shoplive.player.ShopliveCampaignLifecycleStatus
import cloud.shoplive.player.ShopliveCampaignListItem
import cloud.shoplive.player.ShopliveCampaignListRequest
import cloud.shoplive.player.ShopliveCampaignListResponse
import cloud.shoplive.player.ShopliveCampaignMetrics
import cloud.shoplive.player.ShopliveBrand
import cloud.shoplive.player.ShopliveCampaign
import cloud.shoplive.player.ShopliveCampaignInfo
import cloud.shoplive.player.ShopliveCampaignStatus
import cloud.shoplive.player.ShopliveCloseReason
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
import cloud.shoplive.player.ShopliveShareInfo
import cloud.shoplive.player.ShopliveResizeMode
import cloud.shoplive.player.ShopliveResultAlertType
import cloud.shoplive.player.ShopliveResultStatus
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class PlayerMapperTest {

    /** 이름 → drawable 리졸버 대역(JVM 테스트에는 Resources가 없다 — design F7). 기본은 해석 실패. */
    private fun merge(current: ShoplivePlayerConfiguration, partial: Args, drawableId: (String) -> Int? = { null }) =
        PlayerMapper.mergeConfiguration(current, partial, drawableId)

    // ---- wire 테이블: SDK 상수 전부를 덮는다(design §2.3) ----

    @Test // case: B-01, B-02
    fun wireTables_coverAllSdkConstants() {
        fun <E> check(table: Map<String, E>, all: Array<E>) = assertEquals(all.toSet(), table.values.toSet())
        check(PlayerMapper.CLOSE_REASON, ShopliveCloseReason.values()) // case: A4-1 (R-A2) — 사유 테이블이 SDK enum 전체를 덮는다
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
        check(PlayerMapper.CAMPAIGN_LIST_STATUS, ShopliveCampaignListRequest.Status.values()) // case: G-6 (R6-A4)
        check(PlayerMapper.CAMPAIGN_LIST_ORDER, ShopliveCampaignListRequest.Order.values())
    }

    // ---- getCampaigns(SMV-1899 D10) ----

    @Test // case: G-6 (R6-A4) — 요청: 생략은 SDK 기본, statuses·order wire 이름, 32비트 밖·키+null·미지 값 INVALID
    fun campaignListRequest_mapping() {
        assertEquals(ShopliveCampaignListRequest(), PlayerMapper.toCampaignListRequest(null))
        assertEquals(ShopliveCampaignListRequest(), PlayerMapper.toCampaignListRequest(Args.of(mapOf("statuses" to emptyList<String>()))))
        assertEquals(
            ShopliveCampaignListRequest(
                page = 0, size = 100,
                statuses = listOf(ShopliveCampaignListRequest.Status.ONAIR, ShopliveCampaignListRequest.Status.READY, ShopliveCampaignListRequest.Status.ONAIR),
                order = ShopliveCampaignListRequest.Order.ASCENDING,
            ),
            PlayerMapper.toCampaignListRequest(Args.of(mapOf("page" to 0, "size" to 100L, "statuses" to listOf("onAir", "ready", "onAir"), "order" to "ascending"))),
        ) // 보정(page<1·size 범위)과 중복 제거는 SDK 몫 — 브릿지는 그대로 넘긴다
        fun invalidKey(m: Map<String, Any?>): String =
            assertThrows(BridgeArgumentException::class.java) { PlayerMapper.toCampaignListRequest(Args.of(m)) }.key
        assertEquals("statuses[1]", invalidKey(mapOf("statuses" to listOf("ready", "ONAIR"))))
        assertEquals("statuses", invalidKey(mapOf("statuses" to null)))
        assertEquals("page", invalidKey(mapOf("page" to (1L shl 33))))
        assertEquals("size", invalidKey(mapOf("size" to null)))
        assertEquals("order", invalidKey(mapOf("order" to null)))
        assertEquals("order", invalidKey(mapOf("order" to "latest")))
    }

    private fun item(status: ShopliveCampaignLifecycleStatus, metrics: ShopliveCampaignMetrics?, id: Long = 1L) = ShopliveCampaignListItem(
        campaignId = id, campaignKey = "k$id", title = null, description = "d", campaignUrl = "https://u/$id",
        rerun = true, archiveStream = false, privateLive = true, scheduledAt = 1_700_000_000_123L, scheduledEndAt = null, posterUrl = null,
        lifecycle = ShopliveCampaignLifecycle(status, rehearsal = true, startedAt = null, closingAt = 5L, endedAt = null),
        metrics = metrics,
    )

    @Test // case: G-1·G-3·G-4·G-5 (R6-A4) — 응답: 전 필드, 64비트 id, null 그대로, lifecycle 상태 4종 + 미지 값 원문
    fun campaignListResponse_toWire() {
        val wire = PlayerMapper.campaignListToWire(
            ShopliveCampaignListResponse(
                campaigns = listOf(
                    item(ShopliveCampaignLifecycleStatus.OnAir, ShopliveCampaignMetrics(userCount = 1L shl 40, adoreCount = null, showUserCount = false), id = 1L shl 40),
                    item(ShopliveCampaignLifecycleStatus.Unknown("PAUSED"), null),
                ),
                hasMore = true,
            ),
        )
        assertEquals(true, wire["hasMore"])
        val (first, second) = wire["campaigns"] as List<*>
        assertEquals(
            mapOf(
                "campaignId" to (1L shl 40), "campaignKey" to "k${1L shl 40}", "title" to null, "description" to "d", "campaignUrl" to "https://u/${1L shl 40}",
                "rerun" to true, "archiveStream" to false, "privateLive" to true, "scheduledAt" to 1_700_000_000_123L, "scheduledEndAt" to null,
                "posterUrl" to null,
                "lifecycle" to mapOf("status" to "onAir", "rehearsal" to true, "startedAt" to null, "closingAt" to 5L, "endedAt" to null),
                "metrics" to mapOf("userCount" to (1L shl 40), "adoreCount" to null, "showUserCount" to false),
            ),
            first,
        )
        second as Map<*, *>
        assertEquals(mapOf("status" to "unknown", "unknownStatus" to "PAUSED", "rehearsal" to true, "startedAt" to null, "closingAt" to 5L, "endedAt" to null), second["lifecycle"])
        assertNull(second["metrics"])
        assertEquals(true, second.containsKey("metrics"))
        val known = mapOf(
            ShopliveCampaignLifecycleStatus.Reserved to "reserved", ShopliveCampaignLifecycleStatus.Ready to "ready",
            ShopliveCampaignLifecycleStatus.OnAir to "onAir", ShopliveCampaignLifecycleStatus.Closed to "closed",
        )
        for ((status, name) in known) {
            val lifecycle = ((PlayerMapper.campaignListToWire(ShopliveCampaignListResponse(listOf(item(status, null)), false))["campaigns"] as List<*>)[0] as Map<*, *>)["lifecycle"] as Map<*, *>
            assertEquals(name, lifecycle["status"])
            assertEquals(false, lifecycle.containsKey("unknownStatus")) // 원문 키는 unknown일 때만
        }
    }

    @Test // case: R-1 (R6-A1, SMV-1899 D9) — 3.0.6 DEFAULT ↔ wire 'default'(Dart ShopliveResizeMode.auto)
    fun resizeMode_default_roundTripsAsDefaultWire() {
        assertEquals("default", wireOf(ShopliveResizeMode.DEFAULT, PlayerMapper.RESIZE_MODE))
        assertEquals(ShopliveResizeMode.DEFAULT, Args.of(mapOf("mode" to "default")).requireWireEnum("mode", PlayerMapper.RESIZE_MODE))
        assertThrows(BridgeArgumentException::class.java) { Args.of(mapOf("mode" to "auto")).requireWireEnum("mode", PlayerMapper.RESIZE_MODE) }
    }

    @Test // case: C-2 (R6-A7, SMV-1899 D12) — 실행 중 인스턴스 병합은 type을 넣지 않는다(프리뷰 프리셋의 type·mute·overlay 유지)
    fun merge_withoutType_keepsInstanceType() {
        val preview = ShoplivePlayerConfiguration.PREVIEW
        val partial = Args.of(mapOf("type" to "live", "navigation" to mapOf("isCustomShareEnabled" to true)))
        val instance = PlayerMapper.mergeConfiguration(preview, partial, { null }, applyType = false)
        assertEquals(ShoplivePlayerType.PREVIEW, instance.type)
        assertEquals(true, instance.sound.muteOnStart)
        assertEquals(ShopliveOverlayUIMode.HIDDEN, instance.overlay.ui)
        assertEquals(true, instance.navigation.isCustomShareEnabled)
        assertEquals(ShoplivePlayerType.LIVE, merge(preview, partial).type) // 기본(applyType=true)은 type도 병합
    }

    @Test // case: A0-1 (R-A1) — 3.0.4 sealed 상태 6종이 전부 Dart enum name으로(unknown 없음). Closed는 사유와 무관하게 'closed'
    fun stateToWire_allSixStates_notUnknown() {
        assertEquals("idle", PlayerMapper.stateToWire(ShoplivePlayerState.Idle))
        assertEquals("loading", PlayerMapper.stateToWire(ShoplivePlayerState.Loading))
        assertEquals("playing", PlayerMapper.stateToWire(ShoplivePlayerState.Playing))
        assertEquals("paused", PlayerMapper.stateToWire(ShoplivePlayerState.Paused))
        assertEquals("inAppPip", PlayerMapper.stateToWire(ShoplivePlayerState.InAppPIP))
        for (r in ShopliveCloseReason.values()) assertEquals("closed", PlayerMapper.stateToWire(ShoplivePlayerState.Closed(r)))
    }

    @Test // case: B-01
    fun wireNames_areCamelCase() {
        assertEquals("inAppPip", PlayerMapper.stateToWire(ShoplivePlayerState.InAppPIP))
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
        val merged = merge(
            ShoplivePlayerConfiguration(),
            Args.of(mapOf("appearance" to mapOf("indicatorColor" to 0xFF00FF00L))),
        )
        assertEquals(0xFF00FF00.toInt(), merged.appearance.indicatorColor)
        assertEquals(0xFF00FF00L, (PlayerMapper.configurationToWire(merged)["appearance"] as Map<*, *>)["indicatorColor"])
        val signed = merge(ShoplivePlayerConfiguration(), Args.of(mapOf("appearance" to mapOf("indicatorColor" to -16711936))))
        assertEquals(0xFF00FF00.toInt(), signed.appearance.indicatorColor)
        assertThrows(BridgeArgumentException::class.java) {
            merge(ShoplivePlayerConfiguration(), Args.of(mapOf("appearance" to mapOf("indicatorColor" to 0x1_0000_0000L))))
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
        val merged = merge(current, partial)
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
        val first = merge(ShoplivePlayerConfiguration(), Args.of(mapOf("pip" to mapOf("isInAppPipEnabled" to true))))
        val second = merge(first, Args.of(mapOf("overlay" to mapOf("ui" to "hidden"))))
        assertEquals(true, second.pip.isInAppPipEnabled)
        assertEquals(ShopliveOverlayUIMode.HIDDEN, second.overlay.ui)
    }

    @Test // case: CFG-01, CS-03
    fun merge_full_includingAndroidMap() {
        val merged = merge(
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
        assertEquals(true, merged.pip.backPressEntersPip) // case: B-2 (R6-A3) — wire 키는 3.0.3 이름 그대로(SMV-1899 D8 W1)
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
        val start = merge(
            ShoplivePlayerConfiguration(),
            Args.of(mapOf("navigation" to mapOf("shareScheme" to "s"), "android" to mapOf("isVolumeKeyEnabled" to true))),
        )
        val cleared = merge(
            start,
            Args.of(mapOf("navigation" to mapOf("shareScheme" to null), "android" to mapOf("isVolumeKeyEnabled" to null))),
        )
        assertNull(cleared.navigation.shareScheme)
        assertNull(cleared.sound.isVolumeKeyEnabled)
        val kept = merge(start, Args.of(mapOf("navigation" to emptyMap<String, Any>())))
        assertEquals("s", kept.navigation.shareScheme)
    }

    @Test // case: CFG-01, F-04
    fun merge_nonNullFieldWithNull_isInvalid() {
        assertThrows(BridgeArgumentException::class.java) {
            merge(ShoplivePlayerConfiguration(), Args.of(mapOf("pip" to mapOf("isInAppPipEnabled" to null))))
        }
        assertThrows(BridgeArgumentException::class.java) {
            merge(ShoplivePlayerConfiguration(), Args.of(mapOf("type" to "LIVE")))
        }
    }

    @Test // case: A2-4 (R-A5, SMV-1899) navigation.isCustomShareEnabled 생략 유지/true/false/키+null·비Boolean INVALID, toWire 포함
    fun merge_navigationCustomShare() {
        val base = ShoplivePlayerConfiguration()
        assertEquals(false, base.navigation.isCustomShareEnabled) // SDK 기본값 false — 생략 시 이 값 유지
        val on = merge(base, Args.of(mapOf("navigation" to mapOf("isCustomShareEnabled" to true))))
        assertEquals(true, on.navigation.isCustomShareEnabled)
        val kept = merge(on, Args.of(mapOf("navigation" to mapOf("shareScheme" to "s"))))
        assertEquals(true, kept.navigation.isCustomShareEnabled)
        val off = merge(on, Args.of(mapOf("navigation" to mapOf("isCustomShareEnabled" to false))))
        assertEquals(false, off.navigation.isCustomShareEnabled)
        for (bad in listOf(null, "true", 1)) {
            val e = assertThrows(BridgeArgumentException::class.java) {
                merge(on, Args.of(mapOf("navigation" to mapOf("isCustomShareEnabled" to bad))))
            }
            assertEquals("isCustomShareEnabled", e.key)
        }
        assertEquals(true, (PlayerMapper.configurationToWire(on)["navigation"] as Map<*, *>)["isCustomShareEnabled"])
    }

    @Test // case: A3-1·A3-2·A3-3·A3-6 (R-A6, SMV-1899) PIP 버튼 병합 — 리졸버 해석·미해석·생략 유지·키+null 해제·타입 오류, toWire는 isHidden만
    fun merge_pipButtons() {
        val ids = mapOf("app_close" to 101, "app_restore" to 202)
        val resolve: (String) -> Int? = { ids[it] }
        val base = ShoplivePlayerConfiguration()
        assertNull(base.pip.closeButton.imageResId)
        assertEquals(false, base.pip.closeButton.isHidden)
        val set = merge(
            base,
            Args.of(mapOf("pip" to mapOf("closeButton" to mapOf("nativeImageName" to "app_close"), "restoreButton" to mapOf("isHidden" to true, "nativeImageName" to "app_restore")))),
            resolve,
        )
        assertEquals(101, set.pip.closeButton.imageResId)
        assertEquals(false, set.pip.closeButton.isHidden)
        assertEquals(202, set.pip.restoreButton.imageResId) // 숨김과 이미지를 그대로 넘긴다(우선순위는 SDK)
        assertEquals(true, set.pip.restoreButton.isHidden)
        // isHidden만 주면 이미지 유지, 버튼 생략도 유지
        val hidden = merge(set, Args.of(mapOf("pip" to mapOf("closeButton" to mapOf("isHidden" to true)))), resolve)
        assertEquals(101, hidden.pip.closeButton.imageResId)
        assertEquals(true, hidden.pip.closeButton.isHidden)
        assertEquals(202, hidden.pip.restoreButton.imageResId)
        // 미해석·'' → 예외 없이 이미지 없음(이전 이미지도 지움)
        for (name in listOf("missing", "")) {
            val r = merge(set, Args.of(mapOf("pip" to mapOf("closeButton" to mapOf("nativeImageName" to name)))), resolve)
            assertNull(r.pip.closeButton.imageResId)
        }
        // 리졸버가 0을 돌려줘도 미지정(null)으로
        assertNull(merge(base, Args.of(mapOf("pip" to mapOf("closeButton" to mapOf("nativeImageName" to "x")))), { 0 }).pip.closeButton.imageResId)
        // 키+null → 해제(nullable 필드 규칙)
        assertNull(merge(set, Args.of(mapOf("pip" to mapOf("closeButton" to mapOf("nativeImageName" to null)))), resolve).pip.closeButton.imageResId)
        // 타입 오류 → INVALID_ARGUMENT, 보관값 불변은 Bridge.constructing 규칙
        val bad = listOf<Map<String, Any?>>(
            mapOf("closeButton" to null),
            mapOf("closeButton" to "app_close"),
            mapOf("restoreButton" to mapOf("isHidden" to null)),
            mapOf("restoreButton" to mapOf("isHidden" to "yes")),
            mapOf("closeButton" to mapOf("nativeImageName" to 3)),
        )
        for (pip in bad) {
            assertThrows(BridgeArgumentException::class.java) { merge(set, Args.of(mapOf("pip" to pip)), resolve) }
        }
        val wire = PlayerMapper.configurationToWire(hidden)["pip"] as Map<*, *>
        assertEquals(mapOf("isHidden" to true), wire["closeButton"])
        assertEquals(mapOf("isHidden" to true), wire["restoreButton"])
    }

    @Test // case: SMV-1749 PIP isDragOutToCloseEnabled 생략/true/false/null/비Boolean
    fun merge_pipDragOutToClose() {
        val base = ShoplivePlayerConfiguration()
        assertEquals(true, base.pip.isDragOutToCloseEnabled) // SDK 기본값 true(3.0.3) — 생략 시 이 값 유지
        val off = merge(base, Args.of(mapOf("pip" to mapOf("isDragOutToCloseEnabled" to false))))
        assertEquals(false, off.pip.isDragOutToCloseEnabled)
        val kept = merge(off, Args.of(mapOf("pip" to mapOf("isInAppPipEnabled" to true))))
        assertEquals(false, kept.pip.isDragOutToCloseEnabled)
        val on = merge(off, Args.of(mapOf("pip" to mapOf("isDragOutToCloseEnabled" to true))))
        assertEquals(true, on.pip.isDragOutToCloseEnabled)
        for (bad in listOf(null, "true", 1)) {
            val e = assertThrows(BridgeArgumentException::class.java) {
                merge(base, Args.of(mapOf("pip" to mapOf("isDragOutToCloseEnabled" to bad))))
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
        val merged = merge(
            ShoplivePlayerConfiguration(),
            Args.of(mapOf("pip" to mapOf("isInAppPipEnabled" to true, "isDragOutToCloseEnabled" to false, "padding" to mapOf("left" to 5)), "customParameters" to mapOf("a" to "b"))),
        )
        val wire = PlayerMapper.configurationToWire(merged)
        val again = merge(ShoplivePlayerConfiguration(), Args.of(wire))
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
        assertEquals(ShopliveResultAlertType.TOAST, r.alertType) // 생략 = TOAST(iOS와 동일, SMV-1749)
        val full = PlayerMapper.toCustomActionResult("a1", Args.of(mapOf("success" to false, "status" to "hide", "message" to "m", "alertType" to "alert")))
        assertEquals("a1", full.id)
        assertEquals("m", full.message)
        assertEquals(ShopliveResultAlertType.ALERT, full.alertType)
    }

    @Test
    fun resultAlertType_omittedIsToast_invalidRejected() {
        // SMV-1749: 생략만 TOAST(iOS와 동일). 키+null·미지 값은 TOAST로 삼키지 않고 거부한다.
        val base = mapOf("success" to true, "status" to "hide")
        val coupon = { m: Map<String, Any?> -> PlayerMapper.toCouponResult("c", Args.of(base + m)).alertType }
        val custom = { m: Map<String, Any?> -> PlayerMapper.toCustomActionResult("a", Args.of(base + m)).alertType }
        for (build in listOf(coupon, custom)) {
            assertEquals(ShopliveResultAlertType.TOAST, build(emptyMap()))
            assertEquals(ShopliveResultAlertType.TOAST, build(mapOf("alertType" to "toast")))
            assertEquals(ShopliveResultAlertType.ALERT, build(mapOf("alertType" to "alert")))
            assertThrows(BridgeArgumentException::class.java) { build(mapOf("alertType" to null)) }
            assertThrows(BridgeArgumentException::class.java) { build(mapOf("alertType" to "banner")) }
        }
    }

    @Test // case: N-06
    fun couponResult_missingStatusOrSuccess_isInvalid() {
        assertThrows(BridgeArgumentException::class.java) { PlayerMapper.toCouponResult("c", Args.of(mapOf("success" to true))) }
        assertThrows(BridgeArgumentException::class.java) { PlayerMapper.toCouponResult("c", Args.of(mapOf("status" to "keep"))) }
    }

    // ---- 이벤트 → wire (design §2.5) ----

    @Test // case: A4-1·A4-2 (R-A1) — closed일 때만 closeReason 키(3종 = Dart ShopliveCloseReason name), 다른 상태엔 키 없음
    fun stateChanged_closed_carriesCloseReason_only() {
        val expected = mapOf(
            ShopliveCloseReason.USER_ACTION to "userAction",
            ShopliveCloseReason.APP_REQUEST to "appRequest",
            ShopliveCloseReason.ACCESS_KEY_CHANGED to "accessKeyChanged",
        )
        for ((reason, wire) in expected) {
            assertEquals(
                mapOf("type" to "stateChanged", "state" to "closed", "closeReason" to wire),
                PlayerMapper.eventToWire(ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.Closed(reason))),
            )
        }
        for (s in listOf(ShoplivePlayerState.Idle, ShoplivePlayerState.Loading, ShoplivePlayerState.Playing, ShoplivePlayerState.Paused, ShoplivePlayerState.InAppPIP)) {
            assertEquals(false, PlayerMapper.eventToWire(ShoplivePlayerEvent.StateChanged(s)).containsKey("closeReason"))
        }
    }

    @Test // case: A0-2 (R-A4, D4) — 3.0.4 payload 없는 웹 커맨드(null)는 iOS와 같은 {}로(Unknown 아님)
    fun webCommand_nullPayload_isEmptyMap() {
        assertEquals(
            mapOf("type" to "webCommandReceived", "name" to "LOGIN_REQUIRED", "payload" to emptyMap<String, Any?>()),
            PlayerMapper.eventToWire(ShoplivePlayerEvent.WebCommandReceived("LOGIN_REQUIRED", null)),
        )
    }

    @Test // case: N-03
    fun events_allNineTypes() {
        assertEquals(mapOf("type" to "stateChanged", "state" to "playing"), PlayerMapper.eventToWire(ShoplivePlayerEvent.StateChanged(ShoplivePlayerState.Playing)))
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

    @Test // case: A1-3 (R-A3, SMV-1899) shareRequested — 다섯 필드 그대로, 없는 값은 null(키는 항상 실음 — campaignInfoReceived와 같은 관례)
    fun shareRequested_fullAndEmpty() {
        assertEquals(
            mapOf(
                "type" to "shareRequested", "url" to "https://s/1", "campaignKey" to "k", "title" to "t",
                "descriptionText" to "d", "thumbnailUrl" to "https://s/p.png",
            ),
            PlayerMapper.eventToWire(ShoplivePlayerEvent.ShareRequested(ShopliveShareInfo("https://s/1", "k", "t", "d", "https://s/p.png"))),
        )
        assertEquals(
            mapOf("type" to "shareRequested", "url" to null, "campaignKey" to null, "title" to null, "descriptionText" to null, "thumbnailUrl" to null),
            PlayerMapper.eventToWire(ShoplivePlayerEvent.ShareRequested(ShopliveShareInfo())),
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
        val merged = merge(ShoplivePlayerConfiguration(), Args.of(mapOf("pip" to mapOf("padding" to mapOf("top" to 9)))))
        assertEquals(9, merged.pip.padding.top)
        assertEquals(cur.left, merged.pip.padding.left)
        assertEquals(ShopliveInsets::class.java, merged.pip.padding.javaClass)
    }
}
