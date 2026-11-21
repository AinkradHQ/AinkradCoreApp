import CoreKit
import Foundation
import Shell

/// Keeps `shell.coreUpdate` current from `GET /system/update` (E12-3) and starts an update from the Core pop-up. Polls
/// slowly while nothing runs and every two seconds while an update does, because the Core restarts in the middle of one:
/// the status file survives it, so the first answer after the Core is back is the truth.
@MainActor
final class CoreUpdateFeed {
    private let shell: ShellModel
    private let connection: CoreConnection
    /// Runs the POST after Touch ID (`AppModel.elevated`): it is a danger route.
    private let elevated: @MainActor (@escaping () async throws -> Void) async throws -> Void
    private var task: Task<Void, Never>?

    init(
        shell: ShellModel, connection: CoreConnection,
        elevated: @escaping @MainActor (@escaping () async throws -> Void) async throws -> Void
    ) {
        self.shell = shell
        self.connection = connection
        self.elevated = elevated
    }

    func start() {
        shell.startCoreUpdate = { [weak self] in Task { await self?.begin() } }
        shell.coreUpdateNews = { [weak self] in self?.showNews() }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                let running = self?.shell.coreUpdate.running ?? false
                try? await Task.sleep(for: .seconds(running ? 2 : 120))
            }
        }
    }

    func stop() {
        task?.cancel()
        shell.startCoreUpdate = nil
        shell.coreUpdateNews = nil
        shell.coreUpdate = CoreUpdateStatus()
    }

    func poll() async {
        guard await connection.serverSupports(minor: coreMinorV010) else { return }
        guard let data = try? await connection.signedRequest(method: "GET", target: "/api/v1/system/update"),
            let s = CoreUpdateStatus.decode(data)
        else { return }
        if s != shell.coreUpdate { shell.coreUpdate = s }
    }

    private func begin() async {
        do {
            try await elevated { [connection] in
                _ = try await connection.signedRequest(method: "POST", target: "/api/v1/system/update")
            }
            // Show the first step at once; the poll takes over.
            shell.coreUpdate.phase = .snapshot
            shell.coreUpdate.to = shell.coreUpdate.available ?? shell.coreUpdate.to
            await poll()
        } catch is StepUpDeclined {
            return
        } catch {
            // Plain words only: a cancel says nothing, the Core's 429 says when to try again (never "Too many requests").
            switch UpdatesOutcome.of(error) {
            case .silent: return
            case .wait(let s):
                let m = max(1, Int((s / 60).rounded(.up)))
                shell.showToast("Core needs \(m == 1 ? "a minute" : "\(m) minutes") before the next try.", kind: .info)
            case .words(let w): shell.showToast(w, kind: .warn)
            }
        }
    }

    private func showNews() {
        let to = shell.coreUpdate.to ?? shell.coreUpdate.current
        shell.presentSheet(
            title: "Core is on \(to)",
            message: "Updates install by themselves at night: the app, the Core and the runners.",
            actions: [ShellSheetAction("Done", primary: true)])
    }
}
