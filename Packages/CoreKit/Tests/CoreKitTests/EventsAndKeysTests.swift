import AinkradClient
import Foundation
import Testing

@testable import CoreKit

private func event(_ seq: Int64, kind: String = "audit") -> [String: Any] {
    ["seq": seq, "at": stamp(1_800_000_000), "kind": kind, "payload": ["n": seq]]
}

@Suite struct EventTests {
    @Test func decodesEventsAndSkipsWhatItCannot() {
        let ok = jsonBody(event(5))
        #expect(EventWire.decode(ok)?.seq == 5)
        #expect(EventWire.decode(Data("{\"seq\":\"x\"}".utf8)) == nil)
        #expect(EventWire.decode(Data("nope".utf8)) == nil)
        #expect(EventWire.decode(jsonBody(["seq": 1, "at": "yesterday", "kind": "k", "payload": [:]])) == nil)
    }

    @Test func closeReasonCarriesTheFloor() {
        #expect(EventWire.floor(fromCloseReason: "past retention, floor 42; re-sync from /api/v1/events/latest") == 42)
        #expect(EventWire.floor(fromCloseReason: "revoked") == nil)
    }

    @Test func terminalErrorsEndTheStream() {
        #expect(EventWire.isTerminal(.revoked) && EventWire.isTerminal(.coreIdentityMismatch(pinned: "a", served: "b")))
        #expect(!EventWire.isTerminal(.offline("x")) && !EventWire.isTerminal(.sessionExpired))
    }

    @Test func replaysInOrderOnceSkippingTheUndecodableThenGoesLiveOrRetries() async throws {
        let h = try Harness()
        // A page with a repeat, a broken event and a gap in the seqs (a re-filtered stream has them).
        h.core.eventPages = [
            ["items": [event(1), event(2), ["seq": "junk"], event(2), event(5)]]
        ]
        let conn = try h.connection()
        var seen: [Int64] = []
        for await update in conn.events(after: 0) {
            if case .event(let e) = update { seen.append(e.seq) }
            // The socket cannot open in this test (nothing listens): the stream says it is retrying.
            if case .reconnecting = update { break }
        }
        #expect(seen == [1, 2, 5])
    }

    @Test func theCursorPassesAnEventThatDoesNotDecode() async throws {
        let h = try Harness()
        let bad: [String: Any] = ["seq": 2, "at": "not a time", "kind": "k", "payload": [:]]
        h.core.eventPages = [["items": [event(1), bad], "next_after": 2], ["items": [event(3)]]]
        let conn = try h.connection()
        var seen: [Int64] = []
        for await update in conn.events(after: 0) {
            if case .event(let e) = update { seen.append(e.seq) }
            if case .reconnecting = update { break }
        }
        #expect(seen == [1, 3])
        let asked = h.core.requests(to: "/api/v1/events?").map(\.target)
        #expect(asked.first?.contains("after=0") == true && asked.dropFirst().first?.contains("after=2") == true)
    }

    @Test func cancellingTheConsumerClosesTheSocket() async throws {
        let h = try Harness()
        let sockets = SocketFactory([.wait])
        let conn = try h.connection(sockets: sockets)
        for await update in conn.events(after: 0) {
            if case .live = update { break }  // the consumer stops: the stream terminates and cancels its task
        }
        for _ in 0..<200 where sockets.sockets.first?.cancelled != true { try await Task.sleep(for: .milliseconds(10)) }
        #expect(sockets.sockets.first?.cancelled == true, "the socket was closed, not left open until the next message")
    }

    @Test func scopeChangedGapsAndResetsTheCursorFromLatest() async throws {
        let h = try Harness()
        h.core.latestSeq = 77
        let sockets = SocketFactory([.closeWith(4003), .wait])
        let conn = try h.connection(sockets: sockets)
        var seen: [String] = []
        var lives = 0
        for await update in conn.events(after: 3) {
            switch update {
            case .gap(let f): seen.append("gap\(f)")
            case .live:
                lives += 1
                if lives == 2 { seen.append("live2") }
            default: break
            }
            if lives == 2 { break }
        }
        #expect(seen == ["gap77", "live2"])
        // Cursors are per scope view: after the change the replay starts from the new view's head, not from 3.
        let asked = h.core.requests(to: "/api/v1/events?").map(\.target)
        #expect(asked.last?.contains("after=77") == true)
    }

