import Agents
import CoreKit
import Foundation
import Shell
import Terminals

/// What the terminal screens use of the app: the shell, and Touch ID through the one sheet.
@MainActor
final class TerminalHostAdapter: TerminalHost, RunnerHost {
    private unowned let app: AppModel
    init(app: AppModel) { self.app = app }

    var shell: ShellModel { app.shell }
    var isElevated: Bool { app.isElevated }
    var thisMacRunnerID: String? { app.macRunner.runnerID }

    var elevationNotice: ElevationNotice? {
        app.stepUpNotice.map { ElevationNotice(title: $0.title, detail: $0.detail, symbol: $0.symbol, tone: $0.tone) }
    }

    func clearElevationNotice() { app.stepUpNotice = nil }

    /// The runner inside this app, once it is registered and running: its terminals can be reached over its own sockets.
    var localRunner: LocalRunner? {
        guard let mac = app.macRunner, mac.state == .running, mac.terminals, let id = mac.runnerID else { return nil }
        return LocalRunner(id: id, terminals: MacRunnerModel.terminalsDirectory())
    }

    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T {
        do { return try await app.elevated(reason, done: done, keepsEdit: keepsEdit, op) } catch is StepUpDeclined {
            throw ElevationDeclined()
        }
    }

    // MARK: runner page (N18, N19)

    func agentWork(on runner: String) -> [RunnerWork] {
        let now = Date()
        return app.agents.sessions.items.filter { $0.live && $0.runner == runner }.map { s in
            let minutes = max(0, Int(now.timeIntervalSince(s.createdAt) / 60))
            return RunnerWork(
                id: s.id, title: app.agents.title(s),
                detail: "\(AgentWords.harnessName(s.harness)) · running \(minutes) min", minutes: minutes)
        }
    }

    func openAgent(_ id: String) { app.agents.openSession(id) }
    func startAgent(on runner: String) { app.agents.openNewSession(runner: runner) }

    /// Add a runner: the guided flow, at the install screen for a Linux server (the runner invite is not in Core yet).
    func addRunner() { app.openAddWizard(kind: .linuxRunner) }

    func people() -> [RunnerPerson] {
        (app.devices?.active ?? []).filter { $0.kind != "runner" }.map {
            RunnerPerson(id: $0.id, name: $0.name, kind: $0.kind, platform: $0.platform, scopes: $0.scopes)
        }
    }

    func renameRunner(_ id: String, to name: String) async -> String? {
        guard let devices = app.devices else { return "Not connected to a Core." }
        if devices.items.isEmpty { await devices.reload() }
        guard let d = devices.items.first(where: { $0.id == id }) else { return "The Core does not list this runner." }
        if await devices.rename(d, to: name) { return nil }
        return devices.dialogError ?? "The runner was not renamed."
    }

    func revokeRunner(_ id: String) async -> String? {
        guard let devices = app.devices else { return "Not connected to a Core." }
        if devices.items.isEmpty { await devices.reload() }
        guard let d = devices.items.first(where: { $0.id == id }) else { return "The Core does not list this runner." }
        if await devices.revoke(d) { return nil }
        return devices.dialogError ?? "Touch ID did not go through, so the runner was not revoked."
    }
}
