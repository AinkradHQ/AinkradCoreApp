import CryptoKit
import Foundation
import Testing

@testable import CoreKit

private let loopback = URL(string: "http://127.0.0.1:7700")!

private func pairing(_ core: FakeCore, _ store: any KeyStore) -> DevicePairing {
    DevicePairing(keyStore: store, clock: core.clock) { _ in core }
}

/// A store whose step-up key is a software key (an unsigned test process has no Secure Enclave), to exercise the step-up path.
func storeWithSoftwareStepUp() -> any KeyStore {
    let blobs = MemoryBlobs()
    return StepUpTestStore(base: BlobKeyStore(blobs: blobs, useSecureEnclave: false), blobs: blobs)
}

struct StepUpTestStore: KeyStore {
    let base: BlobKeyStore
    let blobs: MemoryBlobs
    func key(_ role: KeyRole, reason: String) throws -> (any DeviceKey)? { try base.key(role, reason: reason) }
    func generateKey(_ role: KeyRole) throws -> (any DeviceKey)? {
        guard role == .stepup else { return try base.generateKey(role) }
        let k = P256.Signing.PrivateKey()
        try blobs.write("stepup", Data([2]) + k.rawRepresentation)
        return SoftwareKey(key: k)
    }
    func deleteKey(_ role: KeyRole) throws { try base.deleteKey(role) }
    func loadIdentity() throws -> PairedIdentity? { try base.loadIdentity() }
    func saveIdentity(_ i: PairedIdentity) throws { try base.saveIdentity(i) }
    func wipe() throws { try base.wipe() }
}

@Suite struct PairingTests {
    @Test func claimsWithATypedCodeAndComputesTheSASItself() async throws {
        let core = FakeCore(clock: TestClock())
        let store = storeWithSoftwareStepUp()
        let p = pairing(core, store)
        let claim = try await p.claim(try .parse("4dttj-f9nwo"), endpoint: loopback)
        let routine = try #require(try store.key(.routine, reason: ""))
        #expect(claim.sas == Wire.sas(coreSPKI: core.coreSPKI, deviceSPKI: routine.spki, pairingID: claim.pairingID))
        #expect(claim.coreFingerprint == core.coreFP)
        let identity = try #require(try store.loadIdentity())
        #expect(identity.deviceID == claim.deviceID && identity.coreFingerprint == core.coreFP)
        // The claim carried the step-up key and both proofs; the Core verified them.
        #expect(core.stepupSPKI != nil)
        let sent = try #require(core.requests(to: "/pair/claim").first)
        #expect(sent.headers["ainkrad-signature"] == nil, "a claim is not a signed request")
        let body = try #require(try JSONSerialization.jsonObject(with: sent.body) as? [String: String])
        #expect(body["code"] == "4DTTJF9NW0" && body["secret"] == nil && body["key_storage"] == "software")
        #expect(body["platform"] == "macos")
    }

