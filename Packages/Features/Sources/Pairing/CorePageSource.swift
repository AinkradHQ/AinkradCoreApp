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

    func checkUpdate() async throws -> (at: Date, feed: Bool) {
        try await run {
            let r = try await client.checkCoreUpdate().ok.body.json
            return (r.checkedAt, r.status != "feed_unavailable")
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
