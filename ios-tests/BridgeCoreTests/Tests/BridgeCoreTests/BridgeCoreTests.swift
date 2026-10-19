import Foundation
import XCTest
@testable import BridgeCore

final class FakeScheduler: MainScheduler {
    var onMain = true
    var now = 0
    private var seq = 0
    private var timers: [(id: Int, due: Int, block: () -> Void)] = []
    var posted: [() -> Void] = []
    func isMainThread() -> Bool { onMain }
    func post(_ block: @escaping () -> Void) { posted.append(block) }
    func postDelayed(milliseconds: Int, _ block: @escaping () -> Void) -> BridgeCancellable {
        seq += 1
        let id = seq
        timers.append((id, now + milliseconds, block))
        return BridgeCancellable { [weak self] in self?.timers.removeAll { $0.id == id } }
    }
    var pendingTimers: Int { timers.count }
    func advance(_ ms: Int) {
        now += ms
        while let i = timers.indices.filter({ timers[$0].due <= now }).min(by: { timers[$0].due < timers[$1].due }) {
            let t = timers.remove(at: i)
            t.block()
        }
    }
    func runPosted() { let p = posted; posted = []; p.forEach { $0() } }
}

final class ArgsTests: XCTestCase {
    func testNilArgumentsIsEmpty() throws { XCTAssertTrue(try Args.of(nil).isEmpty) }

    func testNonMapArgumentsIsInvalid() {
        XCTAssertThrowsError(try Args.of("x")) { XCTAssertEqual(($0 as? BridgeArgumentError)?.key, Args.rootKey) }
    }

    func testNonStringKeyRejectedAtAnyLevel() {
        XCTAssertThrowsError(try Args.of([1: "a"] as NSDictionary))
        XCTAssertThrowsError(try Args.of(["p": [2: "b"] as NSDictionary]).optArgs("p"))
    }

    func testRequireStringRejectsMissingNullWrongTypeBlank() {
        XCTAssertThrowsError(try Args.of([String: Any]()).requireString("k"))
        XCTAssertThrowsError(try Args.of(["k": NSNull()]).requireString("k"))
        XCTAssertThrowsError(try Args.of(["k": NSNumber(value: 1)]).requireString("k"))
        XCTAssertThrowsError(try Args.of(["k": "  "]).requireString("k")) { XCTAssertEqual(($0 as? BridgeArgumentError)?.actual, "blank") }
        XCTAssertEqual(try Args.of(["k": "v"]).requireString("k"), "v")
    }

    func testKeyPresenceVsNull() throws {
        let a = try Args.of(["x": NSNull()])
        XCTAssertTrue(a.has("x"))
        XCTAssertTrue(a.isNull("x"))
        XCTAssertFalse(a.has("y"))
        XCTAssertNil(try a.optString("x"))
    }

    // SMV-1385 회귀 방지: NSNumber Bool과 0/1 Int를 구분한다.
    func testBoolVersusIntFromNSNumber() throws {
        let a = try Args.of(["b": NSNumber(value: true), "i": NSNumber(value: 1), "d": NSNumber(value: 1.5)])
        XCTAssertEqual(try a.optBool("b"), true)
        XCTAssertThrowsError(try a.optBool("i"))
        XCTAssertThrowsError(try a.optInt("b"))
        XCTAssertEqual(try a.optInt("i"), 1)
        XCTAssertThrowsError(try a.optInt("d"))
        XCTAssertEqual(try a.optDouble("i"), 1.0)
        XCTAssertEqual(try a.optDouble("d"), 1.5)
        XCTAssertThrowsError(try a.optDouble("b"))
    }

    func testStringListNonNull() throws {
        XCTAssertNil(try Args.of([String: Any]()).optNonNullStringList("l"))
        XCTAssertThrowsError(try Args.of(["l": NSNull()]).optNonNullStringList("l"))
        XCTAssertThrowsError(try Args.of(["l": ["a", 1]]).optNonNullStringList("l"))
        XCTAssertEqual(try Args.of(["l": ["a", "b"]]).optNonNullStringList("l"), ["a", "b"])
    }

    func testStringStringMap() throws {
        XCTAssertEqual(try Args.of(["m": ["a": "b"]]).optStringStringMap("m"), ["a": "b"])
        XCTAssertThrowsError(try Args.of(["m": ["a": 1]]).optStringStringMap("m"))
    }

