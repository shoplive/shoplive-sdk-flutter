// BridgeCore - SDK/Flutter/UIKit independent core of the Shoplive Flutter iOS bridges (DRAFT-flutter-sdk-302-ios design section 5).
// Keep in sync: identical copies in shoplive_core, shoplive_flutter_sample (shoplive_player) and shoplive_streamer ios/Classes/
// (checked by ios-tests/BridgeCoreTests CopySyncTests). Mirrors the Android BridgeSupport.kt rules:
//  - every MethodCall completes exactly once (bridgedCall -> BridgeOutcome)
//  - no sensitive values in messages/logs (method name, error code, type names only)
//  - Args: missing key vs key+null, blank required strings rejected, String keys only
import Foundation

// MARK: - Errors

enum BridgeErrorCode {
    static let invalidArgument = "INVALID_ARGUMENT"
    static let noHostScreen = "NO_HOST_SCREEN"
    static let notRunning = "NOT_RUNNING"
    static let sdkError = "SDK_ERROR"
}

/// Arguments do not match the channel contract. `actual` carries a type/state name only, never the value.
struct BridgeArgumentError: Error, CustomStringConvertible {
    let key: String
    let expected: String
    let actual: String
    var description: String { "\(key): expected \(expected), got \(actual)" }
}

/// Contract state error (NO_HOST_SCREEN, NOT_RUNNING, SDK_ERROR "plugin detached").
struct BridgeStateError: Error {
    let code: String
    let message: String
}

/// Marker for unknown methods -> FlutterMethodNotImplemented.
struct BridgeNotImplemented: Error {}

struct BridgeFailure {
    let code: String
    let message: String?
    let details: [String: Any]?
}

enum BridgeOutcome {
    case success(Any?)
    case failure(BridgeFailure)
    case notImplemented
}

/// Runs a method body and classifies the outcome. Unknown errors become SDK_ERROR with the type name only.
func bridgedCall(_ block: () throws -> Any?) -> BridgeOutcome {
    do {
        return .success(try block())
    } catch is BridgeNotImplemented {
        return .notImplemented
    } catch let e as BridgeArgumentError {
        return .failure(BridgeFailure(code: BridgeErrorCode.invalidArgument, message: e.description,
                                      details: ["key": e.key, "expected": e.expected, "actual": e.actual]))
    } catch let e as BridgeStateError {
        return .failure(BridgeFailure(code: e.code, message: e.message, details: nil))
    } catch {
        let type = String(describing: Swift.type(of: error))
        return .failure(BridgeFailure(code: BridgeErrorCode.sdkError, message: "SDK call failed: \(type)",
                                      details: ["exception": type]))
    }
}

// MARK: - WebURLRule

/// webPageUrl rule. Platform URL parsers decide differently (java.net.URI vs URLComponents/URL, and iOS 15/16 vs 17+),
/// so the decision is this plain string rule only (SMV-1749 R1-01), identical to Android BridgeSupport `WebUrlRule` and
/// checked on both sides with the shared vectors in shoplive_streamer/test/fixtures/http_url_vectors.json:
///  1. non-empty, no space/control character (`isSpaceOrControl`)
///  2. starts with `http://` or `https://` (ASCII case-insensitive)
///  3. no backslash in the authority (before the first `/`, `?` or `#`)
///  4. non-empty host: the authority without userinfo (before the last `@`) and port (after the last `:`;
///     `[IPv6]` keeps everything up to the first `]`)
/// Anything else (non-ASCII path, underscore host, port format, ...) is not judged here and is left to the SDK.
enum WebURLRule {
    static let expected = "http(s) URL without spaces"
    private static let schemes: [[UInt32]] = ["http://", "https://"].map { $0.unicodeScalars.map(\.value) }
    private static let authorityEnd: Set<UInt32> = Set("/?#".unicodeScalars.map(\.value))
    private static let asciiCaseOffset: UInt32 = 0x20

    static func accepts(_ s: String) -> Bool {
        let v = s.unicodeScalars.map(\.value)
        if v.isEmpty || v.contains(where: isSpaceOrControl) { return false }
        guard let scheme = schemes.first(where: { hasASCIIPrefixIgnoringCase(v, $0) }) else { return false }
        let rest = v.dropFirst(scheme.count)
        let authority = Array(rest.prefix { !authorityEnd.contains($0) })
        return !authority.contains(backslash) && !host(authority).isEmpty
    }