    @Test func pastRetentionIsAGapNotAnError() async throws {
        let h = try Harness()
        h.core.fail("/api/v1/events", .init(status: 410, code: "past_retention", extra: ["floor": 40]))
        h.core.eventPages = [["items": [event(41)]]]
        let conn = try h.connection()
        var updates: [String] = []
        for await update in conn.events(after: 3) {
            switch update {
            case .gap(let f): updates.append("gap\(f)")
            case .event(let e): updates.append("e\(e.seq)")
            case .reconnecting: updates.append("r")
            default: break
            }
            if updates.last == "r" { break }
        }
        #expect(updates.prefix(2) == ["gap40", "e41"])
    }

    @Test func aRevokedDeviceEndsTheStream() async throws {
        let h = try Harness()
        h.core.fail("/api/v1/events", .init(status: 401, code: "auth_failed"))
        let conn = try h.connection()
        var ended: CoreError?
        for await update in conn.events(after: 0) { if case .ended(let e) = update { ended = e } }
        #expect(ended == .authFailed)
    }
}

@Suite struct KeyStoreTests {
    @Test func memoryStoreKeepsKeysAndIdentity() throws {
        let store = makeMemoryKeyStore()
        #expect(try store.key(.routine, reason: "") == nil)
        let k = try #require(try store.generateKey(.routine))
        #expect(k.storage == .software && k.spki.count == 91)
        #expect(try store.key(.routine, reason: "")?.spki == k.spki)
        #expect(try store.generateKey(.stepup) == nil, "no Secure Enclave: no step-up key")
        let id = PairedIdentity(deviceID: "d_x", coreFingerprint: "fp", endpoint: URL(string: "http://127.0.0.1:7700")!)
        try store.saveIdentity(id)
        #expect(try store.loadIdentity() == id)
        try store.wipe()
        #expect(try store.key(.routine, reason: "") == nil && (try store.loadIdentity()) == nil)
    }

    @Test func softwareSignaturesAreRawAndVerify() throws {
        let k = try #require(try makeMemoryKeyStore().generateKey(.routine))
        let sig = try k.sign(Data("m".utf8))
        #expect(sig.count == 64)
        #expect(Wire.verify(spki: k.spki, message: Data("m".utf8), signature: sig))
        #expect(!Wire.verify(spki: k.spki, message: Data("n".utf8), signature: sig))
    }

    /// The real Keychain, only when asked (`COREKIT_KEYCHAIN_TEST=1`): it writes and removes throwaway items.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["COREKIT_KEYCHAIN_TEST"] == "1"))
    func keychainRoundTrip() throws {
        let store = makeKeychainKeyStore(
            service: "com.ainkrad.core.corekit.test", namespace: UUID().uuidString, useSecureEnclave: false,
            dataProtectionKeychain: false)
        defer { try? store.wipe() }
        let k = try #require(try store.generateKey(.routine))
        #expect(try store.key(.routine, reason: "")?.spki == k.spki)
        let id = PairedIdentity(deviceID: "d_x", coreFingerprint: "fp", endpoint: URL(string: "https://core.example")!)
        try store.saveIdentity(id)
        #expect(try store.loadIdentity() == id)
        try store.wipe()
        #expect(try store.key(.routine, reason: "") == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["COREKIT_KEYCHAIN_TEST"] == "1"))
    func secureEnclaveWhereTheHardwareAndSigningAllow() throws {
        let store = makeKeychainKeyStore(
            service: "com.ainkrad.core.corekit.test", namespace: UUID().uuidString, dataProtectionKeychain: false)
        defer { try? store.wipe() }
        let k: (any DeviceKey)?
        do { k = try store.generateKey(.routine) } catch {
            // An unsigned test binary has no entitlement for the enclave; the app does.
            print("Secure Enclave key refused here: \(error)")
            return
        }
        let key = try #require(k)
        let sig = try key.sign(Data("m".utf8))
        #expect(Wire.verify(spki: key.spki, message: Data("m".utf8), signature: sig))
    }
}
