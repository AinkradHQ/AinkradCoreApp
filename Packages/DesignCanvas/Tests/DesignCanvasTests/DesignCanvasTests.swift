import Foundation
import Testing

@testable import DesignCanvas

/// A stand-in Core: its own replica, answering step 1 with the diff, relaying updates to the other peers. `drop()` cuts
/// every link (the relays reconnect).
final class FakeCore: DesignSyncChannel, @unchecked Sendable {
    let replica = Engine(doc: "dd_test")!
    private let lock = NSLock()
    private var peers: [UUID: AsyncThrowingStream<DesignSyncMessage, any Error>.Continuation] = [:]
    private var up = true

    func open(doc: String) async throws -> AsyncThrowingStream<DesignSyncMessage, any Error> {
        try lock.withLock {
            guard up else { throw URLError(.notConnectedToInternet) }
            let (s, c) = AsyncThrowingStream<DesignSyncMessage, any Error>.makeStream()
            peers[UUID()] = c
            c.yield(.stateVector(replica.stateVector()!))
            return s
        }
    }

    func send(_ m: DesignSyncMessage, doc: String) async throws {
        lock.withLock {
            switch m {
            case .stateVector(let sv):
                let d = replica.diff(sv)!
                peers.values.forEach { $0.yield(.update(d)) }
            case .update(let u):
                replica.apply(u)
                peers.values.forEach { $0.yield(.update(u)) }
            case .awareness: break
            }
        }
    }

    func setUp(_ on: Bool) {
        lock.withLock {
            up = on
            if !on {
                peers.values.forEach { $0.finish() }
                peers = [:]
            }
        }
    }
}