    private static let backslash = UInt32(0x5C)
    private static let at = UInt32(0x40)
    private static let colon = UInt32(0x3A)
    private static let openBracket = UInt32(0x5B)
    private static let closeBracket = UInt32(0x5D)

    /// authority -> host: drops userinfo (before the last `@`) and port (after the last `:`); `[`... keeps up to the first `]` (IPv6).
    private static func host(_ authority: [UInt32]) -> ArraySlice<UInt32> {
        let hostPort = authority.lastIndex(of: at).map { authority[($0 + 1)...] } ?? authority[...]
        if hostPort.first == openBracket {
            return hostPort.firstIndex(of: closeBracket).map { hostPort[...$0] } ?? hostPort
        }
        return hostPort.lastIndex(of: colon).map { hostPort[..<$0] } ?? hostPort
    }

    /// C0/DEL/C1 controls + Unicode White_Space, fixed by code point (same list as Android).
    static func isSpaceOrControl(_ cp: UInt32) -> Bool {
        cp <= 0x20 || (0x7F...0x9F).contains(cp) || cp == 0xA0 || cp == 0x1680 || (0x2000...0x200A).contains(cp)
            || cp == 0x2028 || cp == 0x2029 || cp == 0x202F || cp == 0x205F || cp == 0x3000
    }

    /// `prefix` is lowercase ASCII; no Unicode/locale case folding.
    private static func hasASCIIPrefixIgnoringCase(_ v: [UInt32], _ prefix: [UInt32]) -> Bool {
        v.count >= prefix.count && prefix.indices.allSatisfy { i in
            ((0x41...0x5A).contains(v[i]) ? v[i] + asciiCaseOffset : v[i]) == prefix[i]
        }
    }

    /// URL object for an accepted string (the SDK takes a URL; Android passes the string as is). Tries the string,
    /// then a percent-encoded copy (iOS 15/16 do not encode by themselves), then CoreFoundation's lenient parser,
    /// so acceptance never depends on the iOS version.
    static func url(_ s: String) -> URL? { URL(string: s) ?? encodedURL(s) }

    /// The path taken when `URL(string:)` refuses the raw string (always the case for non-ASCII on iOS 15/16).
    static func encodedURL(_ s: String) -> URL? {
        let encoded = percentEncoded(s)
        return URL(string: encoded) ?? URL(dataRepresentation: Data(encoded.utf8), relativeTo: nil, isAbsolute: true)
    }

    /// RFC 3986 unreserved + reserved characters stay; an existing `%XX` stays; everything else (non-ASCII bytes,
    /// quote, angle brackets, backslash, caret, backtick, braces, pipe, a lone `%`) becomes `%XX` of its UTF-8 bytes.
    private static let keep = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=".utf8)

    static func percentEncoded(_ s: String) -> String {
        let bytes = Array(s.utf8)
        var out = [UInt8]()
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == UInt8(ascii: "%"), i + 2 < bytes.count, isHex(bytes[i + 1]), isHex(bytes[i + 2]) {
                out += bytes[i...(i + 2)]
                i += 3
                continue
            }
            if keep.contains(b) { out.append(b) } else { out += Array(String(format: "%%%02X", b).utf8) }
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func isHex(_ b: UInt8) -> Bool {
        (0x30...0x39).contains(b) || (0x41...0x46).contains(b) || (0x61...0x66).contains(b)
    }
}

// MARK: - Args

/// StandardMessageCodec argument map reader. Dart null inside a map arrives as NSNull.
struct Args {
    static let rootKey = "<arguments>"
    private let map: [String: Any]

    private init(_ map: [String: Any]) { self.map = map }

    static func of(_ arguments: Any?, prefix: String = "") throws -> Args {
        guard let arguments = arguments, !(arguments is NSNull) else { return Args([:]) }
        guard let dict = arguments as? [AnyHashable: Any] else {
            throw BridgeArgumentError(key: prefix.isEmpty ? rootKey : prefix, expected: "Map", actual: typeName(arguments))
        }
        var out: [String: Any] = [:]
        for (k, v) in dict {
            guard let key = k.base as? String else {
                throw BridgeArgumentError(key: "\(prefix)<key>", expected: "String", actual: typeName(k.base))
            }
            out[key] = v
        }
        return Args(out)
    }

