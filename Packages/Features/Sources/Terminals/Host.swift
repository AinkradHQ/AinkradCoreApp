import CoreUI
import Foundation
import Shell
import SwiftUI

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

/// The runner that lives on this Mac (the one the app installed): terminals on it are attached through its own Unix sockets,
/// without a round trip to the Core.
public struct LocalRunner: Equatable, Sendable {
    /// The runner's device id in the Core.
    public var id: String
    /// The runner's terminal folder (`<state>/terminals`), where each host keeps `<terminal>.local.sock`.
    public var terminals: URL
    public init(id: String, terminals: URL) {
        self.id = id
        self.terminals = terminals
    }
}

/// What the terminal screens need from the app that owns the connection: the shell, and Touch ID through the one sheet.
@MainActor
public protocol TerminalHost: AnyObject, Sendable {
    var shell: ShellModel { get }
    /// Whether the session is elevated right now.
    var isElevated: Bool { get }
    /// The inline outcome of the last Touch ID that did not elevate; cleared by the next attempt.
    var elevationNotice: ElevationNotice? { get }
    func clearElevationNotice()
    /// The runner on this Mac, when the app runs one that is up; nil otherwise (every terminal then goes through the Core).
    var localRunner: LocalRunner? { get }
    /// Runs `op` elevated: Touch ID first when needed, once more when the Core still says `step_up_required`. Throws
    /// `ElevationDeclined` when the person did not elevate (`elevationNotice` says why).
    /// `keepsEdit`: the person's input is still on screen (a form), so the notice may say so.
    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T
    /// The id of the runner that is this Mac's own (built into the app), for the "This Mac" badge; nil when there is none.
    var thisMacRunnerID: String? { get }
}

extension TerminalHost {
    var localRunner: LocalRunner? { nil }
    public var thisMacRunnerID: String? { nil }
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
    /// The AI tool that runs it ("Claude"), for the Machines row's line; nil when not known.
    public var tool: String?
    public init(id: String, title: String, detail: String, minutes: Int, tool: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.minutes = minutes
        self.tool = tool
    }
}

/// Where Add machine starts.
public enum AddMachineStart: Equatable, Sendable {
    /// The three choices: This Mac, a server or another Mac, a phone or iPad.
    case pick
    /// A server or another Mac, with the machine's name already filled in (a Mac that only signs in: "Run work here").
    case server(name: String?)
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
    func addMachine(_ start: AddMachineStart)
    func people() -> [RunnerPerson]
    /// The phones, iPads and Macs that only sign in; nil before the Core answered (or when not connected).
    func signInMachines() -> [SignInMachine]?
    func reloadSignInMachines() async
    /// A sign-in machine's own page (what it may do, rename, remove), drawn by the app that owns devices.
    func signInPage(_ id: String, back: @escaping @MainActor () -> Void) -> AnyView
    /// This Mac's work switch and its options, for the This Mac page; nil when this build has no runner inside.
    func thisMacWork() -> AnyView?
    /// nil when it worked, else the reason in words.
    func renameRunner(_ id: String, to name: String) async -> String?
    func revokeRunner(_ id: String) async -> String?
}

extension RunnerHost {
    public func signInMachines() -> [SignInMachine]? { nil }
    public func reloadSignInMachines() async {}
    public func signInPage(_ id: String, back: @escaping @MainActor () -> Void) -> AnyView { AnyView(EmptyView()) }
    public func thisMacWork() -> AnyView? { nil }
}

extension TerminalHost {
    var runnerHost: (any RunnerHost)? { self as? any RunnerHost }
}
