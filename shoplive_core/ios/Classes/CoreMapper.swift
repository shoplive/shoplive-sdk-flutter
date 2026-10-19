import Foundation
import ShopliveCore

/// Dart wire map -> Shoplive iOS core 3.0.3 types (design section 2.1). Pure functions.
enum CoreMapper {
    static let genderByWire: [String: ShopliveGender] = [
        "male": .male, "female": .female, "neutral": .neutral, "undefined": .undefined,
    ]

    static func toConfiguration(_ args: Args) throws -> ShopliveConfiguration {
        let accessKey = try args.requireString("accessKey")
        let domains = try args.optNonNullStringList("allowedWebViewDomains") ?? []
        let attribution = try args.optArgs("attribution").map(toAttribution)
        // D-3: the iOS SDK has no appVersion (Android 3.0.3 dropped it too). Validate the type, then ignore it.
        if try args.optString("appVersion") != nil {
            bridgeLog("ShopliveCore", "initialize: appVersion is not supported by the iOS SDK and is ignored")
        }
        return ShopliveConfiguration(accessKey: accessKey, allowedWebViewDomains: domains, attribution: attribution)
    }

    private static func toAttribution(_ a: Args) throws -> ShopliveAttribution {
        ShopliveAttribution(
            utmSource: try a.optString("utmSource"),
            utmCampaign: try a.optString("utmCampaign"),
            utmMedium: try a.optString("utmMedium"),
            utmContent: try a.optString("utmContent")
        )
    }

    static func toUser(_ args: Args) throws -> ShopliveUser {
        switch try args.optString("type") {
        case "guest":
            return .guest
        case "token":
            return .token(jwt: try args.requireString("jwt"))
        case "profile":
            let id = try args.requireString("id")
            if args.has("gender"), args.isNull("gender") {
                throw BridgeArgumentError(key: "gender", expected: "one of \(genderByWire.keys.sorted())", actual: "null")
            }
            let gender = try args.optWireEnum("gender", genderByWire) ?? .undefined
            // D-3: the iOS SDK profile has no custom map. Validate the shape, then ignore it.
            if try args.optStringKeyMap("custom") != nil {
                bridgeLog("ShopliveCore", "setUser: profile.custom is not supported by the iOS SDK and is ignored")
            }
            return .profile(id: id, name: try args.optString("name"), age: try args.optInt("age"),
                            gender: gender, rank: try args.optInt("rank"))
        default:
            throw BridgeArgumentError(key: "type", expected: "one of [guest, token, profile]", actual: "unknown")
        }
    }

    static func toStreamToken(_ args: Args) throws -> String { try args.requireString("token") }

    static func toConversionData(_ args: Args) throws -> ShopliveConversionData {
        let products = try args.optList("products").map { list in
            try list.enumerated().map { index, element -> ShopliveConversionProduct in
                guard element is [AnyHashable: Any] else {
                    throw BridgeArgumentError(key: "products[\(index)]", expected: "Map", actual: Args.typeName(element))
                }
                return try toProduct(try Args.of(element, prefix: "products[\(index)]."))
            }
        }
        // TODO(SDP-VERIFY): 요확인 - 빈 products 리스트를 SDK·서버가 정상 처리하는지(변형 없이 전달) · 근거 DRAFT-flutter-sdk-302-ios/B-05 · 자동 통과 금지(실측)
        let custom = try args.optStringKeyMap("custom").map { map -> [String: Any?] in
            map.mapValues { $0 is NSNull ? nil : $0 }
        }
        return ShopliveConversionData(type: try args.optString("type"), products: products,
                                      orderId: try args.optString("orderId"), referrer: try args.optString("referrer"),
                                      custom: custom)
    }

    private static func toProduct(_ a: Args) throws -> ShopliveConversionProduct {
        ShopliveConversionProduct(
            productId: try a.optString("productId"),
            customerProductId: try a.optString("customerProductId"),
            sku: try a.optString("sku"),
            url: try a.optString("url"),
            purchaseQuantity: try a.optInt("purchaseQuantity"),
            purchaseUnitPrice: try a.optDouble("purchaseUnitPrice")
        )
    }
}