    var isEmpty: Bool { map.isEmpty }
    func has(_ key: String) -> Bool { map[key] != nil }
    func isNull(_ key: String) -> Bool { map[key] is NSNull }

    private func value(_ key: String) -> Any? {
        guard let v = map[key], !(v is NSNull) else { return nil }
        return v
    }

    private func state(_ key: String) -> String { has(key) ? (isNull(key) ? "null" : Args.typeName(map[key]!)) : "missing" }

    func optString(_ key: String) throws -> String? {
        guard let v = value(key) else { return nil }
        guard let s = v as? String else { throw BridgeArgumentError(key: key, expected: "String", actual: Args.typeName(v)) }
        return s
    }

    /// http(s) web URL (missing/null -> nil). Rejected by `WebURLRule` -> INVALID_ARGUMENT (value never carried).
    func optHttpURL(_ key: String) throws -> URL? {
        guard let raw = try optString(key) else { return nil }
        guard WebURLRule.accepts(raw), let url = WebURLRule.url(raw) else {
            throw BridgeArgumentError(key: key, expected: WebURLRule.expected, actual: "not http(s) URL")
        }
        return url
    }

    /// Required string: missing, null or blank is rejected.
    func requireString(_ key: String) throws -> String {
        guard let s = try optString(key) else { throw BridgeArgumentError(key: key, expected: "non-blank String", actual: state(key)) }
        if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BridgeArgumentError(key: key, expected: "non-blank String", actual: "blank")
        }
        return s
    }

    func optBool(_ key: String) throws -> Bool? {
        guard let v = value(key) else { return nil }
        guard let n = v as? NSNumber, Args.isBoolean(n) else { throw BridgeArgumentError(key: key, expected: "Bool", actual: Args.typeName(v)) }
        return n.boolValue
    }

    func requireBool(_ key: String) throws -> Bool {
        guard let b = try optBool(key) else { throw BridgeArgumentError(key: key, expected: "Bool", actual: state(key)) }
        return b
    }

    func optInt(_ key: String) throws -> Int? {
        guard let v = value(key) else { return nil }
        guard let n = v as? NSNumber, !Args.isBoolean(n), !CFNumberIsFloatType(n) else {
            throw BridgeArgumentError(key: key, expected: "Int", actual: Args.typeName(v))
        }
        return n.intValue
    }

    func optDouble(_ key: String) throws -> Double? {
        guard let v = value(key) else { return nil }
        guard let n = v as? NSNumber, !Args.isBoolean(n) else { throw BridgeArgumentError(key: key, expected: "Double", actual: Args.typeName(v)) }
        return n.doubleValue
    }

    func optArgs(_ key: String) throws -> Args? {
        guard let v = value(key) else { return nil }
        return try Args.of(v, prefix: "\(key).")
    }

    func requireArgs(_ key: String) throws -> Args {
        guard let a = try optArgs(key) else { throw BridgeArgumentError(key: key, expected: "Map", actual: state(key)) }
        return a
    }

    /// Missing -> nil, key+null -> rejected (non-null SDK parameter).
    func optNonNullStringList(_ key: String) throws -> [String]? {
        guard has(key) else { return nil }
        guard let v = value(key) else { throw BridgeArgumentError(key: key, expected: "List<String>", actual: "null") }
        guard let list = v as? [Any] else { throw BridgeArgumentError(key: key, expected: "List<String>", actual: Args.typeName(v)) }
        return try list.enumerated().map { i, e in
            guard let s = e as? String else { throw BridgeArgumentError(key: "\(key)[\(i)]", expected: "String", actual: Args.typeName(e)) }
            return s
        }
    }

    func optList(_ key: String) throws -> [Any]? {
        guard let v = value(key) else { return nil }
        guard let list = v as? [Any] else { throw BridgeArgumentError(key: key, expected: "List", actual: Args.typeName(v)) }
        return list
    }

