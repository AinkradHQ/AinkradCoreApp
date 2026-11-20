import CoreKit
import Foundation

// The Core 0.10 calls of the Secrets and Activity apps (E2-6): show or export a secret, the Core's own history and the audit
// counts. They go through the signed transport until the generated client has them, and only when the Core speaks API minor 95;
// an older Core keeps today's screens.

/// The first API minor of Core 0.10 (the same number as the Core page's `CoreMinor.v010`).
enum ActivityMinor { static let v010: Int32 = 95 }

/// A value the Core handed over to be shown. It never prints: a log line or a debugger shows a fixed word.
struct RevealedValue: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let name: String
    let kind: String
    let value: String
    /// The Core's own word on how long to keep it on screen.
    let hideAfter: TimeInterval
    var description: String { "RevealedValue(\(name), hidden)" }
    var debugDescription: String { description }
}

/// One secret of an export. It never prints.
struct ExportedValue: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let name: String
    let kind: String
    let group: String?
    let fileName: String?
    let value: String
    var description: String { "ExportedValue(\(name), hidden)" }
    var debugDescription: String { description }
}

/// One minute of the Core's own readings.
struct OpsPoint: Equatable, Sendable {
    let at: Date
    let cpuPct: Double?
    let memoryBytes: Double?
    let diskUsedPct: Double?
    /// The whole machine (a Linux Core): its CPU share, memory and disk.
    var hostCpuPct: Double?
    var ramUsedBytes: Double?
    var ramTotalBytes: Double?
    var diskUsedBytes: Double?
    var diskTotalBytes: Double?
}

/// One day of the audit log: rows per hour and per kind.
struct AuditDayStat: Equatable, Sendable, Identifiable {
    var id: String { date }
    let date: String
    let hours: [Int]
    let total: Int
    let kinds: [String: Int]
    let needsAttention: Int

    func count(_ kind: String) -> Int { kinds[kind] ?? 0 }
}

extension AdminService {
    func supportsV010() async -> Bool { false }
    func revealValue(_ name: String) async throws -> RevealedValue { throw Self.unsupported }
    func exportSecrets() async throws -> [ExportedValue] { throw Self.unsupported }
    func opsHistory() async throws -> [OpsPoint] { [] }
    func hostFacts() async -> CoreHostFacts? { nil }
    func backups() async throws -> CoreBackups? { nil }
    func startBackup() async throws { throw Self.unsupported }
    func recentRestarts() async -> [CoreRestart] { [] }
    func auditStats(days: Int, tzOffsetMins: Int) async throws -> [AuditDayStat] { [] }

    static var unsupported: AdminFailure {
        AdminFailure(status: 404, code: "unsupported", message: "This Core cannot do that yet.", errorID: nil)
    }
}

extension LiveAdminService {
    func supportsV010() async -> Bool { await connection.serverSupports(minor: ActivityMinor.v010) }

    /// E1's `POST /secrets/{id}/reveal`: no body, and the answer is just `{value}`. The screen keeps the name it asked for, a
    /// text kind (a file secret is never shown, `canShow`), and its own 15 seconds.
    func revealValue(_ name: String) async throws -> RevealedValue {
        struct Wire: Decodable { let value: String }
        let w: Wire = try await call("POST", "/api/v1/secrets/\(name)/reveal")
        return RevealedValue(name: name, kind: "text", value: w.value, hideAfter: 15)
    }

    func exportSecrets() async throws -> [ExportedValue] {
        struct Item: Decodable {
            let name: String
            let kind: String?
            let group: String?
            let file_name: String?
            let value: String
        }
        struct Wire: Decodable { let items: [Item] }
        let w: Wire = try await call("POST", "/api/v1/secrets/export", limit: 16 << 20)
        return w.items.map {
            ExportedValue(
                name: $0.name, kind: $0.kind ?? "text", group: $0.group, fileName: $0.file_name, value: $0.value)
        }
    }

    func opsHistory() async throws -> [OpsPoint] {
        struct Sample: Decodable {
            let at: String
            let cpu_pct: Double?
            let memory_bytes: Double?
            let disk_used_pct: Double?
            let host_cpu_pct: Double?
            let ram_used_bytes: Double?
            let ram_total_bytes: Double?
            let disk_used_bytes: Double?
            let disk_total_bytes: Double?
        }
        struct Wire: Decodable { let samples: [Sample] }
        let w: Wire = try await call("GET", "/api/v1/ops/history?hours=24")
        return w.samples.compactMap { s in
            Self.date(s.at).map {
                OpsPoint(
                    at: $0, cpuPct: s.cpu_pct, memoryBytes: s.memory_bytes, diskUsedPct: s.disk_used_pct,
                    hostCpuPct: s.host_cpu_pct, ramUsedBytes: s.ram_used_bytes, ramTotalBytes: s.ram_total_bytes,
                    diskUsedBytes: s.disk_used_bytes, diskTotalBytes: s.disk_total_bytes)
            }
        }
    }

    func hostFacts() async -> CoreHostFacts? { await connection.hostFacts() }

    func backups() async throws -> CoreBackups? {
        do { return try await connection.backupStatus() } catch { throw CoreFailure.of(error) ?? error }
    }

    func recentRestarts() async -> [CoreRestart] { await connection.recentRestarts() }

    func startBackup() async throws {
        do { try await connection.startBackup() } catch { throw CoreFailure.of(error) ?? error }
    }

    func auditStats(days: Int, tzOffsetMins: Int) async throws -> [AuditDayStat] {
        struct Kind: Decodable {
            let kind: String
            let count: Int
        }
        struct Day: Decodable {
            let date: String
            let hours: [Int]
            let total: Int
            let kinds: [Kind]
            let needs_attention: Int
        }
        struct Wire: Decodable { let days: [Day] }
        let w: Wire = try await call("GET", "/api/v1/audit/stats?days=\(days)&tz_offset_mins=\(tzOffsetMins)")
        return w.days.map {
            AuditDayStat(
                date: $0.date, hours: Array(($0.hours + Array(repeating: 0, count: 24)).prefix(24)), total: $0.total,
                kinds: Dictionary($0.kinds.map { ($0.kind, $0.count) }, uniquingKeysWith: +),
                needsAttention: $0.needs_attention)
        }
    }

    private func call<T: Decodable>(_ method: String, _ path: String, limit: Int? = nil) async throws -> T {
        do {
            let data = try await connection.signedRequest(method: method, target: path, limit: limit)
            return try JSONDecoder().decode(T.self, from: data)
        } catch let f as AdminFailure { throw f } catch {
            throw CoreFailure.of(error) ?? error
        }
    }

    private static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