    func testWireEnumDoesNotEchoValue() {
        XCTAssertThrowsError(try Args.of(["mode": "secretValue"]).optWireEnum("mode", ["fill": 1])) {
            XCTAssertFalse("\($0)".contains("secretValue"))
        }
        XCTAssertThrowsError(try Args.of(["mode": NSNull()]).optWireEnum("mode", ["fill": 1]))
        XCTAssertNil(try Args.of([String: Any]()).optWireEnum("mode", ["fill": 1]))
        XCTAssertEqual(try Args.of(["mode": "fill"]).requireWireEnum("mode", ["fill": 1]), 1)
    }

    // SMV-1749 streamer webPageUrl: missing/null -> nil, non-String -> INVALID_ARGUMENT.
    func testHttpURLOmittedNullWrongType() throws {
        XCTAssertNil(try Args.of([String: Any]()).optHttpURL("u"))
        XCTAssertNil(try Args.of(["u": NSNull()]).optHttpURL("u"))
        XCTAssertThrowsError(try Args.of(["u": NSNumber(value: 1)]).optHttpURL("u")) { XCTAssertEqual(($0 as? BridgeArgumentError)?.key, "u") }
    }

    // SMV-1749 R1-01: same file and expectations as Android StreamerTest.webUrlRule_sharedVectors_matchIos (platform parity).
    // The decision is the string rule only, so the result does not depend on the OS version running this test.
    func testHttpURLSharedVectors() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shoplive_streamer/test/fixtures/http_url_vectors.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let vectors = try XCTUnwrap(root["vectors"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(vectors.count, 50)
        for v in vectors {
            let input = try XCTUnwrap(v["input"] as? String)
            let accept = try XCTUnwrap(v["accept"] as? Bool)
            let args = try Args.of(["u": input])
            if accept {
                // Built URL keeps the original scheme and has a host (also on the iOS 15/16 path where raw URL(string:) is refused).
                let scheme = String(input.prefix { $0 != ":" }).lowercased()
                for url in [try args.optHttpURL("u"), WebURLRule.encodedURL(input)] {
                    let u = try XCTUnwrap(url, input)
                    XCTAssertEqual(u.scheme?.lowercased(), scheme, input)
                    XCTAssertFalse((u.host ?? "").isEmpty, input)
                }
            } else {
                XCTAssertThrowsError(try args.optHttpURL("u"), input) { error in
                    XCTAssertEqual((error as? BridgeArgumentError)?.key, "u")
                    XCTAssertTrue(input.trimmingCharacters(in: .whitespaces).isEmpty || !"\(error)".contains(input), input)
                }
            }
        }
    }

    func testHttpURLKeepsValidURLAndEncodesForOldParsers() throws {
        XCTAssertEqual(try Args.of(["u": "https://shop.example.com/p?id=1"]).optHttpURL("u")?.absoluteString, "https://shop.example.com/p?id=1")
        // percent-encoding used when URL(string:) refuses the raw string (iOS 15/16): non-ASCII -> UTF-8 %XX, %XX kept, lone % encoded
        XCTAssertEqual(WebURLRule.percentEncoded("https://shop.example.com/상품/1?a=%20&b=50%"),
                       "https://shop.example.com/%EC%83%81%ED%92%88/1?a=%20&b=50%25")
        XCTAssertEqual(WebURLRule.percentEncoded("https://e.com/a\\b|{x}"), "https://e.com/a%5Cb%7C%7Bx%7D")
        XCTAssertNotNil(WebURLRule.url("https://example.com:abc/")) // CoreFoundation fallback: accepted like Android
    }

    func testWireOfUnknown() {
        XCTAssertEqual(wireOf(1, ["fill": 1]), "fill")
        XCTAssertEqual(wireOf(2, ["fill": 1]), wireUnknown)
    }
}

final class OutcomeTests: XCTestCase {
    func testOutcomes() {
        if case .success(let v) = bridgedCall({ 1 }) { XCTAssertEqual(v as? Int, 1) } else { XCTFail() }
        if case .notImplemented = bridgedCall({ throw BridgeNotImplemented() }) {} else { XCTFail() }
        if case .failure(let f) = bridgedCall({ throw BridgeArgumentError(key: "k", expected: "String", actual: "Int") }) {
            XCTAssertEqual(f.code, BridgeErrorCode.invalidArgument)
            XCTAssertEqual(f.details?["key"] as? String, "k")
        } else { XCTFail() }
        if case .failure(let f) = bridgedCall({ throw BridgeStateError(code: BridgeErrorCode.notRunning, message: "x") }) {
            XCTAssertEqual(f.code, "NOT_RUNNING")
        } else { XCTFail() }
        struct Secret: Error { let token = "secret-token" }
        if case .failure(let f) = bridgedCall({ throw Secret() }) {
            XCTAssertEqual(f.code, BridgeErrorCode.sdkError)
            XCTAssertFalse((f.message ?? "").contains("secret"))
        } else { XCTFail() }
    }