    /// SDK `[String: Any]` argument. Top-level keys must be String; values are passed through (NSNull kept).
    func optStringKeyMap(_ key: String) throws -> [String: Any]? {
        guard let v = value(key) else { return nil }
        guard let dict = v as? [AnyHashable: Any] else {
            throw BridgeArgumentError(key: key, expected: "Map<String, Any?>", actual: Args.typeName(v))
        }
        var out: [String: Any] = [:]
        for (k, value) in dict {
            guard let s = k.base as? String else { throw BridgeArgumentError(key: "\(key).<key>", expected: "String", actual: Args.typeName(k.base)) }
            out[s] = value
        }
        return out
    }

    func optStringStringMap(_ key: String) throws -> [String: String]? {
        guard let m = try optStringKeyMap(key) else { return nil }
        var out: [String: String] = [:]
        for (k, v) in m {
            guard let s = v as? String else { throw BridgeArgumentError(key: "\(key).\(k)", expected: "String", actual: Args.typeName(v)) }
            out[k] = s
        }
        return out
    }

    /// Wire value (Dart camelCase) -> platform value. Missing -> nil, key+null or unknown -> rejected (value not echoed).
    func optWireEnum<E>(_ key: String, _ table: [String: E]) throws -> E? {
        guard has(key) else { return nil }
        guard let raw = value(key) as? String, let e = table[raw] else {
            throw BridgeArgumentError(key: key, expected: "one of \(table.keys.sorted())", actual: "unknown \(state(key))")
        }
        return e
    }

    func requireWireEnum<E>(_ key: String, _ table: [String: E]) throws -> E {
        guard let e = try optWireEnum(key, table) else { throw BridgeArgumentError(key: key, expected: "one of \(table.keys.sorted())", actual: "missing") }
        return e
    }

    static func isBoolean(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }

    static func typeName(_ v: Any) -> String {
        if let n = v as? NSNumber { return isBoolean(n) ? "Bool" : (CFNumberIsFloatType(n) ? "Double" : "Int") }
        if v is String { return "String" }
        if v is [Any] { return "List" }
        if v is [AnyHashable: Any] { return "Map" }
        if v is NSNull { return "null" }
        return String(describing: type(of: v))
    }
}

let wireUnknown = "unknown"

/// Reverse lookup (platform value -> wire). Values outside the table become "unknown" (Dart maps to the unknown member).
func wireOf<E: Equatable>(_ value: E, _ table: [String: E]) -> String {
    table.first { $0.value == value }?.key ?? wireUnknown
}

// MARK: - ValueNormalizer

/// Native -> Dart payload normalisation (hidden responsibility 11, SMV-1385): NSNumber booleans stay Bool,
/// integral numbers become Int64, other numbers Double, map keys String, nil/NSNull -> NSNull, others -> description.
enum ValueNormalizer {
    static let maxDepth = 32

    static func normalize(_ value: Any?) -> Any { normalize(value, depth: 0) }

    private static func normalize(_ value: Any?, depth: Int) -> Any {
        guard let value = unwrap(value), !(value is NSNull) else { return NSNull() }
        if let n = value as? NSNumber {
            if Args.isBoolean(n) { return n.boolValue }
            return CFNumberIsFloatType(n) ? n.doubleValue : n.int64Value
        }
        if let s = value as? String { return s }
        if let u = value as? URL { return u.absoluteString }
        if let d = value as? Date { return ISO8601DateFormatter().string(from: d) }
        if depth >= maxDepth { return String(describing: value) }
        if let dict = value as? [AnyHashable: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict { out[String(describing: k.base)] = normalize(v, depth: depth + 1) }
            return out
        }
        if let list = value as? [Any] { return list.map { normalize($0, depth: depth + 1) } }
        return String(describing: value)
    }

    /// Flattens Optional<Any> nesting (Any? inside [String: Any?]).
    private static func unwrap(_ value: Any?) -> Any? {
        guard let value = value else { return nil }
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .optional {
            return mirror.children.first.flatMap { unwrap($0.value) }
        }
        return value
    }
}

// MARK: - Scheduling

final class BridgeCancellable {
    private var action: (() -> Void)?
    init(_ action: @escaping () -> Void) { self.action = action }
    func cancel() { action?(); action = nil }
}

protocol MainScheduler: AnyObject {
    func isMainThread() -> Bool
    func post(_ block: @escaping () -> Void)
    func postDelayed(milliseconds: Int, _ block: @escaping () -> Void) -> BridgeCancellable
}

