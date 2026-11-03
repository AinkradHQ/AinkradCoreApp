import AinkradClient
import CryptoKit
import Foundation
import Testing

@testable import CoreKit

// Against a real local Core with a runner that offers `pty`, only when `CORE_IT=1` and `CORE_IT_TERMINALS=1`.
// `scripts/app-it.sh terminals` starts the Core and the runner, makes a pairing code and approves the check code this test
// writes to CORE_IT_SAS_FILE. Do not run it by hand.

private let env = ProcessInfo.processInfo.environment
/// Progress lines go to a file too: Swift Testing holds a child's output until the run ends, and a hung run never ends.
private func say(_ s: String) {
    print(s)
    guard let path = env["CORE_IT_PROGRESS"], let h = FileHandle(forWritingAtPath: path) else { return }
    h.seekToEndOfFile()
    h.write(Data((s + "\n").utf8))
    try? h.close()
}
private func need(_ name: String) throws -> String { try #require(env[name], "\(name) is not set") }

/// Collects what an attachment says, for `until`.
private final class Screen: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    private var ended: TerminalUpdate?
    var text: String { lock.withLock { String(decoding: bytes, as: UTF8.self) } }
    var last: TerminalUpdate? { lock.withLock { ended } }
    func take(_ a: TerminalAttachment) -> Task<Void, Never> {
        Task {
            for await u in a.updates {
                switch u {
                case .output(let d), .snapshot(let d):
                    lock.withLock { bytes += d }
                    a.drawn(d.count)
                default: lock.withLock { ended = u }
                }
            }
        }
    }
}

private func until(_ seconds: Int = 20, _ ok: @Sendable () -> Bool) async -> Bool {
    for _ in 0..<(seconds * 20) where !ok() { try? await Task.sleep(for: .milliseconds(50)) }
    return ok()
}

/// The memory store plus a software step-up key (the real one is Touch ID): the live test elevates without a person.
private struct SoftStepUp: DeviceKey {
    let key = P256.Signing.PrivateKey()
    var storage: KeyStorage { .software }
    var spki: Data { key.publicKey.derRepresentation }
    func sign(_ message: Data) throws -> Data { try key.signature(for: message).rawRepresentation }
}

private final class SoftStore: KeyStore, @unchecked Sendable {
    let base = makeMemoryKeyStore()
    private let lock = NSLock()
    private var stepup: SoftStepUp?
    func key(_ role: KeyRole, reason: String) throws -> (any DeviceKey)? {
        role == .stepup ? lock.withLock { stepup } : try base.key(role, reason: reason)
    }
    func generateKey(_ role: KeyRole) throws -> (any DeviceKey)? {
        guard role == .stepup else { return try base.generateKey(role) }
        let k = SoftStepUp()
        lock.withLock { stepup = k }
        return k
    }
    func deleteKey(_ role: KeyRole) throws {
        if role == .stepup { lock.withLock { stepup = nil } } else { try base.deleteKey(role) }
    }
    func loadIdentity() throws -> PairedIdentity? { try base.loadIdentity() }
    func saveIdentity(_ identity: PairedIdentity) throws { try base.saveIdentity(identity) }
    func loadPending() throws -> PendingPairing? { try base.loadPending() }
    func savePending(_ pending: PendingPairing) throws { try base.savePending(pending) }
    func clearPending() throws { try base.clearPending() }
    func wipe() throws { try base.wipe() }
}

