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
                case ok: CanvasAssetInfo(isFont: false, check: .ok)
                case pending: CanvasAssetInfo(isFont: false, check: .pending)
                case refused: CanvasAssetInfo(isFont: false, check: .refused)
                case font: CanvasAssetInfo(isFont: true, check: .ok)
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
}
