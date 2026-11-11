import CoreUI
import Foundation
import Shell

/// The person said no to Touch ID, or it did not elevate: the action did not run.
public struct ElevationDeclined: Error {
    public init() {}
}

/// Why an elevated action did not run, in words, for the panel that asked to show inline.
public struct ElevationNotice: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var symbol: String
    public var tone: Tone
    public init(title: String, detail: String, symbol: String, tone: Tone) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.tone = tone
    }
}

/// What the terminal screens need from the app that owns the connection: the shell, and Touch ID through the one sheet.
@MainActor
public protocol TerminalHost: AnyObject {
    var shell: ShellModel { get }
    /// Whether the session is elevated right now.
    var isElevated: Bool { get }
    /// The inline outcome of the last Touch ID that did not elevate; cleared by the next attempt.
    var elevationNotice: ElevationNotice? { get }
    func clearElevationNotice()
    /// Runs `op` elevated: Touch ID first when needed, once more when the Core still says `step_up_required`. Throws
    /// `ElevationDeclined` when the person did not elevate (`elevationNotice` says why).
    /// `keepsEdit`: the person's input is still on screen (a form), so the notice may say so.
    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T
}

extension TerminalHost {
    func elevated<T>(_ reason: String, done: String, _ op: () async throws -> T) async throws -> T {
        try await elevated(reason, done: done, keepsEdit: false, op)
    }
}

/// One thing running on a runner that is not a terminal: an agent session.
public struct RunnerWork: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var detail: String
    public var minutes: Int
    public init(id: String, title: String, detail: String, minutes: Int) {
        self.id = id
        self.title = title
        self.detail = detail
        self.minutes = minutes
    }
}

/// A person's device that reaches the Core, for the runner page's "Who may use it".
public struct RunnerPerson: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var kind: String
    public var platform: String?
    public var scopes: [String]
    public init(id: String, name: String, kind: String, platform: String? = nil, scopes: [String]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.platform = platform
        self.scopes = scopes
    }
}

/// What the runner page needs from the app beyond terminals: agent work, devices, and the devices API (rename, revoke).
/// The defaults say "nothing known", so a host that has none still works.
@MainActor
public protocol RunnerHost: AnyObject {
    func agentWork(on runner: String) -> [RunnerWork]
    func openAgent(_ id: String)
    func startAgent(on runner: String)
    func addRunner()
    func people() -> [RunnerPerson]
    /// nil when it worked, else the reason in words.
    func renameRunner(_ id: String, to name: String) async -> String?
    func revokeRunner(_ id: String) async -> String?
}

extension TerminalHost {
    var runnerHost: (any RunnerHost)? { self as? any RunnerHost }
}
