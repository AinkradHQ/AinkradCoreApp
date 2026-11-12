import AinkradClient
import CoreKit
import Foundation
import OpenAPIRuntime

/// The Core as the admin screens use it. `LiveAdminService` is the only real one; tests and the demo bring their own.
/// Values of secrets only ever go in (`createSecret`, `rotateSecret`); nothing here returns one.
protocol AdminService: Sendable {
    func settings() async throws -> [SettingItem]
    func setSetting(_ key: String, _ value: Int64) async throws -> SettingItem
    func resetSetting(_ key: String) async throws -> SettingItem
    func history(_ key: String) async throws -> [SettingChangeItem]
    func secrets() async throws -> [SecretItem]
    func createSecret(_ draft: SecretDraft) async throws -> SecretItem
    func rotateSecret(_ name: String, value: String, fileName: String?) async throws -> SecretItem
    func deleteSecret(_ name: String) async throws
    func secretGroups() async throws -> [SecretGroupItem]
    func createSecretGroup(name: String, description: String, runners: [String]) async throws -> SecretGroupItem
    func updateSecretGroup(_ name: String, description: String, runners: [String]) async throws -> SecretGroupItem
    func deleteSecretGroup(_ name: String) async throws
    /// Lends every secret of the group to a runner at once.
    func leaseGroup(_ name: String, runner: String, ttl: Int64?) async throws -> [LeaseItem]
    func lease(_ name: String, runner: String, ttl: Int64?) async throws -> LeaseItem
    func runners() async throws -> [RunnerChoice]
    func audit(before: Int64?, limit: Int, filter: AuditFilter) async throws -> AuditPageItem
    /// The Core's Prometheus text, as it is.
    func metrics() async throws -> String
}

struct LiveAdminService: AdminService {
    let connection: CoreConnection
    private var client: Client { connection.client }
    private static let scope = "server"

    func settings() async throws -> [SettingItem] {
        try await run {
            switch try await client.listServerSettings() {
            case .ok(let o): return try o.body.json.map(Self.setting)
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .internalServerError(let r): throw Self.fail(500, try? r.body.json)
            case .undocumented(let status, let p): throw await Self.fail(status, p)
            default: throw Self.unknown
            }
        }
    }

    func setSetting(_ key: String, _ value: Int64) async throws -> SettingItem {
        try await run {
            switch try await client.setSetting(
                path: .init(scope: Self.scope, key: key), body: .json(.init(value: value)))
            {
            case .ok(let o): return Self.setting(try o.body.json)
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .internalServerError(let r): throw Self.fail(500, try? r.body.json)
            case .undocumented(let status, let p): throw await Self.fail(status, p)
            default: throw Self.unknown
            }
        }
    }

    func resetSetting(_ key: String) async throws -> SettingItem {
        try await run {
            switch try await client.resetSetting(path: .init(scope: Self.scope, key: key)) {
            case .ok(let o): return Self.setting(try o.body.json)
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .internalServerError(let r): throw Self.fail(500, try? r.body.json)
            case .undocumented(let status, let p): throw await Self.fail(status, p)
            default: throw Self.unknown
            }
        }
    }

    func history(_ key: String) async throws -> [SettingChangeItem] {
        try await run {
            switch try await client.settingHistory(path: .init(scope: Self.scope, key: key)) {
            case .ok(let o):
                return try o.body.json.map {
                    SettingChangeItem(seq: $0.seq, at: $0.at, actor: Self.actor($0.actor), old: $0.old, new: $0.new)
                }
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .internalServerError(let r): throw Self.fail(500, try? r.body.json)
            case .undocumented(let status, let p): throw await Self.fail(status, p)
            default: throw Self.unknown
            }
        }
    }

    func secrets() async throws -> [SecretItem] {
        try await run {
            switch try await client.listSecrets() {
            case .ok(let o): return try o.body.json.map(Self.secret)
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .internalServerError(let r): throw Self.fail(500, try? r.body.json)
            case .undocumented(let status, let p): throw await Self.fail(status, p)
            default: throw Self.unknown
            }
        }
    }

