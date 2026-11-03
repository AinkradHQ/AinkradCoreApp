import Foundation
import Testing

@testable import CoreKit

private func frame(_ kind: String, _ payload: [String: Any]) -> Data {
    jsonBody(["stream_id": 0, "kind": kind, "seq": 0, "payload": payload])
}
private func opened(seq: Int = 0) -> Data {
    frame("control", ["type": "opened", "state": "running", "size": ["rows": 24, "cols": 80], "seq": seq, "pid": 1])
}
private func out(_ text: String) -> Data { frame("output", ["data": Data(text.utf8).base64EncodedString()]) }

/// A scripted terminal socket: frames are pushed in, frames sent are recorded.
private final class ScriptSocket: EventSocket, @unchecked Sendable {
    let lock = NSLock()
    private var queue: [Data] = []
    private var waiter: CheckedContinuation<Data, any Error>?
    private var dead = false
    private(set) var sent: [Data] = []
    var status: Int?
    var code = 0
    var failPing = false
    private(set) var received = 0
    var receivedCount: Int { lock.withLock { received } }

    func push(_ d: Data) {
        let w = lock.withLock { () -> CheckedContinuation<Data, any Error>? in
            if let w = waiter {
                waiter = nil
                received += 1
                return w
            }
            queue.append(d)
            return nil
        }
        w?.resume(returning: d)
    }
    func start() {}
    func ping() async throws { if failPing { throw URLError(.badServerResponse) } }
    func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { c in
            let r = lock.withLock { () -> Result<Data, any Error>? in
                if dead { return .failure(URLError(.networkConnectionLost)) }
                if !queue.isEmpty {
                    received += 1
                    return .success(queue.removeFirst())
                }
                waiter = c
                return nil
            }
            if let r { c.resume(with: r) }
        }
    }
    func send(_ data: Data) async throws { lock.withLock { sent.append(data) } }
    func cancel() { drop(code: 0) }
    func drop(code: Int) {
        let w = lock.withLock { () -> CheckedContinuation<Data, any Error>? in
            self.code = code == 0 ? self.code : code
            dead = true
            defer { waiter = nil }
            return waiter
        }
        w?.resume(throwing: URLError(.networkConnectionLost))
    }
    var closeCode: Int { lock.withLock { code } }
    var closeReason: String { "" }
    var responseStatus: Int? { status }
    var sentKinds: [String] {
        lock.withLock { sent }.compactMap {
            ((try? JSONSerialization.jsonObject(with: $0)) as? [String: Any])?["kind"] as? String
        }
    }
}

private func attached(_ s: ScriptSocket, after: UInt64 = 0) async throws -> TerminalAttachment {
    let h = try Harness()
    let conn = CoreConnection(
        identity: h.identity, endpoint: try CoreEndpoint(h.identity.endpoint), key: h.key, keyStore: h.store,
        http: h.core,
        transport: FakeTransport(core: h.core), makeSocket: { _ in s }, clock: h.clock)
    return try await conn.attachTerminal("t_abc", after: after)
}

@Suite struct TerminalWireTests {
    @Test func decodesTheProtocolFrames() {
        #expect(TerminalFrame.decode(out("hi")) == .output(Data("hi".utf8)))
        #expect(
            TerminalFrame.decode(frame("control", ["type": "snapshot", "seq": 8192, "data": "G1tI"]))
                == .snapshot(seq: 8192, data: Data(base64Encoded: "G1tI")!))
        #expect(
            TerminalFrame.decode(frame("result", ["op": "pty.attach", "terminal": "t", "exit_code": 3]))
                == .exit(code: 3, signal: nil))
        #expect(
            TerminalFrame.decode(frame("result", ["op": "pty.attach", "terminal": "t", "signal": "host_lost"]))
                == .exit(code: nil, signal: "host_lost"))
        #expect(TerminalFrame.decode(frame("heartbeat", [:])) == .unknown)
        #expect(TerminalFrame.decode(frame("control", ["type": "from_the_future"])) == .unknown)
        #expect(TerminalFrame.decode(Data("nope".utf8)) == nil)
        if case .opened(let o)? = TerminalFrame.decode(opened(seq: 4096)) {
            #expect(o.rows == 24 && o.cols == 80 && o.seq == 4096 && o.state == "running")
        } else {
            Issue.record("opened did not decode")
        }
    }

    @Test func creditGoesBackInStepsAndASnapshotMayOverdrawTheWindow() {
        var f = TerminalFlow()
        f.received(TerminalFlow.window * 3)  // a snapshot larger than the window still arrives
        #expect(f.wantsMore)
        f.received(TerminalFlow.window)
        #expect(!f.wantsMore, "past the high-water mark the reader waits")
        #expect(f.drawn(1000) == 0, "small draws are batched")
        #expect(f.drawn(TerminalFlow.grantStep) == 1000 + TerminalFlow.grantStep)
        #expect(f.drawn(TerminalFlow.window * 9) > 0 && f.pending == 0, "never below zero")
        #expect(f.wantsMore)
    }

    @Test func theCursorFollowsBytesAndASnapshotMovesIt() {
        var c = TerminalCursor(after: 100)
        c.apply(.output(Data(count: 28)))
        #expect(c.offset == 128 && !c.repainted)
        c.apply(.snapshot(seq: 9000, data: Data(count: 5)))
        #expect(c.offset == 9000 && c.repainted)
        c.apply(.output(Data(count: 10)))
        #expect(c.offset == 9010)
    }
}

