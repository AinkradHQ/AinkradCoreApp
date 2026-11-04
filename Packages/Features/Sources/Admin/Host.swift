import Foundation
import Shell

/// What the admin screens need from the app that owns the connection: the shell, Touch ID through the one sheet, and whether
/// changes are paused (the Core is unreachable or rate limiting).
@MainActor
public protocol AdminHost: AnyObject {
    var shell: ShellModel { get }
    /// Why changes are paused right now (offline, rate limited), or nil.
    var pausedReason: String? { get }
    /// The inline outcome of the last Touch ID that did not elevate; cleared by the next attempt.
    var elevationNotice: AdminNotice? { get }
    func clearElevationNotice()
    /// Runs `op` elevated: Touch ID first when needed, once more when the Core still says `step_up_required`. Throws
    /// `AdminDeclined` when the person did not elevate (`elevationNotice` says why).
    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T
    /// The Core answered 429: the shell shows its banner with the wait.
    func rateLimited(retryAfter: TimeInterval?)
}