    func createSecret(_ d: SecretDraft) async throws -> SecretItem {
        try await run {
            let body = Components.Schemas.NewSecret(
                delivery: d.delivery, description: d.description.isEmpty ? nil : d.description, fileMode: d.fileMode,
                fileName: d.fileName, group: d.group, kind: d.kind, name: d.name, runners: d.runners, value: d.value)
            switch try await client.createSecret(body: .json(body)) {
            case .ok(let o): return Self.secret(try o.body.json)
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .internalServerError(let r): throw Self.fail(500, try? r.body.json)
            case .undocumented(let status, let payload): throw await Self.fail(status, payload)
            default: throw Self.unknown
            }
        }
    }

    func rotateSecret(_ name: String, value: String, fileName: String?) async throws -> SecretItem {
        try await run {
            switch try await client.rotateSecret(
                path: .init(id: name), body: .json(.init(fileName: fileName, value: value)))
            {
            case .ok(let o): return Self.secret(try o.body.json)
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .internalServerError(let r): throw Self.fail(500, try? r.body.json)
            case .undocumented(let status, let payload): throw await Self.fail(status, payload)
            default: throw Self.unknown
            }
        }
    }

    func secretGroups() async throws -> [SecretGroupItem] {
        try await run { try await client.listSecretGroups().ok.body.json.map(Self.group) }
    }

    func createSecretGroup(name: String, description: String, runners: [String]) async throws -> SecretGroupItem {
        try await run {
            Self.group(
                try await client.createSecretGroup(
                    body: .json(
                        .init(description: description.isEmpty ? nil : description, name: name, runners: runners))
                ).ok.body.json)
        }
    }

    func updateSecretGroup(_ name: String, description: String, runners: [String]) async throws -> SecretGroupItem {
        try await run {
            Self.group(
                try await client.updateSecretGroup(
                    path: .init(id: name), body: .json(.init(description: description, runners: runners))
                ).ok.body.json)
        }
    }

    func deleteSecretGroup(_ name: String) async throws {
        try await run { _ = try await client.deleteSecretGroup(path: .init(id: name)).ok }
    }

    func leaseGroup(_ name: String, runner: String, ttl: Int64?) async throws -> [LeaseItem] {
        try await run {
            try await client.leaseSecretGroup(path: .init(id: name), body: .json(.init(runner: runner, ttlSecs: ttl)))
                .ok.body.json.leases.map {
                    LeaseItem(lease: $0.lease, secret: $0.secret, runner: runner, expiresAt: $0.expiresAt)
                }
        }
    }

    func deleteSecret(_ name: String) async throws {
        try await run {
            switch try await client.deleteSecret(path: .init(id: name)) {
            case .ok: return
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .internalServerError(let r): throw Self.fail(500, try? r.body.json)
            case .undocumented(let status, let p): throw await Self.fail(status, p)
            default: throw Self.unknown
            }
        }
    }

    func lease(_ name: String, runner: String, ttl: Int64?) async throws -> LeaseItem {
        try await run {
            switch try await client.leaseSecret(
                path: .init(id: name), body: .json(.init(runner: runner, ttlSecs: ttl)))
            {
            case .ok(let o):
                let g = try o.body.json
                return LeaseItem(lease: g.lease, secret: name, runner: runner, expiresAt: g.expiresAt)
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .internalServerError(let r): throw Self.fail(500, try? r.body.json)
            case .undocumented(let status, let payload): throw await Self.fail(status, payload)
            default: throw Self.unknown
            }
        }
    }

    func runners() async throws -> [RunnerChoice] {
        try await run {
            try await client.listRunners().ok.body.json.map { r in
                RunnerChoice(
                    id: r.id, name: r.name, online: r.online ?? false,
                    drivers: (r.drivers ?? []).compactMap { $0.name })
            }
        }
    }