    func testErrorCodeConstantsMatchContract() {
        XCTAssertEqual([BridgeErrorCode.invalidArgument, BridgeErrorCode.noHostScreen, BridgeErrorCode.notRunning, BridgeErrorCode.sdkError],
                       ["INVALID_ARGUMENT", "NO_HOST_SCREEN", "NOT_RUNNING", "SDK_ERROR"])
    }
}

final class ValueNormalizerTests: XCTestCase {
    func testPrimitivesAndNumbers() {
        XCTAssertEqual(ValueNormalizer.normalize(NSNumber(value: true)) as? Bool, true)
        let i = ValueNormalizer.normalize(NSNumber(value: 1))
        XCTAssertTrue(i is Int64, "\(type(of: i))")
        XCTAssertEqual(ValueNormalizer.normalize(NSNumber(value: 2.5)) as? Double, 2.5)
        XCTAssertEqual(ValueNormalizer.normalize(true) as? Bool, true)
        XCTAssertEqual(ValueNormalizer.normalize(3) as? Int64, 3)
        XCTAssertEqual(ValueNormalizer.normalize("s") as? String, "s")
        XCTAssertTrue(ValueNormalizer.normalize(nil) is NSNull)
        XCTAssertTrue(ValueNormalizer.normalize(NSNull()) is NSNull)
        XCTAssertEqual(ValueNormalizer.normalize(URL(string: "https://a.b/c")!) as? String, "https://a.b/c")
    }

