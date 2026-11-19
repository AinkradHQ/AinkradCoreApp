import Admin
import CoreKit
import CoreUI
import Foundation
import Shell
import SwiftUI

/// Run control and Project Settings writes (P7-05): Start, Stop and Restart on the Core's run routes, the watch that keeps the
/// open project's run fresh and its idle timer pushed back, General and Archive. Each change is behind Touch ID.
extension ProjectsModel {
    /// The project with its run as the Core last said it: state, idle timer, progress and why a start failed.
    func applying(_ p: ProjectItem) -> ProjectItem {
        guard let r = runStates[p.id] else { return p }
        var p = p
        var live = p.live ?? ProjectLive()
        p.run = RunSummary(
            state: r.summary.state, services: live.services.count, sessions: live.sessions.count,
            lastRun: r.summary.lastRun)
        let remaining = r.idleStopAt.map { Int(ceil($0.timeIntervalSince(now()) / 60)) }
        live.idle =
            r.summary.state == .running
            ? remaining.map { "idle \(max(0, p.idleMinutes - $0)) min of \(p.idleMinutes)" } : nil
        // ponytail: the Core gives no start progress, so the bar eases toward 90% over a minute; replace with real steps (P5-04).
        live.progress = min(0.9, now().timeIntervalSince(r.startedAt) / 60)
        live.progressLine = "Starting on \(coreName)…"
        live.failure = r.summary.state == .failed ? (r.error ?? Self.reason(r.stopReason)) : nil
        live.failureFix = r.summary.state == .failed ? "Check the run setup, then start it again." : nil
        p.live = live
        return p
    }

    static func reason(_ code: String?) -> String {
        switch code {
        case "runner_lost": "The machine running it went offline."
        case "crash": "It stopped by itself."
        default: "The last start failed."
        }
    }

    /// The gallery's cards after the Filter field.
    var shown: [ProjectItem] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty
            ? projects : projects.filter { $0.name.lowercased().contains(q) || $0.slug.contains(q) }
    }

    /// A refusal of a run route, in words (`words` reads a 409 as a taken link name, which is not what a run says).
    func runWords(_ error: any Error) -> String {
        guard let e = CoreFailure.of(error) ?? CoreError.unwrapping(error) else { return words(error) }
        switch e {
        case .http(_, "no_runner", _): return "No runner can run projects right now. Start or pair one, then try again."
        case .http(404, _, _): return "This project has no run set up yet. Add its repos first."
        case .http(409, _, _): return "It is already running, or the project is archived."
        case .http(502, _, _): return "The runner did not do that. Try again."
        default: return words(error)
        }
    }

    /// Start, Stop and Restart, behind Touch ID like every other change to the Core. The Debug demo answers on its own.
    func control(_ action: RunAction, _ project: ProjectItem) {
        #if DEBUG
        if service is ProjectsDemo.Service { return demoControl(action, project) }
        #endif
        Task { await runControl(action, project) }
    }

    func runControl(_ action: RunAction, _ project: ProjectItem) async {
        guard let service, !controlling.contains(project.id), mayWrite() else { return }
        let (verb, done): (String, String) =
            switch action {
            case .start: ("Start", "started")
            case .stop: ("Stop", "stopped")
            case .restart: ("Restart", "restarted")
            }
        controlling.insert(project.id)
        defer { controlling.remove(project.id) }
        do {
            let r = try await host.elevated("\(verb) \(project.name) on \(coreName).", done: done, keepsEdit: false) {
                try await service.control(project: project.id, action)
            }
            runStates[project.id] = r
            await reload()
        } catch is AdminDeclined {
        } catch {
            if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
            host.shell.showToast(runWords(error), kind: .warn)
        }
    }

    /// Reads one project's run again.
    func refreshRun(_ id: Int64) async {
        guard let service, let r = try? await service.run(project: id) else { return }
        runStates[id] = r
        if let i = projects.firstIndex(where: { $0.id == id }) { projects[i] = applying(projects[i]) }
    }

    /// Keeps the open project's run fresh while it starts (every 2 s) or runs (every minute; while its Overview or Run page is
    /// up that also tells the Core a viewer is there, which pushes the idle stop back). Returns once it is neither.
    func watch(_ id: Int64) async {
        while !Task.isCancelled, let service {
            await refreshRun(id)
            switch project(id)?.tag {
            case .some(.starting):
                try? await Task.sleep(for: .seconds(2))
            case .some(.running):
                if section == .overview || section == .run, let r = try? await service.touch(project: id) {
                    runStates[id] = r
                    if let i = projects.firstIndex(where: { $0.id == id }) { projects[i] = applying(projects[i]) }
                }
                try? await Task.sleep(for: .seconds(60))
            default:
                return
            }
        }
    }

    /// Whether Start, Stop and Restart can be tried now.
    func canControl(_ project: ProjectItem) -> Bool {
        service != nil && !readOnly && !controlling.contains(project.id)
    }

    /// General in Project Settings: the name and the description, behind Touch ID.
    @discardableResult
    func saveGeneral(_ project: ProjectItem, name: String, description: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard let service, !busy, mayWrite() else { return false }
        if let problem = ProjectRules.nameProblem(name) {
            writeError = problem
            return false
        }
        busy = true
        writeError = nil
        defer { busy = false }
        do {
            try await host.elevated("Save the name and description of \(project.name).", done: "saved", keepsEdit: true)
            {
                try await service.update(project: project.id, name: name, description: description)
            }
        } catch is AdminDeclined {
            return false
        } catch {
            if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
            writeError = words(error)
            return false
        }
        await reload()
        host.shell.showToast("Saved")
        return true
    }

    /// Archive Project…: asks once, then stops the run and hides the project; the space closes.
    func confirmArchive(_ project: ProjectItem) {
        let shell = host.shell
        shell.present(
            ShellDialog(id: "project-archive") {
                CoreConfirmDialog(
                    "Archive \(project.name)?",
                    message:
                        "Its run stops and it leaves the Projects list. Repos, secrets and the Brain room are kept.",
                    confirmTitle: "Archive", destructive: true,
                    onConfirm: { [weak self] in
                        shell.closeDialog()
                        Task { await self?.archive(project) }
                    }, onCancel: { shell.closeDialog() })
            })
    }

    func archive(_ project: ProjectItem) async {
        guard let service, !busy, mayWrite() else { return }
        busy = true
        defer { busy = false }
        do {
            try await host.elevated(
                "Archive \(project.name). Its run stops and it leaves the Projects list.", done: "archived",
                keepsEdit: false
            ) { try await service.archive(project: project.id) }
        } catch is AdminDeclined {
            return
        } catch {
            host.shell.showToast(runWords(error), kind: .warn)
            return
        }
        closeProject()
        host.shell.closePane(Self.paneID(project.id))
        await reload()
        host.shell.showToast("\(project.name) archived")
    }

}