    func audit(before: Int64?, limit: Int, filter: AuditFilter) async throws -> AuditPageItem {
        try await run {
            let q = Operations.ListAudit.Input.Query(
                before: before, limit: Int32(limit), kind: filter.kind.isEmpty ? nil : filter.kind,
                target: filter.target.isEmpty ? nil : filter.target,
                actor: filter.actor == .any ? nil : filter.actor.rawValue,
                nobodyWatching: filter.nobodyWatching ? true : nil)
            switch try await client.listAudit(query: q) {
            case .ok(let o):
                let page = try o.body.json
                return AuditPageItem(items: page.items.map(Self.audit), nextBefore: page.nextBefore)
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .internalServerError(let r): throw Self.fail(500, try? r.body.json)
            case .undocumented(let status, let p): throw await Self.fail(status, p)
            default: throw Self.unknown
            }
        }
    }

    func metrics() async throws -> String {
        try await run {
            switch try await client.getMetrics() {
            case .ok(let o): return try await String(collecting: o.body.plainText, upTo: 4 << 20)
            case .badRequest(let r): throw Self.fail(400, try? r.body.json)
            case .notFound(let r): throw Self.fail(404, try? r.body.json)
            case .conflict(let r): throw Self.fail(409, try? r.body.json)
            case .internalServerError(let r): throw Self.fail(500, try? r.body.json)
            case .undocumented(let status, let p): throw await Self.fail(status, p)
            default: throw Self.unknown
            }
        }
    }

    // MARK: mapping

    private static let unknown = CoreError.protocolViolation("The Core answered something this app does not know.")

    /// Whatever the generated client threw, as the `CoreError` inside it (an `AdminFailure` passes through).
    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch let f as AdminFailure { throw f } catch {
            throw CoreFailure.of(error) ?? Self.unknown
        }
    }

    static func fail(_ status: Int, _ b: Components.Schemas.ErrorBody?) -> AdminFailure {
        AdminFailure(
            status: status, code: b?.code ?? "unknown", message: b?.message ?? "The Core refused that.",
            errorID: b?.errorId)
    }

    static func fail(_ status: Int, _ payload: UndocumentedPayload) async -> AdminFailure {
        var data = Data()
        if let body = payload.body, let all = try? await Data(collecting: body, upTo: 64 * 1024) { data = all }
        return fail(status, try? JSONDecoder().decode(Components.Schemas.ErrorBody.self, from: data))
    }

    static func setting(_ s: Components.Schemas.Setting) -> SettingItem {
        SettingItem(
            key: s.key, detail: s.description, unit: s.unit.value1?.rawValue ?? s.unit.value2 ?? "unknown",
            defaultValue: s._default, min: s.min, max: s.max, value: s.value, source: s.source)
    }

    static func secret(_ s: Components.Schemas.SecretInfo) -> SecretItem {
        SecretItem(
            name: s.name, owner: s.owner, runners: s.runners, delivery: s.delivery, version: s.version, size: s.size,
            keyID: s.keyId, createdAt: s.createdAt, updatedAt: s.updatedAt, kind: s.kind ?? "text",
            description: s.description ?? "", fileName: s.fileName, fileMode: s.fileMode, group: s.group,
            effectiveRunners: s.effectiveRunners, lastUsedAt: s.lastUsedAt, useCount: s.useCount ?? 0)
    }

    static func group(_ g: Components.Schemas.SecretGroupInfo) -> SecretGroupItem {
        SecretGroupItem(name: g.name, description: g.description, members: g.members, runners: g.runners)
    }

    static func actor(_ a: Components.Schemas.EventActor) -> ActorInfo {
        switch a {
        case .user(let u): .user(u.userId)
        case .system: .system
        }
    }

    static func audit(_ e: Components.Schemas.AuditEntry) -> AuditItem {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let text = (try? enc.encode(e.details)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return AuditItem(
            seq: e.seq, at: e.at, action: e.action, actor: actor(e.actor), entityKind: e.entityKind,
            entityRef: e.entityRef, details: text,
            origin: e.origin.map {
                AuditOrigin(
                    kind: $0.kind, reference: $0.reference, rootKind: $0.rootKind, rootReference: $0.rootReference)
            })
    }
}