@Suite(.serialized) struct LiveTerminalTests {
    @Test(.enabled(if: env["CORE_IT"] == "1" && env["CORE_IT_TERMINALS"] == "1"))
    func opensEchoesDetachesReattachesAndCloses() async throws {
        let url = try #require(URL(string: try need("CORE_IT_URL")))
        let store = SoftStore()
        let pairing = DevicePairing(keyStore: store)
        let claim = try await pairing.claim(try .parse(try need("CORE_IT_CODE")), endpoint: url)
        try claim.sas.write(toFile: try need("CORE_IT_SAS_FILE"), atomically: true, encoding: .utf8)
        try await pairing.confirmSAS()
        try await pairing.awaitApproval(timeout: .seconds(55))
        say("IT paired")
        let conn = try CoreConnection.open(keyStore: store)
        try await conn.connect()
        say("IT connected")

        // Elevated (Touch ID stands in as the software step-up key), then a terminal on the runner.
        _ = try await conn.stepUp(reason: "live test")
        say("IT elevated")
        let runners = try await conn.client.listRunners().ok.body.json
        let runner = try #require(
            runners.first { $0.online == true && ($0.drivers ?? []).contains { $0.name == "pty" } })
        say("IT runner \(runner.id) \(runner.name) drivers=\((runner.drivers ?? []).map { $0.name ?? "?" })")
        // The runner starts a host process per terminal: under load that can take longer than the Core waits (503), so retry.
        var created: Components.Schemas.Terminal?
        for _ in 0..<4 where created == nil {
            let r = try await conn.client.createTerminal(
                body: .json(.init(runner: runner.id, size: .init(cols: 100, rows: 30))))
            if case .created(let c) = r { created = try c.body.json } else { try await Task.sleep(for: .seconds(2)) }
        }
        let made = try #require(created, "a terminal was opened")
        let id = made.id
        say("IT terminal \(id) status=\(made.status.value1?.rawValue ?? made.status.value2 ?? "?")")

        // Attach, echo, see it.
        let first = try await conn.attachTerminal(id)
        print(
            "IT opened size=\(first.opened.cols)x\(first.opened.rows) seq=\(first.opened.seq) state=\(first.opened.state)"
        )
        let screen1 = Screen()
        let reader1 = screen1.take(first)
        first.input(Data("echo live-$((40+2))-ok\n".utf8))
        #expect(
            await until { screen1.text.contains("live-42-ok\r\n") }, "the echo came back: \(screen1.text.suffix(200))")
        let seenAt = first.cursor
        say("IT first screen \(screen1.text.count) bytes, cursor=\(seenAt)")

        // Detach: the terminal keeps running; it is still listed running with nobody attached.
        first.detach()
        _ = await reader1.value
        #expect(screen1.last == .closed(.detached))
        try await Task.sleep(for: .milliseconds(600))
        let after = try await conn.client.getTerminal(path: .init(id: id)).ok.body.json
        #expect((after.status.value1?.rawValue ?? "") == "running")
        #expect((after.attached ?? 0) == 0, "detached: no one attached")

        // Reattach from the byte it had: no repeat of what it saw, and typing still works.
        let again = try await conn.attachTerminal(id, after: seenAt)
        let screen2 = Screen()
        let reader2 = screen2.take(again)
        again.input(Data("echo again-$((50+5))-ok\n".utf8))
        #expect(
            await until { screen2.text.contains("again-55-ok\r\n") },
            "typing after reattach: \(screen2.text.suffix(200))")
        #expect(!screen2.text.contains("live-42-ok\r\n"), "resumed after the last byte: nothing replayed twice")
        again.detach()
        _ = await reader2.value

        // A fresh attach replays the history (or repaints it): both earlier lines are there.
        let fresh = try await conn.attachTerminal(id)
        let screen3 = Screen()
        let reader3 = screen3.take(fresh)
        #expect(
            await until { screen3.text.contains("live-42-ok") && screen3.text.contains("again-55-ok") },
            "history: \(screen3.text.suffix(300))")
        say("IT fresh attach got \(screen3.text.count) bytes, repainted=\(fresh.repainted)")

        // Resize and a signal over the socket, then close from the API: the child ends and the terminal is exited.
        fresh.resize(rows: 40, cols: 120)
        try await conn.client.signalTerminal(path: .init(id: id), body: .json(.init(signal: "WINCH"))).noContent
        let done = try await conn.client.closeTerminal(path: .init(id: id)).ok.body.json
        #expect(
            await until(30) {
                if case .exited? = screen3.last { true } else if case .closed? = screen3.last { true } else { false }
            }, "the socket ended after close")
        reader3.cancel()
        let status = done.status.value1?.rawValue ?? done.status.value2 ?? "?"
        say("IT closed: status=\(status) exit=\(String(describing: done.exitCode)) signal=\(done.exitSignal ?? "-")")
        #expect(["exited", "reaped"].contains(status))
        fresh.detach()
        await conn.close()
    }
}
