import CoreKit
import Foundation
import Shell

@testable import Admin

@MainActor
final class FakeHost: AdminHost {
    let shell = ShellModel()
    var pausedReason: String?
    var elevationNotice: AdminNotice?
    var declines = false
    private(set) var reasons: [String] = []
    private(set) var rateLimits: [TimeInterval?] = []
    func clearElevationNotice() { elevationNotice = nil }
    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T {
        reasons.append(reason)
        if declines { throw AdminDeclined() }
        return try await op()
    }
    func rateLimited(retryAfter: TimeInterval?) { rateLimits.append(retryAfter) }
}

func setting(
    _ key: String, value: Int64 = 10, def: Int64 = 10, min: Int64 = 1, max: Int64 = 100, unit: String = "seconds",
    source: String? = nil
) -> SettingItem {
    SettingItem(
        key: key, detail: "About \(key).", unit: unit, defaultValue: def, min: min, max: max, value: value,
        source: source)
}

func secret(_ name: String, version: Int64 = 1, runners: [String] = ["d_run"]) -> SecretItem {
    SecretItem(
        name: name, owner: "d_me", runners: runners, delivery: "env", version: version, size: 12, keyID: "k1",
        createdAt: Date(timeIntervalSince1970: 1_000), updatedAt: Date(timeIntervalSince1970: 2_000))
}

func audit(_ seq: Int64, action: String = "setting.set") -> AuditItem {
    AuditItem(
        seq: seq, at: Date(timeIntervalSince1970: Double(seq)), action: action, actor: .user(1), entityKind: "setting",
        entityRef: "x", details: "{}")
}

final class FakeService: AdminService, @unchecked Sendable {
    private let lock = NSLock()
    var settingList: [SettingItem] = []
    var historyByKey: [String: [SettingChangeItem]] = [:]
    var secretList: [SecretItem] = []
    var runnerList: [RunnerChoice] = [RunnerChoice(id: "d_run", name: "mac-studio", online: true, drivers: ["pty"])]
    var auditRows: [AuditItem] = []
    var metricsText = ""
    var failure: (any Error)?
    private var calls: [String] = []
    private var secretValues: [String] = []
    private var auditCalls: [(before: Int64?, filter: AuditFilter)] = []

    var log: [String] { lock.withLock { calls } }
    /// Every value that was ever sent (the one place a value may appear).
    var sentValues: [String] { lock.withLock { secretValues } }
    var auditQueries: [(before: Int64?, filter: AuditFilter)] { lock.withLock { auditCalls } }
    private func note(_ s: String) throws {
        lock.withLock { calls.append(s) }
        if let failure { throw failure }
    }

    func settings() async throws -> [SettingItem] {
        try note("settings")
        return settingList
    }
    func setSetting(_ key: String, _ value: Int64) async throws -> SettingItem {
        try note("set \(key) \(value)")
        guard let i = settingList.firstIndex(where: { $0.key == key }) else {
            throw AdminFailure(status: 404, code: "not_found", message: "no", errorID: nil)
        }
        settingList[i].value = value
        settingList[i].source = value == settingList[i].defaultValue ? nil : "server"
        return settingList[i]
    }
    func resetSetting(_ key: String) async throws -> SettingItem {
        try note("reset \(key)")
        guard let i = settingList.firstIndex(where: { $0.key == key }) else {
            throw AdminFailure(status: 404, code: "not_found", message: "no", errorID: nil)
        }
        settingList[i].value = settingList[i].defaultValue
        settingList[i].source = nil
        return settingList[i]
    }
    func history(_ key: String) async throws -> [SettingChangeItem] {
        try note("history \(key)")
        return historyByKey[key] ?? []
    }
    func secrets() async throws -> [SecretItem] {
        try note("secrets")
        return secretList
    }
    func createSecret(name: String, value: String, delivery: String, runners: [String]) async throws -> SecretItem {
        lock.withLock { secretValues.append(value) }
        try note("create \(name) \(delivery) \(runners.joined(separator: ","))")
        let made = secret(name, runners: runners)
        secretList.append(made)
        return made
    }
    func rotateSecret(_ name: String, value: String) async throws -> SecretItem {
        lock.withLock { secretValues.append(value) }
        try note("rotate \(name)")
        guard let i = secretList.firstIndex(where: { $0.name == name }) else {
            throw AdminFailure(status: 404, code: "not_found", message: "no", errorID: nil)
        }
        secretList[i] = secret(name, version: secretList[i].version + 1, runners: secretList[i].runners)
        return secretList[i]
    }
    func deleteSecret(_ name: String) async throws {
        try note("delete \(name)")
        secretList.removeAll { $0.name == name }
    }
    func lease(_ name: String, runner: String, ttl: Int64?) async throws -> LeaseItem {
        try note("lease \(name) \(runner) \(ttl.map(String.init) ?? "default")")
        return LeaseItem(lease: "l_abc", secret: name, runner: runner, expiresAt: Date().addingTimeInterval(120))
    }
    func runners() async throws -> [RunnerChoice] { runnerList }
    func audit(before: Int64?, limit: Int, filter: AuditFilter) async throws -> AuditPageItem {
        lock.withLock { auditCalls.append((before, filter)) }
        try note("audit \(before.map(String.init) ?? "-")")
        let rows = auditRows.filter { filter.kind.isEmpty || $0.action.hasPrefix(filter.kind) }
            .sorted { $0.seq > $1.seq }.filter { before == nil || $0.seq < before! }
        let page = Array(rows.prefix(limit))
        return AuditPageItem(items: page, nextBefore: rows.count > limit ? page.last?.seq : nil)
    }
    func metrics() async throws -> String {
        try note("metrics")
        return metricsText
    }
}

@MainActor
func makeAdmin(_ service: FakeService = FakeService(), host: FakeHost = FakeHost()) async -> (
    AdminModel, FakeService, FakeHost
) {
    let admin = AdminModel(host: host)
    admin.use(service)
    await settle()
    return (admin, service, host)
}

/// Lets the loads `use` started finish.
@MainActor
func settle() async {
    for _ in 0..<20 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(30))
}
