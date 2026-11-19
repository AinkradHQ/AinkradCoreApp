import Foundation

// The Core 0.10 host facts and backup calls (E2-6): the machine's CPU, memory and disk, the runner fleet, and the backup schedule,
// history and "back up now". The routes ride the signed transport (`signedRequest`) until the generated client has them, and
// only on a Core that speaks API minor 95; an older Core answers nil and the screens keep what they had.

/// The first API minor of Core 0.10.
public let coreMinorV010: Int32 = 95

/// What the Core machine says about itself: the whole host, not only the Core process. Absent parts are nil (a Core on a Mac).
public struct CoreHostFacts: Equatable, Sendable {
    public var cpuPct: Double?
    public var ramUsedBytes: Int64?
    public var ramTotalBytes: Int64?
    public var diskUsedBytes: Int64?
    public var fleet: CoreFleet?

    public init(
        cpuPct: Double? = nil, ramUsedBytes: Int64? = nil, ramTotalBytes: Int64? = nil, diskUsedBytes: Int64? = nil,
        fleet: CoreFleet? = nil
    ) {
        self.cpuPct = cpuPct
        self.ramUsedBytes = ramUsedBytes
        self.ramTotalBytes = ramTotalBytes
        self.diskUsedBytes = diskUsedBytes
        self.fleet = fleet
    }

    /// Memory in use, 0...100, when the host says both numbers.
    public var ramPct: Int? {
        guard let u = ramUsedBytes, let t = ramTotalBytes, t > 0 else { return nil }
        return Int((Double(u) / Double(t) * 100).rounded())
    }

    public static func decode(_ data: Data) -> CoreHostFacts? {
        struct Runner: Decodable {
            let name: String
            let state: String
            let busy_pct: Int?
        }
        struct Fleet: Decodable {
            let working: Int
            let idle: Int
            let offline: Int
            let runners: [Runner]
        }
        struct Wire: Decodable {
            let host_cpu_pct: Double?
            let ram_used_bytes: Int64?
            let ram_total_bytes: Int64?
            let disk_used_bytes: Int64?
            let fleet: Fleet?
        }
        guard let w = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        return CoreHostFacts(
            cpuPct: w.host_cpu_pct, ramUsedBytes: w.ram_used_bytes, ramTotalBytes: w.ram_total_bytes,
            diskUsedBytes: w.disk_used_bytes,
            fleet: w.fleet.map {
                CoreFleet(
                    working: $0.working, idle: $0.idle, offline: $0.offline,
                    runners: $0.runners.map { CoreFleet.Runner(name: $0.name, state: $0.state, busyPct: $0.busy_pct) })
            })
    }
}

/// How many runners are working, idle and offline, and each one.
public struct CoreFleet: Equatable, Sendable {
    public struct Runner: Equatable, Sendable {
        public var name: String
        /// `working`, `idle` or `offline`.
        public var state: String
        public var busyPct: Int?
        public init(name: String, state: String, busyPct: Int? = nil) {
            self.name = name
            self.state = state
            self.busyPct = busyPct
        }
    }
    public var working: Int
    public var idle: Int
    public var offline: Int
    public var runners: [Runner]
    public init(working: Int, idle: Int, offline: Int, runners: [Runner] = []) {
        self.working = working
        self.idle = idle
        self.offline = offline
        self.runners = runners
    }
}

/// One backup on the Core machine.
public struct CoreBackupFile: Equatable, Sendable {
    public var at: Date
    public var bytes: Int64
    public init(at: Date, bytes: Int64) {
        self.at = at
        self.bytes = bytes
    }
}

/// The backup schedule, the last run and the backups on disk (`GET /system/backups`).
public struct CoreBackups: Equatable, Sendable {
    /// `present`, `absent` (no host helper here) or `error`.
    public var helper: String
    public var installed: Bool
    /// The timer's `OnCalendar` expression.
    public var schedule: String?
    public var nextAt: Date?
    public var running: Bool
    /// `success`, or systemd's word for the failure.
    public var lastResult: String?
    public var lastFinishedAt: Date?
    /// Newest first.
    public var history: [CoreBackupFile]

    public init(
        helper: String = "present", installed: Bool = true, schedule: String? = nil, nextAt: Date? = nil,
        running: Bool = false, lastResult: String? = nil, lastFinishedAt: Date? = nil, history: [CoreBackupFile] = []
    ) {
        self.helper = helper
        self.installed = installed
        self.schedule = schedule
        self.nextAt = nextAt
        self.running = running
        self.lastResult = lastResult
        self.lastFinishedAt = lastFinishedAt
        self.history = history
    }

    /// Whether this Core can back up and be asked to.
    public var available: Bool { helper == "present" && installed }

    /// The schedule in words: "Every day", "Every hour", "Every day at 22:00", or the raw expression when it is a shape this
    /// does not know.
    public var scheduleWords: String? {
        guard let s = schedule?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        switch s {
        case "daily": return "Every day"
        case "hourly": return "Every hour"
        case "weekly": return "Every week"
        default: break
        }
        let parts = s.split(separator: " ")
        if parts.count == 2, parts[0] == "*-*-*", parts[1].split(separator: ":").count == 3 {
            let hm = parts[1].split(separator: ":").prefix(2).joined(separator: ":")
            return "Every day at \(hm)"
        }
        return s
    }

    /// For the last `days` days (today last), whether a backup was written that day, by the calendar `calendar` uses.
    public func days(_ days: Int, now: Date, calendar: Calendar = .current) -> [Bool] {
        (0..<days).reversed().map { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: now) else { return false }
            return history.contains { calendar.isDate($0.at, inSameDayAs: day) }
        }
    }

    public static func decode(_ data: Data) -> CoreBackups? {
        struct File: Decodable {
            let at: String
            let bytes: Int64
        }
        struct Run: Decodable {
            let result: String?
            let running: Bool?
            let finished_at: String?
        }
        struct Wire: Decodable {
            let helper: String
            let installed: Bool?
            let schedule: String?
            let next_at: String?
            let last_run: Run?
            let history: [File]?
        }
        guard let w = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        return CoreBackups(
            helper: w.helper, installed: w.installed ?? false, schedule: w.schedule, nextAt: w.next_at.flatMap(date),
            running: w.last_run?.running ?? false, lastResult: w.last_run?.result,
            lastFinishedAt: w.last_run?.finished_at.flatMap(date),
            history: (w.history ?? []).compactMap { f in date(f.at).map { CoreBackupFile(at: $0, bytes: f.bytes) } })
    }

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

extension CoreConnection {
    /// The host facts from `GET /core/health`; nil on a Core before 0.10 or when the call fails.
    public func hostFacts() async -> CoreHostFacts? {
        guard await serverSupports(minor: coreMinorV010),
            let data = try? await signedRequest(method: "GET", target: "/api/v1/core/health")
        else { return nil }
        return CoreHostFacts.decode(data)
    }

    /// The backup schedule and history; nil on a Core before 0.10.
    public func backupStatus() async throws -> CoreBackups? {
        guard await serverSupports(minor: coreMinorV010) else { return nil }
        let data = try await signedRequest(method: "GET", target: "/api/v1/system/backups")
        return CoreBackups.decode(data)
    }

    /// Starts a backup now (`POST /system/backup`).
    public func startBackup() async throws {
        _ = try await signedRequest(method: "POST", target: "/api/v1/system/backup")
    }
}
