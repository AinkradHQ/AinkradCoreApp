import CryptoKit
import Darwin
import Foundation
import Testing

@testable import CoreKit

/// A stand-in for the runner host's local socket: speaks its line protocol on a real Unix socket in a private folder.
final class StubHost: @unchecked Sendable {
    let dir: String
    let path: String
    private let server: Int32
    private let lock = NSLock()
    private var client: Int32 = -1
    private var buffer = Data()
    private(set) var received: [[String: Any]] = []

    init(mode: mode_t = 0o700) throws {
        dir = "/tmp/lt-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: Int(mode)])
        path = dir + "/t_x.local.sock"
        server = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        precondition(ok == 0 && listen(server, 1) == 0)
    }

    deinit {
        Darwin.close(server)
        if client >= 0 { Darwin.close(client) }
        try? FileManager.default.removeItem(atPath: dir)
    }

    func accept() -> Bool {
        var p = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
        guard poll(&p, 1, 5000) > 0 else { return false }
        client = Darwin.accept(server, nil, nil)
        return client >= 0
    }

    func send(_ obj: [String: Any]) {
        var d = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        d.append(0x0A)
        _ = d.withUnsafeBytes { Darwin.write(client, $0.baseAddress, d.count) }
    }

    /// The next message the app sent, waiting up to 5 s.
    func next() -> [String: Any]? {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let i = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<i]
                buffer.removeSubrange(buffer.startIndex...i)
                let o = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
                if let o { lock.withLock { received.append(o) } }
                return o
            }
            var p = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, 200) > 0 else { continue }
            var chunk = [UInt8](repeating: 0, count: 8192)
            let n = Darwin.read(client, &chunk, chunk.count)
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<n])
        }
        return nil
    }

    func hangUp() {
        shutdown(client, SHUT_RDWR)
    }

    /// The Core-side facts for a handshake: challenge out, `auth` in (checked), `authed` + `hello` out.
    func greet(
        challenge: String = "chal-1", next nextChallenge: String = "chal-2", lease: Int = 45_000,
        key: P256.Signing.PublicKey,
        seq: Int = 0
    ) -> [String: Any]? {
        guard accept() else { return nil }
        send(["type": "challenge", "nonce": challenge])
        guard let auth = next(), auth["type"] as? String == "auth", let grant = auth["grant"] as? String,
            let sig = auth["sig"] as? String, let raw = Wire.unb64(sig),
            let signature = try? P256.Signing.ECDSASignature(rawRepresentation: raw),
            key.isValidSignature(
                signature, for: LocalTerminalAttachment.attachMessage(challenge: challenge, grant: grant))
        else { return nil }
        send(["type": "authed", "lease_ms": lease, "challenge": nextChallenge])
        send([
            "type": "hello", "protocol": 1,
            "info": ["id": "t_x", "state": "running", "size": ["rows": 24, "cols": 80], "seq": seq],
        ])
        return auth
    }
}

private struct Grants: Sendable {
    var count = 0
}

private final class Counter: @unchecked Sendable {
    let lock = NSLock()
    var grants = 0
    var releases = 0
    var failure: CoreError?
}

private func source(_ key: P256.Signing.PrivateKey, _ c: Counter, lease: Int = 45) -> LocalGrantSource {
    LocalGrantSource(
        grant: {
            if let f = c.lock.withLock({ c.failure }) { throw f }
            let n = c.lock.withLock { () -> Int in
                c.grants += 1
                return c.grants
            }
            return LocalTerminalGrant(
                terminal: "t_x", runner: "d_r", grant: "grant-\(n)", leaseSecs: lease, socket: "t_x.local.sock")
        },
        sign: { try key.signature(for: $0).rawRepresentation }, release: { c.lock.withLock { c.releases += 1 } })
}

private func firstGrant(_ n: Int = 0, lease: Int = 45) -> LocalTerminalGrant {
    LocalTerminalGrant(terminal: "t_x", runner: "d_r", grant: "grant-\(n)", leaseSecs: lease, socket: "t_x.local.sock")
}

private func b64(_ s: String) -> String { Data(s.utf8).base64EncodedString() }