final class DispatchMainScheduler: MainScheduler {
    func isMainThread() -> Bool { Thread.isMainThread }
    func post(_ block: @escaping () -> Void) { DispatchQueue.main.async(execute: block) }
    func postDelayed(milliseconds: Int, _ block: @escaping () -> Void) -> BridgeCancellable {
        let item = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: item)
        return BridgeCancellable { item.cancel() }
    }
}

/// Engine attach generation: completions arriving after detach compare against it (pair #13). Main thread only.
final class AttachGeneration {
    private(set) var current: Int = 0
    @discardableResult func next() -> Int { current += 1; return current }
    func isCurrent(_ generation: Int) -> Bool { generation == current }
}

// MARK: - Events

/// One EventChannel sink: hops to main, drops without a listener, never throws into the SDK.
final class EventEmitter {
    let name: String
    private let scheduler: MainScheduler
    private let onCancelled: () -> Void
    private var sink: ((Any?) -> Void)?

    init(name: String, scheduler: MainScheduler, onCancelled: @escaping () -> Void = {}) {
        self.name = name
        self.scheduler = scheduler
        self.onCancelled = onCancelled
    }

    var hasListener: Bool { sink != nil }

    func listen(_ sink: @escaping (Any?) -> Void) { self.sink = sink }

    /// Dart cancelled the subscription.
    func cancel() {
        sink = nil
        onCancelled()
    }

    /// Engine detach: drop the sink without the cancel side effects.
    func clear() { sink = nil }

    /// - Returns: true if delivered (or scheduled on main), false if dropped.
    @discardableResult func emit(_ event: [String: Any]) -> Bool {
        if !scheduler.isMainThread() {
            scheduler.post { [weak self] in _ = self?.deliver(event) }
            return true
        }
        return deliver(event)
    }

    private func deliver(_ event: [String: Any]) -> Bool {
        guard let sink = sink else { return false }
        sink(event)
        return true
    }
}

// MARK: - Pending requests

/// requestId -> pending SDK request (coupon / custom action). Exactly-once: only the side that `take`s responds.
/// All calls happen on the main thread (MethodChannel, DispatchQueue.main timers, SDK delegate hopped to main).
final class PendingRequests<T> {
    static var defaultTimeoutMs: Int { 10_000 }
    static var minTimeoutMs: Int { 1_000 }
    static var maxTimeoutMs: Int { 120_000 }

    private struct Entry {
        let value: T
        let fallback: (T) -> Void
        let timer: BridgeCancellable
    }

    private let scheduler: MainScheduler
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var seq = 0
    private var timeoutMs = PendingRequests.defaultTimeoutMs

    init(scheduler: MainScheduler) { self.scheduler = scheduler }

    var count: Int { entries.count }

    /// Applies to requests registered afterwards. Range [1000, 120000] ms.
    func setTimeoutMs(_ value: Int) throws {
        guard value >= PendingRequests.minTimeoutMs, value <= PendingRequests.maxTimeoutMs else {
            throw BridgeArgumentError(key: "timeoutMs", expected: "\(PendingRequests.minTimeoutMs)..\(PendingRequests.maxTimeoutMs)", actual: "out of range")
        }
        timeoutMs = value
    }

    func register(_ value: T, fallback: @escaping (T) -> Void) -> String {
        seq += 1
        let id = String(seq)
        let timer = scheduler.postDelayed(milliseconds: timeoutMs) { [weak self] in
            guard let self = self, let taken = self.take(id) else { return }
            fallback(taken)
        }
        entries[id] = Entry(value: value, fallback: fallback, timer: timer)
        order.append(id)
        return id
    }

    func peek(_ id: String) -> T? { entries[id]?.value }

    /// Removes and cancels the timer. nil if already answered (duplicate / expired respond -> false).
    func take(_ id: String) -> T? {
        guard let entry = entries.removeValue(forKey: id) else { return nil }
        order.removeAll { $0 == id }
        entry.timer.cancel()
        return entry.value
    }

    /// Answers every pending request once with its fallback (requests onCancel / engine detach).
    func flushAll() {
        for id in order {
            guard let entry = entries[id], take(id) != nil else { continue }
            entry.fallback(entry.value)
        }
    }
}
