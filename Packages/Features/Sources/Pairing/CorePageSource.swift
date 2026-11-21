import AinkradClient
import CoreKit
import Foundation
import Shell

/// The Core page's reads and writes over the signed client. Written against the routes of Core 0.10; the generated client
/// gains them with the epic's `make clients`.
struct LiveCorePageSource: CorePageSource {
    let connection: CoreConnection
    private var client: Client { connection.client }

    func supported() async -> Bool { await connection.serverSupports(minor: coreMinorV010) }

    func prefs() async throws -> CorePagePrefs {
        try await run { Self.prefs(try await client.getCorePrefs().ok.body.json) }
    }

    func set(name: String?, crashReports: Bool?, autoUpdate: Bool?, updateHour: Int?) async throws -> CorePagePrefs {
        try await run {
            let body = Components.Schemas.SetCorePrefs(
                autoUpdate: autoUpdate, crashReports: crashReports, name: name, updateHour: updateHour.map { Int64($0) }
            )
            return Self.prefs(try await client.setCorePrefs(body: .json(body)).ok.body.json)
        }
    }

    func storage() async throws -> CorePageStorage {
        try await run {
            let s = try await client.getCoreStorage().ok.body.json
            return CorePageStorage(
                database: s.databaseBytes.map { Int64($0) }, projects: s.projectsBytes.map { Int64($0) },
                backups: s.backupsBytes.map { Int64($0) }, backupsCount: s.backupsCount.map { Int($0) },
                other: s.otherBytes.map { Int64($0) }, diskUsedPct: s.diskUsedPct.map { Int($0) },
                diskTotal: s.diskTotalBytes.map { Int64($0) })
        }
    }

    func backups() async throws -> CoreBackups? { try await run { try await connection.backupStatus() } }

    func backupNow() async throws { try await run { try await connection.startBackup() } }

    func backupRetention() async -> CoreBackupRetention? { await connection.backupRetention() }

    func setBackupRetention(_ keep: Int) async throws -> Int? {
        try await run { try await connection.setBackupRetention(keep) }
    }

    private static func prefs(_ p: Components.Schemas.CorePrefs) -> CorePagePrefs {
        CorePagePrefs(
            name: p.name, crashReports: p.crashReports ?? false, autoUpdate: p.autoUpdate ?? true,
            updateHour: p.updateHour.map { Int($0) } ?? 3, updateCheckedAt: p.updateCheckedAt)
    }

    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch { throw CoreFailure.of(error) ?? error }
    }
}

/// Settings, Updates over the signed connection. The check is read raw so the fields a newer Core adds (the runner's latest,
/// the reason a feed did not answer) are used without a new client, and an older Core's answer still reads.
struct LiveUpdatesSource: UpdatesSource {
    let connection: CoreConnection
    private var client: Client { connection.client }

    func supported() async -> Bool { await connection.serverSupports(minor: coreMinorV010) }

    func check() async throws -> CoreUpdateCheck {
        let data = try await run {
            try await connection.signedRequest(method: "POST", target: "/api/v1/core/update/check")
        }
        guard let c = CoreUpdateCheck.decode(data) else {
            throw CoreError.invalidInput("The Core's answer did not read.")
        }
        return c
    }

    func runners() async throws -> [UpdatableRunner] {
        try await run {
            try await client.listRunners().ok.body.json.map {
                UpdatableRunner(
                    id: $0.id, name: $0.name, version: $0.version, online: $0.online ?? false,
                    behind: $0.updateAvailable ?? false, updating: $0.updating ?? false, builtIn: $0.builtIn ?? false)
            }
        }
    }

    func updateRunner(_ id: String) async throws {
        try await run { _ = try await client.updateRunner(path: .init(id: id)).accepted }
    }

    func coreStatus() async throws -> CoreUpdateStatus {
        let data = try await run {
            try await connection.signedRequest(method: "GET", target: "/api/v1/system/update")
        }
        guard let s = CoreUpdateStatus.decode(data) else {
            throw CoreError.invalidInput("The Core's answer did not read.")
        }
        return s
    }

    func startCore() async throws {
        try await run { _ = try await connection.signedRequest(method: "POST", target: "/api/v1/system/update") }
    }

    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch { throw CoreFailure.of(error) ?? error }
    }
}