@Suite(.serialized) struct TerminalAttachmentTests {
    @Test func attachesReadsInOrderAndSendsInputResizeSignalAndCredit() async throws {
        let s = ScriptSocket()
        s.push(opened(seq: 4))
        let a = try await attached(s)
        #expect(a.opened.cols == 80)
        s.push(out("ab"))
        s.push(out("cd"))
        var got = Data()
        for await u in a.updates {
            if case .output(let d) = u { got += d }
            if got.count == 4 { break }
        }
        #expect(String(decoding: got, as: UTF8.self) == "abcd")
        #expect(a.cursor == 4)
        a.input(Data("ls\n".utf8))
        a.resize(rows: 30, cols: 100)
        a.signal("INT")
        s.push(out(String(repeating: "y", count: 40 * 1024)))
        for await u in a.updates { if case .output = u { break } }
        a.drawn(4 + 40 * 1024)
        for _ in 0..<100 where s.sentKinds.count < 4 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(s.sentKinds == ["output", "control", "control", "credit"])
        a.detach()
    }

    @Test func aSlowRendererPausesReadingAndDrawingResumesIt() async throws {
        let s = ScriptSocket()
        s.push(opened())
        let a = try await attached(s)
        let chunk = String(repeating: "x", count: 100 * 1024)
        for _ in 0..<6 { s.push(out(chunk)) }
        for _ in 0..<100 where a.pending < TerminalFlow.highWater { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(150))
        let paused = s.receivedCount
        #expect(paused <= 1 + 5, "the reader stopped at the high-water mark")
        #expect(paused < 7, "not every queued frame was read")
        a.drawn(TerminalFlow.highWater)
        for _ in 0..<100 where s.receivedCount < 7 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(s.receivedCount == 7, "drawing frees the reader")
        a.detach()
    }

    @Test func closeCodesSaySoAndDetachEndsOnce() async throws {
        let s = ScriptSocket()
        s.push(opened())
        let a = try await attached(s)
        s.drop(code: 4003)
        var last: TerminalUpdate?
        for await u in a.updates { last = u }
        #expect(last == .closed(.stepUpExpired))
        #expect(TerminalAttachment.close(for: 4001) == .revoked)
        #expect(TerminalAttachment.close(for: 1001) == .dropped)

        let t = ScriptSocket()
        t.push(opened())
        let b = try await attached(t)
        b.detach()
        b.detach()
        var all: [TerminalUpdate] = []
        for await u in b.updates { all.append(u) }
        #expect(all == [.closed(.detached)])
    }

    @Test func exitAndRunnerErrorsArriveAsUpdates() async throws {
        let s = ScriptSocket()
        s.push(opened())
        let a = try await attached(s)
        s.push(frame("result", ["op": "pty.attach", "terminal": "t_abc", "exit_code": 0]))
        s.push(frame("error", ["code": "internal", "message": "x"]))
        var seen: [TerminalUpdate] = []
        for await u in a.updates {
            seen.append(u)
            if seen.count == 2 { break }
        }
        #expect(seen == [.exited(code: 0, signal: nil), .failed(code: "internal", message: "x")])
        a.detach()
    }

    @Test func aRefusedUpgradeIsNamedByItsStatus() async throws {
        // The fake session holds read and admin, no terminal scope: a 403 is then forbidden_scope, not step-up.
        for (status, check) in [
            (403, { (e: CoreError) in e == .forbiddenScope }),
            (404, { (e: CoreError) in if case .http(404, _, _) = e { true } else { false } }),
            (429, { (e: CoreError) in if case .http(429, _, _) = e { true } else { false } }),
        ] {
            let s = ScriptSocket()
            s.failPing = true
            s.status = status
            do {
                _ = try await attached(s)
                Issue.record("attached despite \(status)")
            } catch let e as CoreError { #expect(check(e), "status \(status) gave \(e)") }
        }
    }
}
