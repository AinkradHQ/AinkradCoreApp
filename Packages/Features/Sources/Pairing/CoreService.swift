import Agents
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
    /// No longer able to reach the Core, so "Active now" / "Last seen" would only mislead.
    var cutOff: Bool { revoked || status == "locked" || status == "expired" }
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
    /// `session_expired`: the session is being reopened in the background.
    case renewing
    case rateLimited(retryAfter: TimeInterval?)
    /// The socket closed cleanly and came back: the Core restarted.
    case restarted
    case ended(CoreError)
    case event(kind: String, pairingID: String?, deviceID: String?)
    /// The payload of an account event, every value as text, for the bell and banners.
    case notice(kind: String, fields: [String: String])
}

/// The Core as the pairing screens use it. `LiveCoreService` is the only real one; tests bring their own.
protocol CoreService: Sendable {
    var deviceID: String { get }
    func connect() async throws
    func close() async
    /// The scopes this device holds (a new device can never be given more).
    func myScopes() async throws -> [String]
    /// Core's version, the API minor and this device's name and scopes (`GET /me`).
    func about() async throws -> CoreAbout
    func elevatedUntil() async -> Date?
    func stepUp(reason: String) async throws -> Date
    func devices() async throws -> [DeviceInfo]
    func rename(_ id: String, to name: String) async throws -> DeviceInfo
    func setScopes(_ id: String, _ scopes: [String]) async throws -> DeviceInfo
    func revoke(_ id: String) async throws -> DeviceInfo
    func createPairing(name: String, kind: String, scopes: [String]) async throws -> NewPairing
    func pairing(_ id: String) async throws -> PairingInfo
    /// Pairings claimed and still waiting for a decision (admin; the Core has no list route, so the audit's claims are asked).
    func pendingPairings() async throws -> [PairingInfo]
    func approve(_ id: String, sas: String, scopes: [String]?) async throws -> PairingInfo
    func reject(_ id: String) async throws -> PairingInfo
    func lockouts() async throws -> [LockoutInfo]
    func clearLockout(_ key: String) async throws
    func events() -> AsyncStream<ServiceEvent>
    /// The agent routes of this Core; nil where there is no Core to ask (tests, the demo).
    var agentsAPI: (any AgentsAPI)? { get }
}

extension CoreService {
    var agentsAPI: (any AgentsAPI)? { nil }
    func pendingPairings() async throws -> [PairingInfo] { [] }
}

struct LiveCoreService: CoreService {
    let connection: CoreConnection
    var deviceID: String { connection.identity.deviceID }
    var agentsAPI: (any AgentsAPI)? { LiveAgentsAPI(connection: connection) }
    private var client: Client { connection.client }

