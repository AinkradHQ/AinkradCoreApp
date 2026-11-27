import Admin
import CoreKit
import CoreUI
import Foundation
import Shell
import SwiftUI

/// Run control and Project Settings writes (P7-05): Start, Stop and Restart on the Core's run routes, the watch that keeps the
/// open project's run fresh and its idle timer pushed back, General and Archive. Each change is behind Touch ID.
extension ProjectsModel {
    /// The project with what the Core last said of it: its setup, its run (state, idle timer, start progress, why it ended) and,
    /// for the open one, the services, sessions and room the Overview shows.
    func applying(_ p: ProjectItem) -> ProjectItem {
        var p = p
        if let s = setupStates[p.id] {
            p.draft = s.draft
            p.setupChecked = true
        }
        p.stale = isStale
        var live = p.live ?? ProjectLive()
        let parts = liveParts[p.id]
        if let parts {
            live.services = parts.services
            live.sessions = parts.sessions
            live.room = parts.room
            live.roomID = parts.roomID
            live.metrics = parts.metrics
        }
        live.stale = p.stale
        p.crash = core110 ? crash(for: p.id, run: runStates[p.id]) : nil
        guard let r = runStates[p.id] else {
            if parts != nil { p.live = live }
            return p
        }
        let planned = max(live.services.count, p.draft?.services.count ?? 0)
        p.run = RunSummary(
            state: r.summary.state, services: planned, sessions: live.sessions.count, lastRun: r.summary.lastRun)
        let remaining = r.idleStopAt.map { Int(ceil($0.timeIntervalSince(now()) / 60)) }
        live.idle =
            r.summary.state == .running && !p.idleNever
            ? remaining.map { "idle \(max(0, p.idleMinutes - $0)) min of \(p.idleMinutes)" } : nil
        // No guessed easing: the bar is the services the Core reports up of the services the setup has, and nothing when it
        // reports none yet. `live.steps` are the Core's own start steps (API 110).
        let up = live.services.filter { $0.state == .up }.count
        let total = p.draft?.services.count ?? live.services.count
        live.progress = total > 0 && !live.services.isEmpty ? Double(up) / Double(total) : nil
        let where_ = runnerName(r.runner) ?? coreName
        live.progressLine =
            total > 0 && !live.services.isEmpty
            ? "Starting on \(where_) · \(up) of \(ProjectItem.count(total, "service")) up" : "Starting on \(where_)…"
        live.steps = r.steps.map { StartStep(title: $0.title, state: $0.state, detail: $0.detail) }
        // The step the Core says is under way names how far it is ("2 of 3 services up"): that is the honest line.
        if let d = r.steps.first(where: { $0.state == .active })?.detail {
            live.progressLine = "Starting on \(where_) · \(d)"
        }
        live.runner = runnerName(r.runner)
        live.lastActivity = r.lastActivityAt
        live.stopWords = r.summary.state == .stopped ? Self.reason(r.stopReason) : nil
        let crashLoop = parts?.crashLoop == true
        live.failure =
            r.summary.state == .failed || crashLoop
            ? (crashLoop ? Self.crashLoopWords : r.error ?? Self.reason(r.stopReason)) : nil
        live.failureFix =
            live.failure == nil
            ? nil
            : crashLoop
                ? "Read the log of the last run, fix what stops it, then start it again."
                : "Check the run setup, then start it again."
        p.live = live
        if crashLoop, p.run?.state == .stopped { p.run?.state = .failed }
        return p
    }

    static let crashLoopWords = "It kept crashing, so the Core stopped restarting it."

    /// Why a run ended, in a sentence (the Core's `stop_reason`).
    static func reason(_ code: String?) -> String {
        switch code {
        case "runner_lost": "The machine running it went offline."
        case "crash": "It stopped by itself."
        case "user": "You stopped it."
        case "idle": "It stopped after a while with no visits."
        case "replaced": "Another run replaced it."
        case "start_failed": "The last start failed."
        case nil: "The last start failed."
        case let other?: "It ended (\(other))."
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
        guard let service else { return }
        let answer: ProjectRunState?
        do { answer = try await service.run(project: id) } catch {
            // A Core that cannot be asked is not "running": what is shown is marked as how it last looked.
            markSilent(true)
            return
        }
        markSilent(false)
        guard let r = answer else { return }
        runStates[id] = r
        if let i = projects.firstIndex(where: { $0.id == id }) { projects[i] = applying(projects[i]) }
    }

    /// Keeps the open project's run fresh while it starts (every 2 s) or runs (every minute; while its Overview or Run page is
    /// up that also tells the Core a viewer is there, which pushes the idle stop back). Returns once it is neither.
    func watch(_ id: Int64) async {
        while !Task.isCancelled, let service {
            await refreshRun(id)
            await refreshLive(id)
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

    /// General in Project Settings: the name, the description and (when it changed) the link name, behind Touch ID.
    @discardableResult
    func saveGeneral(_ project: ProjectItem, name: String, description: String, slug: String? = nil) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard let service, !busy, mayWrite() else { return false }
        let newSlug = slug.flatMap { $0 == project.slug ? nil : $0 }
        if let problem = ProjectRules.nameProblem(name) ?? newSlug.flatMap(ProjectRules.slugProblem) {
            writeError = problem
            return false
        }
        busy = true
        writeError = nil
        defer { busy = false }
        let colour = colour(project)
        do {
            try await host.elevated("Save the name and description of \(project.name).", done: "saved", keepsEdit: true)
            {
                if let newSlug {
                    try await service.update(
                        project: project.id, patch: ProjectPatch(name: name, description: description, slug: newSlug))
                } else {
                    try await service.update(project: project.id, name: name, description: description)
                }
            }
        } catch is AdminDeclined {
            return false
        } catch {
            writeError = words(error)
            return false
        }
        // The colour is kept by link name on this Mac: it follows the new one.
        if let newSlug { colours.set(colour, for: newSlug) }
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
        // A Core with the unarchive route (minor 95) gives a few seconds to undo.
        guard let undo = insightsService else {
            host.shell.showToast("\(project.name) archived")
            return
        }
        host.shell.showToast(
            "Archived \(project.name). Your repos stay on GitHub.", kind: .ok,
            undo: { [weak self] in Task { await self?.restore(project, undo) } })
    }

    /// The Undo of a delete: the project is active again and back in the list.
    func restore(_ project: ProjectItem, _ service: any ProjectInsightsService) async {
        guard mayWrite() else { return }
        do {
            try await host.elevated("Bring back \(project.name).", done: "restored", keepsEdit: false) {
                try await service.unarchive(project: project.id)
            }
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
