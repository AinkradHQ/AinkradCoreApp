import Shell
import Terminals

/// What the terminal screens use of the app: the shell, and Touch ID through the one sheet.
@MainActor
final class TerminalHostAdapter: TerminalHost {
    private unowned let app: AppModel
    init(app: AppModel) { self.app = app }

    var shell: ShellModel { app.shell }
    var isElevated: Bool { app.isElevated }

    var elevationNotice: ElevationNotice? {
        app.stepUpNotice.map { ElevationNotice(title: $0.title, detail: $0.detail, symbol: $0.symbol, tone: $0.tone) }
    }

    func clearElevationNotice() { app.stepUpNotice = nil }

    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T {
        do { return try await app.elevated(reason, done: done, keepsEdit: keepsEdit, op) } catch is StepUpDeclined {
            throw ElevationDeclined()
        }
    }
}