private func addPage(_ e: Engine, _ id: String) -> Bool {
    e.edit(#"[{"op":"add","id":"\#(id)","type":"page","parent":null,"order":"a","name":"Page"}]"#)
}

@MainActor
private func eventually(_ ok: () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if ok() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return ok()
}

@MainActor
struct DesignSyncTests {
    @Test func twoDevicesConverge() async {
        let core = FakeCore()
        let (a, b) = (Engine(doc: "dd_test")!, Engine(doc: "dd_test")!)
        let ra = DesignSync(engine: a, doc: "dd_test", channel: core)
        let rb = DesignSync(engine: b, doc: "dd_test", channel: core)
        ra.start()
        rb.start()
        #expect(await eventually { ra.connected && rb.connected })
        #expect(addPage(a, "n_aaaaaaaaaaaa"))
        ra.flush()
        #expect(await eventually { b.node("n_aaaaaaaaaaaa") != nil })
        #expect(core.replica.node("n_aaaaaaaaaaaa") != nil)
        ra.stop()
        rb.stop()
    }

    @Test func aSocketTheCoreClosesAtOnceCountsAsUnreachableAndBacksOff() async {
        let core = FakeCore()
        let a = Engine(doc: "dd_test")!
        let ra = DesignSync(engine: a, doc: "dd_test", channel: core)
        core.setUp(false)  // every open fails
        ra.backoff = { _ in 0.02 }
        ra.start()
        #expect(await eventually { ra.unreachable })
        core.setUp(true)
        #expect(await eventually { ra.connected && !ra.unreachable })
        #expect(DesignSync(engine: a, doc: "dd_test", channel: core).backoff(20) == 30)
        ra.stop()
    }

    @Test func reconnectResyncsBothWays() async {
        let core = FakeCore()
        let (a, b) = (Engine(doc: "dd_test")!, Engine(doc: "dd_test")!)
        let ra = DesignSync(engine: a, doc: "dd_test", channel: core)
        let rb = DesignSync(engine: b, doc: "dd_test", channel: core)
        ra.backoff = { _ in 0.05 }
        rb.backoff = { _ in 0.05 }
        ra.start()
        rb.start()
        #expect(await eventually { ra.connected && rb.connected })
        core.setUp(false)
        #expect(await eventually { !ra.connected && !rb.connected })
        // edits on both sides while the link is down: nothing is sent
        #expect(addPage(a, "n_aaaaaaaaaaaa"))
        ra.flush()
        core.replica.edit(#"[{"op":"add","id":"n_cccccccccccc","type":"page","parent":null,"order":"b"}]"#)
        core.setUp(true)
        #expect(await eventually { b.node("n_aaaaaaaaaaaa") != nil && a.node("n_cccccccccccc") != nil })
        #expect(core.replica.node("n_aaaaaaaaaaaa") != nil)
        ra.stop()
        rb.stop()
    }

    @Test func systemRelayNeverSends() async {
        let core = FakeCore()
        let a = Engine(doc: "dd_test")!
        let r = DesignSync(engine: a, doc: "dd_sys", target: .system, channel: core)
        r.start()
        #expect(await eventually { r.connected })
        #expect(addPage(a, "n_aaaaaaaaaaaa"))
        r.flush()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(core.replica.node("n_aaaaaaaaaaaa") == nil)
        r.stop()
    }
}

@MainActor
struct AssetFetcherTests {
    final class Calls: @unchecked Sendable {
        let lock = NSLock()
        var data: [String] = []
        func add(_ s: String) { lock.withLock { data.append(s) } }
        var all: [String] { lock.withLock { data } }
    }

    @Test func fetchesOnlyCheckedAssets() async {
        let ok = String(repeating: "a", count: 64)
        let pending = String(repeating: "b", count: 64)
        let refused = String(repeating: "c", count: 64)
        let font = String(repeating: "d", count: 64)
        let unknown = String(repeating: "e", count: 64)
        let calls = Calls()
        let src = CanvasAssetSource(
            info: { sha in
                switch sha {
                case ok: CanvasAssetInfo(contentType: "image/png", check: .ok)
                case pending: CanvasAssetInfo(contentType: "image/png", check: .pending)
                case refused: CanvasAssetInfo(contentType: "image/png", check: .refused)
                case font: CanvasAssetInfo(contentType: "font/ttf", check: .ok)
                default: nil
                }
            },
            data: { sha in
                calls.add(sha)
                return Data([0x89, 0x50, 0x4e, 0x47])
            })
        let f = AssetFetcher(engine: Engine(doc: "dd_test")!, source: src)
        f.fetch([ok, pending, refused, font, unknown, ok])
        try? await Task.sleep(for: .milliseconds(300))
        #expect(Set(calls.all) == [ok, font])
        #expect(calls.all.count == 2)
    }

    /// #304 review: routing follows the Core's content type, never the asset's kind. A font-kind asset that is a PDF, or an
    /// image-kind asset that is a font, is routed by its type; SVG, PDF, zip and unknown types never reach the engine.
    @Test func routesStrictlyByContentType() {
        func route(_ t: String) -> CanvasAssetInfo.Route { CanvasAssetInfo(contentType: t, check: .ok).route }
        #expect(["font/ttf", "font/otf", "font/woff2"].allSatisfy { route($0) == .font })
        #expect(["image/png", "image/jpeg", "image/gif", "image/webp"].allSatisfy { route($0) == .image })
        let never = [
            "image/svg+xml", "application/pdf", "application/zip", "", "Font/TTF", "font/ttf; x=1", "font/woff",
            "text/html",
        ]
        #expect(never.allSatisfy { route($0) == .none })
    }

    @Test func neverFetchesATypeThatIsNeitherFontNorImage() async {
        let pdf = String(repeating: "f", count: 64)
        let calls = Calls()
        let src = CanvasAssetSource(
            info: { _ in CanvasAssetInfo(contentType: "application/pdf", check: .ok) },
            data: { sha in
                calls.add(sha)
                return Data()
            })
        let f = AssetFetcher(engine: Engine(doc: "dd_test")!, source: src)
        f.fetch([pdf])
        try? await Task.sleep(for: .milliseconds(200))
        #expect(calls.all.isEmpty)
    }
}

@Suite struct EditorQueryTests {
    @Test func treeTokensAndSelectAnswerFromTheEngine() {
        let e = Engine(doc: "dd_q")!
        #expect(addPage(e, "n_aaaaaaaaaaaa"))
        let tree = String(data: e.tree() ?? Data(), encoding: .utf8) ?? ""
        #expect(tree.contains("n_aaaaaaaaaaaa") && tree.contains("page"))
        #expect(e.tokens() != nil)
        #expect(e.select(["n_aaaaaaaaaaaa"]) && e.selection() == ["n_aaaaaaaaaaaa"])
        #expect(
            !e.select(["n_zzzzzzzzzzzz"]) && e.selection() == ["n_aaaaaaaaaaaa"], "an unknown id refuses the whole call"
        )
        #expect(e.select([]) && e.selection().isEmpty)
    }

    @Test func aFreshOutboxIsEmptyAfterTheEditsAreDrained() {
        let e = Engine(doc: "dd_o")!
        #expect(addPage(e, "n_aaaaaaaaaaaa"))
        if case .update(let u) = e.outbox() { #expect(!u.isEmpty) } else { Issue.record("expected an update") }
        #expect(e.outbox() == .empty)
    }
}
