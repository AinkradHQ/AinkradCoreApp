import Foundation

@testable import CoreKit
@testable import Pairing

/// Scripted stand-in for `DevicePairing`.
final class FakeDriver: PairingDriver, @unchecked Sendable {
    var claimResult: Result<PairingClaim, any Error> = .success(FakeDriver.claim)
    var resumeResult: PairingClaim?
    var approvals: [Result<PairingOutcome, any Error>] = [.success(.awaitingConfirmation), .success(.paired)]
    var cancelResult: PairingCancel = .cleared
    private(set) var confirmed = false
    private(set) var claimedWith: (PairingCredential, URL?)?
    private let lock = NSLock()

    static let claim = PairingClaim(
        deviceID: "d_new", pairingID: "p_1", sas: "K7QD-2M9X-R4TB-0W6E",
        coreFingerprint: String(repeating: "A", count: 43))

    func claim(_ credential: PairingCredential, endpoint: URL?) async throws -> PairingClaim {
        claimedWith = (credential, endpoint)
        return try claimResult.get()
    }
    func resume() async throws -> PairingClaim? { resumeResult }
    func confirmSAS() async throws { confirmed = true }
    func awaitApproval() async throws -> PairingOutcome {
        let next = lock.withLock {
            approvals.isEmpty ? Result<PairingOutcome, any Error>.success(.paired) : approvals.removeFirst()
        }
        return try next.get()
    }
    func cancel() async throws -> PairingCancel { cancelResult }
}

/// The Core, as scripted.
final class FakeService: CoreService, @unchecked Sendable {
    let deviceID = "d_me"
    var connectError: (any Error)?
    var stepUpError: (any Error)?
    var deviceList: [DeviceInfo] = []
    var renamed: [String] = []
    var revoked: [String] = []
    var cleared: [String] = []
    var stepUps = 0
    var elevated: Date?

    func connect() async throws { if let connectError { throw connectError } }
    func close() async {}
    var scopes = ["read", "approve", "admin"]
    var aboutError: (any Error)?
    func myScopes() async throws -> [String] { scopes }
    func about() async throws -> CoreAbout {
        if let aboutError { throw aboutError }
        return CoreAbout(
            server: "0.47.1", apiMajor: "v1", apiMinor: 47, build: "ab12cd3", device: "Ahmed's MacBook", scopes: scopes)
    }
    func elevatedUntil() async -> Date? { elevated }
    func stepUp(reason: String) async throws -> Date {
        stepUps += 1
        if let stepUpError { throw stepUpError }
        let until = Date().addingTimeInterval(300)
        elevated = until
        return until
    }
    func devices() async throws -> [DeviceInfo] { deviceList }
    func rename(_ id: String, to name: String) async throws -> DeviceInfo {
        renamed.append(name)
        var d = deviceList.first { $0.id == id }!
        d.name = name
        return d
    }
    func setScopes(_ id: String, _ scopes: [String]) async throws -> DeviceInfo {
        var d = deviceList.first { $0.id == id }!
        d.scopes = scopes
        return d
    }
    func revoke(_ id: String) async throws -> DeviceInfo {
        revoked.append(id)
        var d = deviceList.first { $0.id == id }!
        d.status = "revoked"
        return d
    }
    var refuseCreate = false
    func createPairing(name: String, kind: String, scopes: [String]) async throws -> NewPairing {
        if refuseCreate { throw CoreError.forbiddenScope }
        return NewPairing(id: "p_9", code: "ABCDEFGHJK", qr: nil, expiresAt: Date().addingTimeInterval(300))
    }
    func pairing(_ id: String) async throws -> PairingInfo {
        PairingInfo(
            id: id, status: "claimed", name: "iPhone", kind: "device", platform: "ios", keyStorage: "secure_enclave",
            scopes: ["read"], sas: "AAAA-BBBB-CCCC-DDDD", expiresAt: nil, deviceID: "d_x")
    }
    var pending: [PairingInfo] = []
    func pendingPairings() async throws -> [PairingInfo] { pending }
    func approve(_ id: String, sas: String, scopes: [String]?) async throws -> PairingInfo {
        PairingInfo(
            id: id, status: "approved", name: "iPhone", kind: "device", platform: "ios", keyStorage: nil, scopes: [],
            sas: sas, expiresAt: nil, deviceID: nil)
    }
    func reject(_ id: String) async throws -> PairingInfo { try await pairing(id) }
    func lockouts() async throws -> [LockoutInfo] { [] }
    func clearLockout(_ key: String) async throws { cleared.append(key) }
    func events() -> AsyncStream<ServiceEvent> { AsyncStream { _ in } }

    static func device(_ id: String, _ name: String, scopes: [String] = ["read"]) -> DeviceInfo {
        DeviceInfo(
            id: id, name: name, kind: "device", platform: "macos", keyStorage: "secure_enclave", scopes: scopes,
            status: "active", lastUsed: Date(), createdAt: Date())
    }
}