    func connect() async throws { try await connection.connect() }
    func close() async { await connection.close() }
    func myScopes() async throws -> [String] { try await connection.session().scopes }
    func about() async throws -> CoreAbout {
        let me = try await run { try await client.getMe().ok.body.json }
        return CoreAbout(
            server: me.versions.server, apiMajor: me.versions.api.major, apiMinor: Int(me.versions.api.minor),
            build: me.versions.gitSha, device: me.device.name, scopes: try await myScopes())
    }
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
            case .undocumented(let status, let p): throw await Self.status(status, p)
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
            case .undocumented(let status, let p): throw await Self.status(status, p)
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
            case .undocumented(let status, let p): throw await Self.status(status, p)
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
            case .undocumented(let status, let p): throw await Self.status(status, p)
            default: throw Self.unknown
            }
        }
    }

    func pairing(_ id: String) async throws -> PairingInfo {
        try await run {
            switch try await client.getPairing(path: .init(id: id)) {
            case .ok(let o): return Self.pairing(try o.body.json, fallback: id)
            case .notFound(let r): throw Self.fail(r)
            case .undocumented(let status, let p): throw await Self.status(status, p)
            default: throw Self.unknown
            }
        }
    }

    func pendingPairings() async throws -> [PairingInfo] {
        let rows = try await run {
            try await client.listAudit(query: .init(limit: 50, kind: "pairing.claimed")).ok.body.json.items
        }
        var ids: [String] = []
        for r in rows {
            if let id = r.details.value["pairing"] as? String, !ids.contains(id) { ids.append(id) }
        }
        var out: [PairingInfo] = []
        for id in ids {
            if let p = try? await pairing(id), p.status == "claimed" { out.append(p) }
        }
        return out
    }

    func approve(_ id: String, sas: String, scopes: [String]?) async throws -> PairingInfo {
        try await run {
            switch try await client.approvePairing(path: .init(id: id), body: .json(.init(sas: sas, scopes: scopes))) {
            case .ok(let o): return Self.pairing(try o.body.json, fallback: id)
            case .badRequest(let r): throw Self.fail(r)
            case .notFound(let r): throw Self.fail(r)
            case .conflict(let r): throw Self.fail(r)
            case .undocumented(let status, let p): throw await Self.status(status, p)
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
            case .undocumented(let status, let p): throw await Self.status(status, p)
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
                var closedCleanly = false
                for await update in source {
                    switch update {
                    case .live:
                        out.yield(.live)
                        if closedCleanly { out.yield(.restarted) }
                        closedCleanly = false
                    case .reconnecting(let cause):
                        closedCleanly = cause == nil
                        switch cause {
                        case .sessionExpired?: out.yield(.renewing)
                        case .rateLimited(let after)?: out.yield(.rateLimited(retryAfter: after))
                        default: out.yield(.reconnecting)
                        }
                    case .gap: out.yield(.gap)
                    case .ended(let e): out.yield(.ended(e))
                    case .event(let e):
                        let p = Self.flatten(e.payload.value)
                        let kind = Self.eventKind(e.kind, p)
                        out.yield(
                            .event(kind: kind, pairingID: p["pairing"] as? String, deviceID: p["device"] as? String))
                        if AccountNotice.kinds.contains(kind) {
                            out.yield(.notice(kind: kind, fields: p.compactMapValues { Self.text($0) }))
                        }
                    }
                }
                out.finish()
            }
            out.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: mapping

    /// Core sends every audit row as kind "audit" with the real action in the payload; the app routes on the action.
    static func eventKind(_ kind: String, _ payload: [String: (any Sendable)?]) -> String {
        kind == "audit" ? (payload["action"] as? String ?? kind) : kind
    }

    /// An audit row keeps its own fields under `details` (`{"action":"pairing.claimed","details":{"pairing":"p_…"}}`) and names a
    /// device it is about in `entity_ref`. Lifts both to the top so every reader sees one flat shape; a top-level field wins.
    static func flatten(_ payload: [String: (any Sendable)?]) -> [String: (any Sendable)?] {
        var p = payload
        if let d = payload["details"] as? [String: (any Sendable)?] { p.merge(d) { top, _ in top } }
        if p["device"] == nil, payload["entity_kind"] as? String == "device", let ref = payload["entity_ref"] {
            p["device"] = ref
        }
        return p
    }

    /// A payload value as text; null and nested values have none.
    private static func text(_ v: (any Sendable)?) -> String? {
        switch v {
        case let s as String: s
        case let n as Int: String(n)
        case let n as Int64: String(n)
        case let n as Double: String(Int64(n))
        case let b as Bool: String(b)
        default: nil
        }
    }

    private static let unknown = CoreError.protocolViolation("The Core answered something this app does not know.")

    /// Whatever the generated client threw, as the `CoreError` inside it.
    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch {
            throw CoreFailure.of(error) ?? Self.unknown
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
    /// A status the contract does not list (410, 413, 502, 503): the Core's standard error body, when it has one.
    private static func status(_ code: Int, _ payload: UndocumentedPayload) async -> CoreError {
        var data = Data()
        if let body = payload.body, let all = try? await Data(collecting: body, upTo: 16 * 1024) { data = all }
        let b = try? JSONDecoder().decode(Components.Schemas.ErrorBody.self, from: data)
        return .http(
            status: code, code: b?.code ?? "error", message: b?.message ?? "The Core could not do that (\(code)).")
    }
    private static func fail(_ r: Components.Responses.NotFound) -> CoreError {
        .http(status: 404, code: "not_found", message: (try? r.body.json)?.message ?? "The Core does not know that.")
    }
}
