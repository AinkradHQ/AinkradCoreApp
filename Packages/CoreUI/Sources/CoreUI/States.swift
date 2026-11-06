import Foundation

/// Status colour family. A tone never stands alone: the label is always shown beside it.
public enum Tone: String, Sendable, Hashable, CaseIterable { case run, done, warn, fail, queue }

/// A Core API value shown to people: label, tone and SF Symbol come from `states.js`.
/// Every state keeps an unknown raw value (`case unknown(String)`) and shows it as its raw word, so a newer server never crashes an older client.
public protocol CoreState: RawRepresentable, Codable, Hashable, Sendable where RawValue == String {
    typealias Entry = (state: Self, raw: String, label: String, tone: Tone, symbol: String)
    static var table: [Entry] { get }
    static func unknown(_ raw: String) -> Self
    /// The raw value when this is `.unknown`.
    var unknownRaw: String? { get }
}

extension CoreState {
    static func parse(_ raw: String) -> Self { table.first { $0.raw == raw }?.state ?? unknown(raw) }
    public init(rawValue: String) { self = Self.parse(rawValue) }
    // Matched by case name, not `==`: RawRepresentable's `==` calls `rawValue`, which would recurse.
    private var entry: Entry? {
        let name = String(describing: self)
        return Self.table.first { String(describing: $0.state) == name }
    }
    public var rawValue: String { unknownRaw ?? entry?.raw ?? "" }
    public var label: String { entry?.label ?? rawValue }
    public var tone: Tone { entry?.tone ?? .queue }
    public var symbol: String { entry?.symbol ?? "questionmark.circle" }
    public init(from decoder: any Decoder) throws {
        self = Self.parse(try decoder.singleValueContainer().decode(String.self))
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// Provider accounts (KAN-421).
public enum AccountState: CoreState {
    case healthy, cooling, overBudget, expired, auth, disabled
    case unknown(String)
    public var unknownRaw: String? { if case .unknown(let r) = self { r } else { nil } }
    public static let table: [Entry] = [
        (.healthy, "healthy", "Ready", .run, "checkmark.circle"),
        (.cooling, "cooling", "Resting", .warn, "clock"),
        (.overBudget, "over_budget", "Budget reached", .warn, "gauge.with.dots.needle.100percent"),
        (.expired, "expired", "Sign in again", .fail, "person.crop.circle.badge.exclamationmark"),
        (.auth, "auth", "Sign-in failed", .fail, "exclamationmark.triangle"),
        (.disabled, "disabled", "Turned off", .queue, "pause.circle"),
    ]
}

/// `AgentSession.state`.
public enum SessionState: CoreState {
    case starting, running, interrupted, ended, lost
    case unknown(String)
    public var unknownRaw: String? { if case .unknown(let r) = self { r } else { nil } }
    public static let table: [Entry] = [
        (.starting, "starting", "Starting", .done, "hourglass"),
        (.running, "running", "Running", .run, "waveform"),
        (.interrupted, "interrupted", "Resuming", .warn, "arrow.clockwise"),
        (.ended, "ended", "Ended", .queue, "stop.circle"),
        (.lost, "lost", "Lost", .fail, "wifi.exclamationmark"),
    ]
}

/// `AgentSession.outcome`.
public enum SessionOutcome: CoreState {
    case succeeded, failed, stalled, tokenCap, cancelled, lost
    case unknown(String)
    public var unknownRaw: String? { if case .unknown(let r) = self { r } else { nil } }
    public static let table: [Entry] = [
        (.succeeded, "succeeded", "Succeeded", .run, "checkmark.circle"),
        (.failed, "failed", "Failed", .fail, "xmark.octagon"),
        (.stalled, "stalled", "Stalled", .warn, "tortoise"),
        (.tokenCap, "token_cap", "Token cap", .warn, "gauge.with.dots.needle.100percent"),
        (.cancelled, "cancelled", "Cancelled", .queue, "xmark.circle"),
        (.lost, "lost", "Lost", .fail, "wifi.exclamationmark"),
    ]
}

/// `Terminal.status` plus what this device sees.
public enum TerminalState: CoreState {
    case running, exited, reaped, orphaned, hostLost
    case unknown(String)
    public var unknownRaw: String? { if case .unknown(let r) = self { r } else { nil } }
    public static let table: [Entry] = [
        (.running, "running", "Running", .run, "terminal"),
        (.exited, "exited", "Exited", .queue, "checkmark.circle"),
        (.reaped, "reaped", "Closed", .queue, "xmark.circle"),
        (.orphaned, "orphaned", "Orphaned", .warn, "questionmark.circle"),
        (.hostLost, "host_lost", "Runner lost it", .fail, "wifi.exclamationmark"),
    ]
}

/// Citadel issue states.
public enum IssueState: CoreState {
    case backlog, todo, inProgress, inReview, blocked, done, cancelled
    case unknown(String)
    public var unknownRaw: String? { if case .unknown(let r) = self { r } else { nil } }
    public static let table: [Entry] = [
        (.backlog, "backlog", "Backlog", .queue, "tray"),
        (.todo, "todo", "To do", .queue, "circle.dashed"),
        (.inProgress, "in_progress", "In progress", .done, "play.circle"),
        (.inReview, "in_review", "In review", .done, "eye"),
        (.blocked, "blocked", "Blocked", .warn, "exclamationmark.triangle"),
        (.done, "done", "Done", .run, "checkmark.circle"),
        (.cancelled, "cancelled", "Cancelled", .queue, "xmark.circle"),
    ]
}

/// Citadel run states.
public enum RunState: CoreState {
    case queued, running, succeeded, failed, cancelled, timedOut, runnerLost
    case unknown(String)
    public var unknownRaw: String? { if case .unknown(let r) = self { r } else { nil } }
    public static let table: [Entry] = [
        (.queued, "queued", "Queued", .queue, "clock"),
        (.running, "running", "Running", .run, "waveform"),
        (.succeeded, "succeeded", "Succeeded", .run, "checkmark.circle"),
        (.failed, "failed", "Failed", .fail, "xmark.octagon"),
        (.cancelled, "cancelled", "Cancelled", .queue, "xmark.circle"),
        (.timedOut, "timed_out", "Timed out", .warn, "timer"),
        (.runnerLost, "runner_lost", "Runner lost", .fail, "wifi.exclamationmark"),
    ]
}