@Suite(.serialized) struct LocalTerminalTests {
    /// The same bytes the Core's `attach_message` builds (crates/proto/src/v2/local.rs has the twin of this check).
    @Test func theSignedMessageIsTheBytesTheCoreChecks() {
        #expect(
            LocalTerminalAttachment.attachMessage(challenge: "chal", grant: "grant")
                == Data("AINKRAD-LOCAL-ATTACH-V1\nchal\ngrant".utf8))
    }

    @Test func theAppProvesTheDeviceKeyOverTheHostsChallengeAndThenTypesAndReadsLocally() async throws {
        let host = try StubHost()
        let key = P256.Signing.PrivateKey()
        let c = Counter()
        let attach = Task {
            try await LocalTerminalAttachment.open(
                socketPath: host.path, first: firstGrant(), source: source(key, c), after: 0)
        }
        let auth = host.greet(key: key.publicKey)
        #expect(auth?["grant"] as? String == "grant-0")
        let a = try await attach.value
        #expect(a.opened.rows == 24 && a.opened.cols == 80 && a.opened.state == "running")
        #expect(host.next()?["type"] as? String == "attach")

        a.input(Data("ls\n".utf8))
        let typed = host.next()
        #expect(typed?["type"] as? String == "input" && typed?["data"] as? String == b64("ls\n"))
        a.resize(rows: 30, cols: 100)
        let size = host.next()?["size"] as? [String: Int]
        #expect(size == ["rows": 30, "cols": 100])

        var it = a.updates.makeAsyncIterator()
        host.send(["type": "out", "seq": 0, "data": b64("hello")])
        #expect(await it.next() == .output(Data("hello".utf8)))
        // A replay that overlaps what was already seen is trimmed, never drawn twice.
        host.send(["type": "out", "seq": 3, "data": b64("lo world")])
        #expect(await it.next() == .output(Data(" world".utf8)))
        #expect(a.cursor == 11)
        host.send(["type": "snapshot", "seq": 50, "data": b64("screen")])
        #expect(await it.next() == .snapshot(Data("screen".utf8)))
        #expect(a.cursor == 50 && a.repainted)
        host.send(["type": "exit", "exit": ["code": 3]])
        #expect(await it.next() == .exited(code: 3, signal: nil))

        a.detach()
        #expect(await it.next() == .closed(.detached))
        try await Task.sleep(for: .milliseconds(100))
        #expect(c.lock.withLock { c.releases } == 1)
    }

    @Test func aHostThatRefusesTheGrantThrowsAndNoKeyOfAnotherDeviceIsAccepted() async throws {
        let host = try StubHost()
        let key = P256.Signing.PrivateKey()
        let attach = Task {
            try await LocalTerminalAttachment.open(
                socketPath: host.path, first: firstGrant(), source: source(key, Counter()), after: 0)
        }
        #expect(host.accept())
        host.send(["type": "challenge", "nonce": "c"])
        #expect(host.next()?["type"] as? String == "auth")
        host.send(["type": "error", "message": "the grant was already used"])
        host.hangUp()
        await #expect(throws: LocalPathError.refused("the grant was already used")) { try await attach.value }
    }

    @Test func anUnsafeOrMissingSocketIsUnavailableNotAnError() async throws {
        let key = P256.Signing.PrivateKey()
        await #expect(throws: LocalPathError.self) {
            try await LocalTerminalAttachment.open(
                socketPath: "/tmp/no-such-dir-\(UUID().uuidString)/t.local.sock", first: firstGrant(),
                source: source(key, Counter()),
                after: 0)
        }
        // The folder is open to the group: the app does not send a keystroke into it.
        let open = try StubHost(mode: 0o755)
        await #expect(throws: LocalPathError.unavailable("the terminal folder is not private to this user")) {
            try await LocalTerminalAttachment.open(
                socketPath: open.path, first: firstGrant(), source: source(key, Counter()), after: 0)
        }
        // A host that never speaks: timed out, not hung.
        let quiet = try StubHost()
        let attach = Task {
            try await LocalTerminalAttachment.open(
                socketPath: quiet.path, first: firstGrant(), source: source(key, Counter()), after: 0)
        }
        #expect(quiet.accept())
        await #expect(throws: LocalPathError.timedOut) { try await attach.value }
    }

    @Test func theLeaseIsRenewedWithAFreshGrantSignedOverTheNewChallenge() async throws {
        let host = try StubHost()
        let key = P256.Signing.PrivateKey()
        let c = Counter()
        // A 3-second lease renews every second.
        let attach = Task {
            try await LocalTerminalAttachment.open(
                socketPath: host.path, first: firstGrant(lease: 3), source: source(key, c, lease: 3), after: 0)
        }
        _ = host.greet(lease: 3000, key: key.publicKey)
        let a = try await attach.value
        _ = host.next()  // attach
        let renew = host.next()
        #expect(renew?["type"] as? String == "auth" && renew?["grant"] as? String == "grant-1")
        let sig = try P256.Signing.ECDSASignature(
            rawRepresentation: Wire.unb64(renew?["sig"] as? String ?? "") ?? Data())
        #expect(
            key.publicKey.isValidSignature(
                sig, for: LocalTerminalAttachment.attachMessage(challenge: "chal-2", grant: "grant-1")))
        a.detach()
    }

    @Test func aCoreThatStopsGrantingEndsTheAttachmentTheWayTheSocketsCloseCodesDo() async throws {
        let host = try StubHost()
        let key = P256.Signing.PrivateKey()
        let c = Counter()
        let attach = Task {
            try await LocalTerminalAttachment.open(
                socketPath: host.path, first: firstGrant(lease: 3), source: source(key, c, lease: 3), after: 0)
        }
        _ = host.greet(lease: 3000, key: key.publicKey)
        let a = try await attach.value
        c.lock.withLock { c.failure = .stepUpRequired }
        var last: TerminalUpdate?
        for await u in a.updates { last = u }
        #expect(last == .closed(.stepUpExpired))
    }

    @Test func aDroppedSocketEndsWithDroppedAndKeepsTheCursorToReattachFrom() async throws {
        let host = try StubHost()
        let key = P256.Signing.PrivateKey()
        let attach = Task {
            try await LocalTerminalAttachment.open(
                socketPath: host.path, first: firstGrant(), source: source(key, Counter()), after: 10)
        }
        _ = host.greet(key: key.publicKey, seq: 10)
        let a = try await attach.value
        host.send(["type": "out", "seq": 10, "data": b64("abc")])
        var it = a.updates.makeAsyncIterator()
        _ = await it.next()
        host.hangUp()
        #expect(await it.next() == .closed(.dropped))
        #expect(a.cursor == 13)
    }
}