    // SMV-1385: JSONSerialization 결과의 viewerCount(0/1)가 Bool로 바뀌면 안 된다.
    func testJsonSerializationNumbersKeepTypes() throws {
        let json = try JSONSerialization.jsonObject(with: Data(#"{"viewerCount":1,"live":true,"rate":0.5,"n":null}"#.utf8))
        let out = ValueNormalizer.normalize(json) as! [String: Any]
        XCTAssertEqual(out["viewerCount"] as? Int64, 1)
        XCTAssertEqual(out["live"] as? Bool, true)
        XCTAssertEqual(out["rate"] as? Double, 0.5)
        XCTAssertTrue(out["n"] is NSNull)
    }

    func testContainersAndKeys() {
        let out = ValueNormalizer.normalize([1: ["a", [2, 3]], "k": ["n": NSNull()]] as [AnyHashable: Any]) as! [String: Any]
        let list = out["1"] as! [Any]
        XCTAssertEqual(list.first as? String, "a")
        XCTAssertEqual((list.last as! [Any]).compactMap { $0 as? Int64 }, [2, 3])
        XCTAssertTrue((out["k"] as! [String: Any])["n"] is NSNull)
    }

    func testDepthLimit() {
        var nested: Any = "leaf"
        for _ in 0..<(ValueNormalizer.maxDepth + 2) { nested = [nested] }
        var cur: Any? = ValueNormalizer.normalize(nested)
        var depth = 0
        while let l = cur as? [Any] { cur = l.first; depth += 1 }
        XCTAssertTrue(cur is String)
        XCTAssertEqual(depth, ValueNormalizer.maxDepth)
    }

    func testUnknownTypeToString() {
        struct Custom: CustomStringConvertible { var description: String { "custom" } }
        XCTAssertEqual(ValueNormalizer.normalize(Custom()) as? String, "custom")
    }
}

final class EventEmitterTests: XCTestCase {
    func testDropsWithoutSink_deliversOnMain_hopsOffMain_cancelNotifies() {
        let s = FakeScheduler()
        var cancelled = 0
        let e = EventEmitter(name: "ch", scheduler: s, onCancelled: { cancelled += 1 })
        XCTAssertFalse(e.emit(["type": "x"]))
        var got: [Any?] = []
        e.listen { got.append($0) }
        XCTAssertTrue(e.emit(["type": "a"]))
        s.onMain = false
        XCTAssertTrue(e.emit(["type": "b"]))
        XCTAssertEqual(got.count, 1)
        s.onMain = true
        s.runPosted()
        XCTAssertEqual(got.count, 2)
        e.cancel()
        XCTAssertFalse(e.emit(["type": "c"]))
        XCTAssertEqual(cancelled, 1)
        e.listen { got.append($0) }
        e.clear()
        XCTAssertFalse(e.emit(["type": "d"]))
        XCTAssertEqual(cancelled, 1, "clear는 onCancelled를 부르지 않는다")
    }
}

final class PendingRequestsTests: XCTestCase {
    private let s = FakeScheduler()
    private var fallbacks: [String] = []
    private lazy var registry = PendingRequests<String>(scheduler: s)

    private func register(_ v: String) -> String { registry.register(v) { [unowned self] in self.fallbacks.append($0) } }

    func testTimeoutFallbackOnce() {
        _ = register("c1")
        s.advance(PendingRequests<String>.defaultTimeoutMs - 1)
        XCTAssertEqual(fallbacks, [])
        s.advance(1)
        XCTAssertEqual(fallbacks, ["c1"])
        s.advance(PendingRequests<String>.defaultTimeoutMs)
        XCTAssertEqual(fallbacks, ["c1"])
    }

    func testTakeFirstThenTimerNoFallback_andTimerFirstThenTakeNil() {
        let a = register("a")
        XCTAssertEqual(registry.take(a), "a")
        XCTAssertEqual(s.pendingTimers, 0)
        let b = register("b")
        s.advance(PendingRequests<String>.defaultTimeoutMs)
        XCTAssertNil(registry.take(b))
        XCTAssertEqual(fallbacks, ["b"])
        XCTAssertNil(registry.take(a), "중복 take는 nil")
    }

    func testFlushAllOnce_andIdsUnique() {
        let a = register("a"); let b = register("b")
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(registry.peek(a), "a")
        registry.flushAll()
        XCTAssertEqual(Set(fallbacks), ["a", "b"])
        XCTAssertEqual(registry.count, 0)
        XCTAssertEqual(s.pendingTimers, 0)
        registry.flushAll()
        XCTAssertEqual(fallbacks.count, 2)
    }

    func testTimeoutRange() throws {
        for bad in [-5, 0, 999, 120_001] { XCTAssertThrowsError(try registry.setTimeoutMs(bad)) }
        try registry.setTimeoutMs(1_000)
        try registry.setTimeoutMs(120_000)
        _ = register("late")
        s.advance(119_999)
        XCTAssertEqual(fallbacks, [])
        s.advance(1)
        XCTAssertEqual(fallbacks, ["late"])
    }
}

final class AttachGenerationTests: XCTestCase {
    func testGeneration() {
        let g = AttachGeneration()
        let first = g.next()
        XCTAssertTrue(g.isCurrent(first))
        g.next()
        XCTAssertFalse(g.isCurrent(first))
    }
}

/// 3패키지 BridgeCore.swift·BridgeFlutter.swift 사본 동일성(형제 파일이 없으면 실패).
final class CopySyncTests: XCTestCase {
    func testBridgeCopiesAreIdentical() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for (file, packages) in [
            ("BridgeCore.swift", ["shoplive_core", "shoplive_flutter_sample", "shoplive_streamer"]),
            ("BridgeFlutter.swift", ["shoplive_core", "shoplive_flutter_sample", "shoplive_streamer"]),
            ("HostScreen.swift", ["shoplive_flutter_sample", "shoplive_streamer"]),
            ("ShopliveErrorWire.swift", ["shoplive_flutter_sample", "shoplive_streamer"]),
        ] {
            let contents = try packages.map { try String(contentsOf: repo.appendingPathComponent("\($0)/ios/Classes/\(file)"), encoding: .utf8) }
            XCTAssertEqual(Set(contents).count, 1, "\(file) copies differ")
        }
    }
}
