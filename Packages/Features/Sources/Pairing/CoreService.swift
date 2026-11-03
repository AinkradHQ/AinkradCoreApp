import AinkradClient
import CoreKit
import Foundation
import OpenAPIRuntime

/// What the Devices, Add device and Lockouts screens know of a device.
struct DeviceInfo: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var kind: String
    var platform: String?
    var keyStorage: String?
    var scopes: [String]
    var status: String
    var lastUsed: Date?
    var createdAt: Date
    /// The device's routine key fingerprint, as the Core lists it.
    var fingerprint: String?
    /// Whether it has a step-up key (the Core's field; nil when the Core does not say).
    var stepup: Bool?
    var revoked: Bool { status == "revoked" || status == "rejected" }
}

/// A pairing as its approver sees it (`PairingView`).
struct PairingInfo: Equatable, Sendable {
    let id: String
    var status: String
    var name: String?
    var kind: String?
    var platform: String?
    var keyStorage: String?
    var scopes: [String]
    var sas: String?
    var expiresAt: Date?
    var deviceID: String?
}

struct NewPairing: Equatable, Sendable {
    let id: String
    let code: String
    let qr: String?
    let expiresAt: Date?
}

struct LockoutInfo: Identifiable, Equatable, Sendable {
    var id: String { key }
    let key: String
    let lockedUntil: Date
    let strikes: Int
}

/// The event stream, reduced to what these screens act on.
enum ServiceEvent: Sendable, Equatable {
    case live, reconnecting, gap
    case ended(CoreError)
    case event(kind: String, pairingID: String?, deviceID: String?)
}

/// The Core as the pairing screens use it. `LiveCoreService` is the only real one; tests bring their own.
protocol CoreService: Sendable {
    var deviceID: String { get }
    func connect() async throws
    func close() async
    /// The scopes this device holds (a new device can never be given more).
    func myScopes() async throws -> [String]
    func elevatedUntil() async -> Date?
    func stepUp(reason: String) async throws -> Date
    func devices() async throws -> [DeviceInfo]
    func rename(_ id: String, to name: String) async throws -> DeviceInfo
    func setScopes(_ id: String, _ scopes: [String]) async throws -> DeviceInfo
    func revoke(_ id: String) async throws -> DeviceInfo
    func createPairing(name: String, kind: String, scopes: [String]) async throws -> NewPairing
    func pairing(_ id: String) async throws -> PairingInfo
    func approve(_ id: String, sas: String, scopes: [String]?) async throws -> PairingInfo
    func reject(_ id: String) async throws -> PairingInfo
    func lockouts() async throws -> [LockoutInfo]
    func clearLockout(_ key: String) async throws
    func events() -> AsyncStream<ServiceEvent>
}

struct LiveCoreService: CoreService {
    let connection: CoreConnection
    var deviceID: String { connection.identity.deviceID }
    private var client: Client { connection.client }

    func connect() async throws { try await connection.connect() }
    func close() async { await connection.close() }
    func myScopes() async throws -> [String] { try await connection.session().scopes }
    func elevatedUntil() async -> Date? { await connection.elevatedUntil }
    func stepUp(reason: String) async throws -> Date { try await connection.stepUp(reason: reason) }

    func devices() async throws -> [DeviceInfo] {
        try await run { try await client.listDevices().ok.body.json.map(Self.device) }
    }

