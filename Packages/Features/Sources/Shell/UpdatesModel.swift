import Foundation
import Observation

/// What "Check now" found (`POST /core/update/check`). An older Core answers `feed_unavailable` without a reason, and a status
/// this app does not know reads as no feed, so the page never claims more than the Core said.
public struct CoreUpdateCheck: Equatable, Sendable {
    public enum Status: String, Sendable {
        case upToDate = "up_to_date"
        case available
        case feedUnavailable = "feed_unavailable"
    }
    public var at: Date
    public var status: Status
    public var current: String?
    public var latest: String?
    /// The newest runner version the feed offers; nil on a Core that does not say.
    public var latestRunner: String?
    /// Why the feed did not answer, in the Core's words; nil on an older Core.
    public var reason: String?
    public init(
        at: Date, status: Status, current: String? = nil, latest: String? = nil, latestRunner: String? = nil,
        reason: String? = nil
    ) {
        self.at = at
        self.status = status
        self.current = current
        self.latest = latest
        self.latestRunner = latestRunner
        self.reason = reason
    }

    /// The answer, read leniently so a newer Core's extra fields are used and an older Core's missing ones are not needed.
    public static func decode(_ data: Data) -> CoreUpdateCheck? {
        struct Wire: Decodable {
            var checked_at: String?
            var status: String?
            var current_version: String?
            var latest_version: String?
            var runner_latest_version: String?
            var reason: String?
        }
        guard let w = try? JSONDecoder().decode(Wire.self, from: data), let status = w.status else { return nil }
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let at = w.checked_at.flatMap { full.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } ?? Date()
        return CoreUpdateCheck(
            at: at, status: Status(rawValue: status) ?? .feedUnavailable, current: w.current_version,
            latest: w.latest_version, latestRunner: w.runner_latest_version,
            reason: w.reason)
    }
}

/// One runner as the Updates tab shows it (`GET /runners`).
public struct UpdatableRunner: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var version: String?
    public var online: Bool
    /// The Core's version is newer than the runner's (`update_available`).
    public var behind: Bool
    /// The runner's updater is swapping its programs now (`updating`).
    public var updating: Bool
    /// The runner inside this Mac app: it updates with the app.
    public var builtIn: Bool
    public init(
        id: String, name: String, version: String?, online: Bool = true, behind: Bool = false, updating: Bool = false,
        builtIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.online = online
        self.behind = behind
        self.updating = updating
        self.builtIn = builtIn
    }
}

/// Where one runner's update stands, in the order the row reads it.
public enum RunnerUpdateState: Equatable, Sendable {
    case updating, starting, behind, offline, withApp, upToDate
}

/// What the Updates tab asks of the Core. The Pairing module implements it over the signed connection.
public protocol UpdatesSource: Sendable {
    /// Whether this Core has the update routes (Core 0.10).
    func supported() async -> Bool
    func check() async throws -> CoreUpdateCheck
    func runners() async throws -> [UpdatableRunner]
    /// `POST /runners/{id}/update` (needs a step-up; the gate asks for it).
    func updateRunner(_ id: String) async throws
}

/// State behind Settings, Updates: the Core's check, every runner's version and update, and this app's own updater. The
/// Core's install itself is `ShellModel.coreUpdate` (polled from `GET /system/update`), shared with the Core pop-up.
@MainActor @Observable
public final class UpdatesModel {
    public var source: (any UpdatesSource)? {
        didSet { if source == nil { reset() } }
    }
    /// Runs an action behind Touch ID (the app sets it). Throws `CancellationError` when the person did not unlock.
    public var gate: (@MainActor (String, @escaping @MainActor () async throws -> Void) async throws -> Void)?
    public private(set) var supported = false
    public private(set) var checking = false
    public private(set) var check: CoreUpdateCheck?
    public private(set) var runners: [UpdatableRunner] = []
    /// Runners asked to update that have not started yet.
    public private(set) var asked: Set<String> = []
    public private(set) var failure: String?