    @Test func claimsWithAQRSecretAndRefusesAnExpiredOne() async throws {
        let core = FakeCore(clock: TestClock(unix: 1000), host: "core.example:8443")
        let secret = Wire.b64(Data(repeating: 9, count: 16))
        let ok = "ainkrad-pair:v1?h=core.example&p=8443&c=\(core.coreFP)&s=\(secret)&e=2000"
        let p = pairing(core, makeMemoryKeyStore())
        _ = try await p.claim(try .parse(ok))
        let body = try #require(
            try JSONSerialization.jsonObject(with: core.requests(to: "/pair/claim").first!.body) as? [String: String])
        #expect(body["secret"] == secret && body["code"] == nil)
        // Expired QR.
        let late = pairing(FakeCore(clock: TestClock(unix: 3000)), makeMemoryKeyStore())
        await #expect(throws: CoreError.pairingExpired) { _ = try await late.claim(try .parse(ok)) }
    }

    @Test func aQRFingerprintThatIsNotTheCoresAborts() async throws {
        let core = FakeCore(clock: TestClock(unix: 1000), host: "core.example:8443")
        let store = makeMemoryKeyStore()
        let wrong = Wire.b64(Data(repeating: 1, count: 32))
        let qr = "ainkrad-pair:v1?h=core.example&p=8443&c=\(wrong)&s=\(Wire.b64(Data(repeating: 9, count: 16)))&e=2000"
        do {
            _ = try await pairing(core, store).claim(try .parse(qr))
            Issue.record("paired")
        } catch {
            guard case CoreError.coreIdentityMismatch = error else {
                Issue.record("\(error)")
                return
            }
        }
        #expect(core.requests(to: "/pair/claim").isEmpty, "nothing claimed")
        #expect(try store.key(.routine, reason: "") == nil && (try store.loadIdentity()) == nil)
    }

    @Test func aSASThatIsNotOursAbortsAndLeavesNothingBehind() async throws {
        let core = FakeCore(clock: TestClock())
        core.pairSASOverride = "AAAA-AAAA-AAAA-AAAA"
        let store = makeMemoryKeyStore()
        await #expect(throws: CoreError.sasMismatch) {
            _ = try await pairing(core, store).claim(try .parse("4DTTJF9NW0"), endpoint: loopback)
        }
        #expect(try store.key(.routine, reason: "") == nil && (try store.loadIdentity()) == nil)
    }

    @Test func aWrongCodeIsPairingFailed() async throws {
        let core = FakeCore(clock: TestClock())
        core.fail("/pair/claim", .init(status: 401, code: "pairing_failed"))
        let store = makeMemoryKeyStore()
        await #expect(throws: CoreError.pairingFailed) {
            _ = try await pairing(core, store).claim(try .parse("4DTTJF9NW0"), endpoint: loopback)
        }
        #expect(try store.key(.routine, reason: "") == nil)
    }

    @Test func pollsUntilActive() async throws {
        let core = FakeCore(clock: TestClock())
        let store = makeMemoryKeyStore()
        let p = pairing(core, store)
        _ = try await p.claim(try .parse("4DTTJF9NW0"), endpoint: loopback)
        core.pairStatus = "pending"
        Task<Void, Never> {
            try? await Task.sleep(for: .milliseconds(20))
            core.pairStatus = "active"
        }
        try await p.awaitApproval()
        let polls = core.requests(to: "/pair/status")
        #expect(polls.count >= 1)
        #expect(polls.allSatisfy { $0.headers["ainkrad-session"] == nil && $0.headers["ainkrad-signature"] != nil })
        #expect(try store.loadIdentity() != nil, "kept")
    }

    @Test func rejectedForgetsTheDevice() async throws {
        let core = FakeCore(clock: TestClock())
        let store = makeMemoryKeyStore()
        let p = pairing(core, store)
        _ = try await p.claim(try .parse("4DTTJF9NW0"), endpoint: loopback)
        core.pairStatus = "rejected"
        await #expect(throws: CoreError.notApproved("rejected")) { try await p.awaitApproval() }
        #expect(try store.loadIdentity() == nil && (try store.key(.routine, reason: "")) == nil)
    }

    @Test func pendingForeverExpires() async throws {
        let core = FakeCore(clock: TestClock())
        let p = pairing(core, makeMemoryKeyStore())
        _ = try await p.claim(try .parse("4DTTJF9NW0"), endpoint: loopback)
        core.pairStatus = "pending"
        await #expect(throws: CoreError.notApproved("expired")) { try await p.awaitApproval(timeout: .seconds(20)) }
    }

    @Test func refusesToPairTwice() async throws {
        let core = FakeCore(clock: TestClock())
        let p = pairing(core, makeMemoryKeyStore())
        _ = try await p.claim(try .parse("4DTTJF9NW0"), endpoint: loopback)
        await #expect(throws: CoreError.self) { _ = try await p.claim(try .parse("4DTTJF9NW0"), endpoint: loopback) }
    }

    @Test func aTypedCodeNeedsTheEndpoint() async throws {
        let p = pairing(FakeCore(clock: TestClock()), makeMemoryKeyStore())
        await #expect(throws: CoreError.self) { _ = try await p.claim(try .parse("4DTTJF9NW0")) }
    }
}

@Suite struct StepUpTests {
    @Test func elevatesWithTheStepUpKey() async throws {
        let core = FakeCore(clock: TestClock())
        let store = storeWithSoftwareStepUp()
        let routine = try #require(try store.generateKey(.routine))
        let stepup = try #require(try store.generateKey(.stepup))
        let identity = PairedIdentity(
            deviceID: "d_stepuptest00000000000000", coreFingerprint: core.coreFP, endpoint: loopback)
        try store.saveIdentity(identity)
        core.register(device: identity.deviceID, spki: routine.spki)
        core.stepupSPKI = stepup.spki
        let conn = CoreConnection(
            identity: identity, endpoint: try CoreEndpoint(loopback), key: routine, keyStore: store, http: core,
            transport: FakeTransport(core: core), urlSession: .shared, clock: core.clock)
        #expect(await conn.elevatedUntil == nil)
        let until = try await conn.stepUp(reason: "test")
        let expected = Int64(core.clock.now().timeIntervalSince1970) + 300
        #expect(abs(Int64(until.timeIntervalSince1970) - expected) <= 1)
        #expect(await conn.elevatedUntil != nil)
    }

    @Test func aDeviceWithoutAStepUpKeyCannotElevate() async throws {
        let h = try Harness()
        let conn = try h.connection()
        await #expect(throws: CoreError.self) { _ = try await conn.stepUp(reason: "test") }
        #expect(h.core.requests(to: "/api/v1/auth/step-up").isEmpty, "nothing was sent")
    }
}