    func rename(_ id: String, to name: String) async throws -> DeviceInfo {
        try await run {
            switch try await client.renameDevice(path: .init(id: id), body: .json(.init(name: name))) {
            case .ok(let o): return Self.device(try o.body.json)
            case .badRequest(let r): throw Self.fail(r)
            case .notFound(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            default: throw Self.unknown
            }
        }
    }

    func setScopes(_ id: String, _ scopes: [String]) async throws -> DeviceInfo {
        try await run {
            switch try await client.setDeviceScopes(path: .init(id: id), body: .json(.init(scopes: scopes))) {
            case .ok(let o): return Self.device(try o.body.json)
            case .badRequest(let r): throw Self.fail(r)
            case .notFound(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            default: throw Self.unknown
            }
        }
    }

    func revoke(_ id: String) async throws -> DeviceInfo {
        try await run {
            switch try await client.revokeDevice(path: .init(id: id)) {
            case .ok(let o): return Self.device(try o.body.json)
            case .notFound(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            default: throw Self.unknown
            }
        }
    }

    func createPairing(name: String, kind: String, scopes: [String]) async throws -> NewPairing {
        try await run {
            switch try await client.createPairing(body: .json(.init(kind: kind, name: name, scopes: scopes))) {
            case .ok(let o):
                let p = try o.body.json
                guard let id = p.pairingId, let code = p.code else {
                    throw CoreError.protocolViolation("a pairing without an id or a code")
                }
                return NewPairing(id: id, code: code, qr: p.qr, expiresAt: p.expiresAt)
            case .badRequest(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            default: throw Self.unknown
            }
        }
    }

    func pairing(_ id: String) async throws -> PairingInfo {
        try await run {
            switch try await client.getPairing(path: .init(id: id)) {
            case .ok(let o): return Self.pairing(try o.body.json, fallback: id)
            case .notFound(let r): throw Self.fail(r)
            default: throw Self.unknown
            }
        }
    }

    func approve(_ id: String, sas: String, scopes: [String]?) async throws -> PairingInfo {
        try await run {
            switch try await client.approvePairing(path: .init(id: id), body: .json(.init(sas: sas, scopes: scopes))) {
            case .ok(let o): return Self.pairing(try o.body.json, fallback: id)
            case .badRequest(let r): throw Self.fail(r)
            case .notFound(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            default: throw Self.unknown
            }
        }
    }

    func reject(_ id: String) async throws -> PairingInfo {
        try await run {
            switch try await client.rejectPairing(path: .init(id: id)) {
            case .ok(let o): return Self.pairing(try o.body.json, fallback: id)
            case .notFound(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            default: throw Self.unknown
            }
        }
    }

    func lockouts() async throws -> [LockoutInfo] {
        try await run {
            try await client.listLockouts().ok.body.json.map {
                LockoutInfo(key: $0.key, lockedUntil: $0.lockedUntil, strikes: Int($0.strikes))
            }
        }
    }

    func clearLockout(_ key: String) async throws {
        try await run { _ = try await client.clearLockout(body: .json(.init(key: key))).ok }
    }

    func events() -> AsyncStream<ServiceEvent> {
        let source = connection.events()
        return AsyncStream { out in
            let task = Task {
                for await update in source {
                    switch update {
                    case .live: out.yield(.live)
                    case .reconnecting: out.yield(.reconnecting)
                    case .gap: out.yield(.gap)
                    case .ended(let e): out.yield(.ended(e))
                    case .event(let e):
                        let p = e.payload.value
                        out.yield(
                            .event(kind: e.kind, pairingID: p["pairing"] as? String, deviceID: p["device"] as? String))
                    }
                }
                out.finish()
            }
            out.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: mapping

    private static let unknown = CoreError.protocolViolation("The Core answered something this app does not know.")

    /// Whatever the generated client threw, as the `CoreError` inside it.
    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch {
            throw CoreError.unwrapping(error) ?? Self.unknown
        }
    }

    private static func device(_ d: Components.Schemas.Device) -> DeviceInfo {
        DeviceInfo(
            id: d.id, name: d.name, kind: d.kind ?? "device", platform: d.platform, keyStorage: d.keyStorage,
            scopes: d.scopes ?? [], status: d.revokedAt != nil ? "revoked" : (d.status ?? "active"),
            lastUsed: d.lastUsedAt, createdAt: d.createdAt, fingerprint: d.fingerprint, stepup: d.stepup)
    }

    private static func pairing(_ p: Components.Schemas.PairingView, fallback: String) -> PairingInfo {
        PairingInfo(
            id: p.pairingId ?? fallback, status: p.status ?? "live", name: p.name, kind: p.kind, platform: p.platform,
            keyStorage: p.keyStorage, scopes: p.scopes ?? [], sas: p.sas, expiresAt: p.expiresAt, deviceID: p.deviceId)
    }

    private static func fail(_ r: Components.Responses.Conflict) -> CoreError {
        let b = try? r.body.json
        switch b?.code {
        case "sas_mismatch": return .sasMismatch
        case "pairing_expired": return .pairingExpired
        default: return .http(status: 409, code: b?.code ?? "conflict", message: b?.message ?? "The Core refused that.")
        }
    }
    private static func fail(_ r: Components.Responses.BadRequest) -> CoreError {
        .badRequest(message: (try? r.body.json)?.message ?? "The Core refused that.")
    }
    private static func fail(_ r: Components.Responses.NotFound) -> CoreError {
        .http(status: 404, code: "not_found", message: (try? r.body.json)?.message ?? "The Core does not know that.")
    }
}
