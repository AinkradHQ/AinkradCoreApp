import CoreKit
import Foundation

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
    /// The runner on the Core's own host (`built_in`): it updates with the Core. This Mac's runner is not this one; the
    /// model knows it by id (`UpdatesModel.macRunnerID`).
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
    /// The Core host's runner: it is swapped by the Core's own update.
    case withCore
    /// This Mac's runner: it comes inside the app and updates with it. Never an Update button.
    case withApp
    /// Waiting its turn in Update everything.
    case queued
    /// Asked to update; its updater has not said it started yet.
    case asked
    case updating
    case behind
    case offline
    case upToDate
}

/// The Core's own update as this tab follows it: the four steps the person sees (the Core's status file has three; Restart
/// is the gap while the Core comes back), when each began, and whether the connection is down right now.
public struct CoreRun: Equatable, Sendable {
    public enum Step: Int, CaseIterable, Sendable {
        case snapshot, install, restart, health
        public var name: String { ["Snapshot", "Install", "Restart", "Health check"][rawValue] }
        /// Typical seconds per step (Core 0.10.3 on a small server: about 26 s in all). Only for the bars and "About n s
        /// left"; the Core's status moves the steps.
        public var expected: TimeInterval { [4, 8, 7, 6][rawValue] }
    }

    public var from: String
    public var to: String
    public var startedAt: Date
    public var step = Step.snapshot
    public var stepAt: Date
    /// Seconds each finished step took, by step.
    public var took: [Step: TimeInterval] = [:]
    /// The connection dropped (the Core restarts): since when. Nil while the Core answers.
    public var gapSince: Date?
    /// When the Core answered again after the gap.
    public var backAt: Date?

    public init(from: String, to: String, at: Date) {
        self.from = from
        self.to = to
        startedAt = at
        stepAt = at
    }

    /// Moves forward only; the steps skipped on the way count as done with no time.
    public mutating func move(to s: Step, at now: Date) {
        guard s.rawValue > step.rawValue else { return }
        took[step] = max(0, now.timeIntervalSince(stepAt))
        step = s
        stepAt = now
    }

    /// How full a step's bar is. The running step creeps toward its typical time and waits at 92 % for the Core.
    public func fill(_ s: Step, at now: Date) -> Double {
        if s.rawValue < step.rawValue { return 1 }
        if s.rawValue > step.rawValue { return 0 }
        return min(0.92, max(0, now.timeIntervalSince(stepAt) / s.expected))
    }

    /// The whole run, 0...1, for the map's small bar.
    public func progress(at now: Date) -> Double {
        let total = Step.allCases.map(\.expected).reduce(0, +)
        let done = Step.allCases.filter { $0.rawValue < step.rawValue }.map(\.expected).reduce(0, +)
        return min(1, (done + fill(step, at: now) * step.expected) / total)
    }

    /// Whole seconds left, never under 1 while it runs.
    public func secondsLeft(at now: Date) -> Int {
        let rest = Step.allCases.filter { $0.rawValue > step.rawValue }.map(\.expected).reduce(0, +)
        let here = max(1, step.expected - now.timeIntervalSince(stepAt))
        return max(1, Int((rest + here).rounded(.up)))
    }

    /// Whole seconds the connection has been down, counting from 1.
    public func gapSeconds(at now: Date) -> Int? {
        gapSince.map { max(1, Int(now.timeIntervalSince($0)) + 1) }
    }
}

/// The last Update everything that went through: what the done card says.
public struct UpdatesFinished: Equatable, Sendable {
    public var version: String
    public var runners: Int
    public var seconds: Int
    public init(version: String, runners: Int, seconds: Int) {
        self.version = version
        self.runners = runners
        self.seconds = seconds
    }
}

/// What the one card at the top says, in the order it wins.
public enum UpdatesHero: Equatable, Sendable {
    case updating, wentBack, following, done, available, runner, macApp, upToDate
}

/// How an error reaches the person: not at all (a cancel, a declined Touch ID), as a wait (the Core's 429 `Retry-After`),
/// or in plain words. Raw errors (`listRunners … CancellationError()`) never show.
public enum UpdatesOutcome: Equatable, Sendable {
    case silent
    case wait(TimeInterval)
    case words(String)

    public static func of(_ error: any Error) -> UpdatesOutcome {
        if isCancellation(error) { return .silent }
        guard let core = CoreError.unwrapping(error) else { return .words(generic) }
        switch core {
        case .rateLimited(let after): return .wait(max(1, after ?? 60))
        case .stepUpCancelled: return .silent
        case .offline, .coreUnproven:
            return .words("The Core cannot be reached right now. This page tries again by itself.")
        case .http(_, _, let message): return .words(message.isEmpty ? generic : message)
        case .authFailed, .sessionExpired, .forbiddenScope, .unlockRequired, .stepUpRequired:
            return .words(core.errorDescription ?? generic)
        default: return .words(generic)
        }
    }

    static let generic = "The Core did not answer as expected. This page tries again by itself."

    /// A cancel anywhere inside what was thrown: Swift's, URLSession's, or one the generated client wrapped.
    static func isCancellation(_ error: any Error, depth: Int = 0) -> Bool {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return true }
        if let core = error as? CoreError { return core == .stepUpCancelled }
        guard depth < 6 else { return false }
        for child in Mirror(reflecting: error).children {
            if let inner = child.value as? any Error, isCancellation(inner, depth: depth + 1) { return true }
        }
        return String(describing: error).contains("CancellationError")
    }
}

/// What the Updates tab asks of the Core. The Pairing module implements it over the signed connection.
public protocol UpdatesSource: Sendable {
    /// Whether this Core has the update routes (Core 0.10).
    func supported() async -> Bool
    func check() async throws -> CoreUpdateCheck
    func runners() async throws -> [UpdatableRunner]
    /// `POST /runners/{id}/update` (needs a step-up; the gate asks for it).
    func updateRunner(_ id: String) async throws
    /// `GET /system/update`: the Core updater's status file. Throws while the Core restarts.
    func coreStatus() async throws -> CoreUpdateStatus
    /// `POST /system/update` (needs a step-up). The Core answers 429 with `Retry-After` when it wants a pause first.
    func startCore() async throws
}
