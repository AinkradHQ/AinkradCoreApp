import Admin
import Foundation
import Shell

/// What the admin screens use of the app: the shell, Touch ID through the one sheet, and whether changes are paused.
@MainActor
final class AdminHostAdapter: AdminHost {
    private unowned let app: AppModel
    init(app: AppModel) { self.app = app }

    var shell: ShellModel { app.shell }

    var pausedReason: String? {
        if case .rateLimited? = app.shell.linkNotice {
            return "Too many requests. Changes are paused until the limit lifts."
        }
        switch app.shell.coreLink {
        case .offline, .reconnecting:
            return "Changes are paused while Home Core is unreachable. They resume when it is back."
        default: return nil
        }
    }

    var elevationNotice: AdminNotice? {
        app.stepUpNotice.map {
            AdminNotice(title: $0.title, detail: $0.detail, symbol: $0.symbol, warn: $0.tone == .warn)
        }
    }

    func clearElevationNotice() { app.stepUpNotice = nil }

    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T {
        do { return try await app.elevated(reason, done: done, keepsEdit: keepsEdit, op) } catch is StepUpDeclined {
            throw AdminDeclined()
        }
    }

    func rateLimited(retryAfter: TimeInterval?) { app.noteRateLimit(retryAfter) }
}
