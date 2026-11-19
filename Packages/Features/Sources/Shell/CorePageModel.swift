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
    /// Runs "check now": when it ran, and whether a release feed answered.
    func checkUpdate() async throws -> (at: Date, feed: Bool)
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
    public private(set) var checking = false
    /// One line about the last check: "No release feed yet", or nil.
    public private(set) var checkNote: String?
    public private(set) var failure: String?
    public init() {}

    private func reset() {
        supported = false
        prefs = CorePagePrefs()
        storage = nil
        checkNote = nil
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

    public func checkNow() async {
        guard let source, supported, !checking else { return }
        checking = true
        defer { checking = false }
        do {
            let r = try await source.checkUpdate()
            prefs.updateCheckedAt = r.at
            checkNote = r.feed ? "Checked just now." : "Checked. No release feed is set up on this Core yet."
            failure = nil
        } catch { failure = Self.words(error) }
    }

    static func words(_ error: Error) -> String { (error as? LocalizedError)?.errorDescription ?? "The Core did not accept that." }
}