    // This Mac app (Sparkle, set by the app target).
    public var appVersion = ""
    /// A downloaded version that installs on restart.
    public var appReady: String?
    public var checkApp: (@MainActor () -> Void)?
    public var installApp: (@MainActor () -> Void)?

    public init() {}

    private func reset() {
        supported = false
        check = nil
        runners = []
        asked = []
        failure = nil
    }

    public func load() async {
        guard let source else { return }
        supported = await source.supported()
        await loadRunners()
    }

    public func loadRunners() async {
        guard let source, supported else { return }
        do {
            runners = try await source.runners()
            // Asked runners leave "starting" once their updater runs or they are on the new version.
            asked = asked.filter { id in runners.first { $0.id == id }.map { $0.behind && !$0.updating } ?? false }
        } catch { failure = CorePageModel.words(error) }
    }

    public func checkNow() async {
        guard let source, supported, !checking else { return }
        checking = true
        defer { checking = false }
        do {
            check = try await source.check()
            failure = nil
        } catch { failure = CorePageModel.words(error) }
        await loadRunners()
    }

    public func state(_ r: UpdatableRunner) -> RunnerUpdateState {
        if r.updating { return .updating }
        if asked.contains(r.id) { return .starting }
        if r.builtIn && r.behind { return .withApp }
        if !r.online { return .offline }
        return r.behind ? .behind : .upToDate
    }

    /// The runners an Update all would ask.
    public var behind: [UpdatableRunner] { runners.filter { state($0) == .behind } }

    /// Asks one runner to update, behind Touch ID. A decline changes nothing.
    public func update(runner id: String) async {
        await update([id], reason: "Update this runner.")
    }

    /// Asks every runner that is behind, under one Touch ID.
    public func updateAllBehind() async {
        let ids = behind.map(\.id)
        guard !ids.isEmpty else { return }
        await update(ids, reason: ids.count == 1 ? "Update this runner." : "Update \(ids.count) runners.")
    }

    private func update(_ ids: [String], reason: String) async {
        guard let source, supported else { return }
        let run: @MainActor () async throws -> Void = { [weak self] in
            for id in ids {
                try await source.updateRunner(id)
                self?.asked.insert(id)
            }
        }
        do {
            if let gate { try await gate(reason, run) } else { try await run() }
            failure = nil
        } catch is CancellationError {
        } catch { failure = CorePageModel.words(error) }
        await loadRunners()
    }

    /// Keeps the runners fresh while the tab shows: every few seconds while one updates, else now and then.
    public func watch() async {
        await load()
        while !Task.isCancelled {
            let busy = !asked.isEmpty || runners.contains { $0.updating }
            try? await Task.sleep(for: .seconds(busy ? 3 : 30))
            await loadRunners()
        }
    }

    /// The line beside Check now. `lastChecked` is the Core's record of the last check, for before one ran here.
    public func checkWords(lastChecked: Date?) -> String {
        guard supported else { return "This Core is too old to check for updates." }
        if checking { return "Checking…" }
        guard let c = check else {
            return lastChecked.map { "Last checked \($0.formatted(.relative(presentation: .named)))" }
                ?? "Not checked yet"
        }
        switch c.status {
        case .upToDate: return "Up to date. Checked just now."
        case .available: return c.latest.map { "Core \($0) is ready." } ?? "A new version is ready."
        case .feedUnavailable:
            return c.reason.map { "Checked. \($0)" } ?? "Checked. No release feed is set up on this Core yet."
        }
    }

    #if DEBUG
    /// Demo scenes: made-up runners and a check result, no Core reached.
    public func debugSet(check: CoreUpdateCheck?, runners: [UpdatableRunner], asked: Set<String> = []) {
        supported = true
        self.check = check
        self.runners = runners
        self.asked = asked
    }
    #endif
}
