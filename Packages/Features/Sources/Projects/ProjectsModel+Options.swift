import Admin
import CoreKit
import Foundation
import Shell

/// Settings, Apps, Projects, Options (E2-4): what a run gets, read from and saved to the Core, and Unarchive.
extension ProjectsModel {
    /// The words under the limits while they are not there to pick.
    var limitsNote: String {
        switch limitsState {
        case .loading: "Reading the Core…"
        case .unsupported: "This Core is older than the one that sets what a project may use. Update it to set them here."
        case .failed: "The Core did not answer. Open this page again to retry."
        case .ready: ""
        }
    }

    func loadLimits() async {
        guard let service else {
            limitsState = .loading
            return
        }
        do {
            if let l = try await service.limits() {
                limits = l
                limitsState = .ready
            } else {
                limitsState = .unsupported
            }
        } catch { limitsState = .failed }
    }

    /// One choice of "When a project runs": saved for every project behind Touch ID. The page shows the new value at once and
    /// goes back to what the Core holds when the save does not happen.
    func saveLimits(_ change: (inout ProjectLimits) -> Void) {
        guard let service, var next = limits, mayWrite() else { return }
        let before = next
        change(&next)
        guard next != before else { return }
        limits = next
        Task {
            do {
                try await host.elevated(
                    "Change what a running project may use. It applies to every project.", done: "saved", keepsEdit: false
                ) { try await service.setLimits(next) }
                await reload()
            } catch is AdminDeclined {
                limits = before
            } catch {
                limits = before
                if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
                host.shell.showToast(words(error), kind: .warn)
            }
        }
    }

    /// Unarchive on an archived project: it is active again, with its repos, secrets and notes.
    func unarchive(_ project: ProjectItem) async {
        guard let service, !busy, mayWrite() else { return }
        busy = true
        defer { busy = false }
        do {
            try await host.elevated(
                "Bring \(project.name) back to the Projects list.", done: "restored", keepsEdit: false
            ) { try await service.unarchive(project: project.id) }
        } catch is AdminDeclined {
            return
        } catch {
            host.shell.showToast(runWords(error), kind: .warn)
            return
        }
        await reload()
        host.shell.showToast("\(project.name) is back")
    }
}
