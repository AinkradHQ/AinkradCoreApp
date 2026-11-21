import CoreKit
import Foundation
import Observation

/// The Core's own preferences, as the Core page shows them (`GET /api/v1/core/prefs`, Core 0.10).
public struct CorePagePrefs: Equatable, Sendable {
    public var name: String?
    public var crashReports: Bool
    public var autoUpdate: Bool
    /// The hour, 0 to 23, an automatic update installs at.
    public var updateHour: Int
    public var updateCheckedAt: Date?
    public init(
        name: String? = nil, crashReports: Bool = false, autoUpdate: Bool = true, updateHour: Int = 3,
        updateCheckedAt: Date? = nil
    ) {
        self.name = name
        self.crashReports = crashReports
        self.autoUpdate = autoUpdate
        self.updateHour = updateHour
        self.updateCheckedAt = updateCheckedAt
    }
}

/// Bytes by kind of data (`GET /api/v1/core/storage`). A part the Core could not measure is nil.
public struct CorePageStorage: Equatable, Sendable {
    public var database: Int64?
    public var projects: Int64?
    public var backups: Int64?
    public var backupsCount: Int?
    public var other: Int64?
    public var diskUsedPct: Int?
    public var diskTotal: Int64?
    public init(
        database: Int64? = nil, projects: Int64? = nil, backups: Int64? = nil, backupsCount: Int? = nil,
        other: Int64? = nil, diskUsedPct: Int? = nil, diskTotal: Int64? = nil
    ) {
        self.database = database
        self.projects = projects
        self.backups = backups
        self.backupsCount = backupsCount
        self.other = other
        self.diskUsedPct = diskUsedPct
        self.diskTotal = diskTotal
    }
}

/// What the Core page asks of the Core. The Pairing module implements it over the generated client.
public protocol CorePageSource: Sendable {
    /// Whether this Core has the routes (minor 95 and up).
    func supported() async -> Bool
    func prefs() async throws -> CorePagePrefs
    func set(name: String?, crashReports: Bool?, autoUpdate: Bool?, updateHour: Int?) async throws -> CorePagePrefs
    func storage() async throws -> CorePageStorage
    /// The backup schedule and history from the Core machine's helper; nil where the Core cannot say.
    func backups() async throws -> CoreBackups?
    /// Starts a backup on the Core machine.
    func backupNow() async throws
    /// How many backups the Core keeps, with the range it accepts; nil where the Core cannot say (no retention route).
    func backupRetention() async -> CoreBackupRetention?
    /// Sets how many backups the Core keeps (needs a step-up); returns what it now keeps.
    func setBackupRetention(_ keep: Int) async throws -> Int?
}

extension CorePageSource {
    public func backups() async throws -> CoreBackups? { nil }
    public func backupNow() async throws {}
    public func backupRetention() async -> CoreBackupRetention? { nil }
    public func setBackupRetention(_ keep: Int) async throws -> Int? { nil }
}

/// State behind the Core page's tabs. Without a source, or on an older Core, `supported` is false and the page shows
/// the read-only facts it already has.
@MainActor @Observable
public final class CorePageModel {
    public var source: (any CorePageSource)? {
        didSet { if source == nil { reset() } }
    }
    public private(set) var supported = false
    public private(set) var prefs = CorePagePrefs()
    public private(set) var storage: CorePageStorage?
    public private(set) var failure: String?
    public private(set) var backups: CoreBackups?
    public private(set) var backupStarting = false
    /// One line about the last "Back up now".
    public private(set) var backupNote: String?
    /// How many backups the Core keeps and the range it accepts; nil on a Core without the retention route.
    public private(set) var retention: CoreBackupRetention?
    /// Runs an action behind Touch ID (the app sets it). Throws `CancellationError` when the person did not unlock.
    public var gate: (@MainActor (String, @escaping @MainActor () async throws -> Void) async throws -> Void)?
    public init() {}

    private func reset() {
        supported = false
        prefs = CorePagePrefs()
        storage = nil
        backups = nil
        retention = nil
        backupNote = nil
    }

    public func load() async {
        guard let source else { return }
        supported = await source.supported()
        guard supported else { return }
        do { prefs = try await source.prefs() } catch { failure = Self.words(error) }
    }

    public func loadStorage() async {
        guard let source, await source.supported() else { return }
        do { storage = try await source.storage() } catch { failure = Self.words(error) }
    }

    public func loadBackups() async {
        guard let source, await source.supported() else { return }
        do { backups = try await source.backups() } catch { failure = Self.words(error) }
        retention = await source.backupRetention()
    }

    /// Sets how many backups the Core keeps, behind Touch ID, and keeps what the Core answers. A decline changes nothing.
    public func setKeep(_ keep: Int) async {
        guard let source, supported, let r = retention, keep != r.keep, (r.min...r.max).contains(keep) else { return }
        let change: @MainActor () async throws -> Void = { [weak self] in
            let now = try await source.setBackupRetention(keep)
            self?.retention?.keep = now ?? keep
        }
        do {
            if let gate {
                try await gate("Change how many backups your Core keeps.", change)
            } else {
                try await change()
            }
            backupNote = "Your Core keeps the last \(retention?.keep ?? keep) backups."
            failure = nil
        } catch is CancellationError {
        } catch {
            failure = Self.words(error)
            if let again = await source.backupRetention() { retention = again }
        }
    }

    /// Starts a backup, then reads the schedule again so the page shows it running.
    public func backupNow() async {
        guard let source, supported, !backupStarting else { return }
        backupStarting = true
        defer { backupStarting = false }
        do {
            try await source.backupNow()
            backupNote = "Backup started. It finishes by itself."
            failure = nil
            if let again = try? await source.backups() { backups = again }
        } catch { failure = Self.words(error) }
    }

    /// Saves one change and keeps what the Core answers, so the page never shows a value the Core refused.
    public func save(
        name: String? = nil, crashReports: Bool? = nil, autoUpdate: Bool? = nil, updateHour: Int? = nil
    ) async {
        guard let source, supported else { return }
        do {
            prefs = try await source.set(
                name: name, crashReports: crashReports, autoUpdate: autoUpdate, updateHour: updateHour)
            failure = nil
        } catch {
            failure = Self.words(error)
            if let again = try? await source.prefs() { prefs = again }
        }
    }

    #if DEBUG
    /// Demo scenes: the Core's preferences without a Core; `supported: false` plays an older Core.
    public func debugSet(prefs: CorePagePrefs, supported: Bool = true) {
        self.supported = supported
        self.prefs = prefs
    }
    #endif

    static func words(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "The Core did not accept that."
    }
}
