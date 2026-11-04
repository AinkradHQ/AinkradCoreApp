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
