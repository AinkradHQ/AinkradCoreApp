import Admin
import CoreKit
import CoreUI
import Foundation
import Shell

/// What the Projects app does with Core API minor 110: the colour held on the Core, a repo's branch, and the crash alert. (The
/// private preview, the start steps, the metrics and the sessions filter are in `PreviewProxy`, `ProjectRunControl`,
/// `ProjectsModel+Live` and `ProjectsService`.) Every entry point here is gated on `core110`.
extension ProjectsModel {
    // MARK: colour

    /// A colour picked in Settings: on a 110 Core it is saved on the Core (one Touch ID, like every change) and shown once it
    /// is; on an older one it stays a choice of this Mac, as before.
    func setColour(_ c: ProjectColour, for p: ProjectItem) {
        guard core110, service != nil else {
            colours.set(c, for: p.slug)
            bumpColour()
            return
        }
        guard c != colour(p) else { return }
        Task {
            if await change(p, ProjectPatch(colour: c.rawValue), why: "Save the colour of \(p.name).") {
                colours.set(c, for: p.slug)
                bumpColour()
            }
        }
    }

    /// The projects whose colour was picked on this Mac and the Core does not hold yet.
    func coloursToPush() -> [(ProjectItem, ProjectColour)] {
        projects.compactMap { p in
            guard !p.archived, p.colourName == nil, let c = colours.explicit(p.slug) else { return nil }
            return (p, c)
        }
    }

    /// Once per Mac: the colours picked here go up to the Core where it has none, behind one Touch ID. Declined or failed, it is
    /// asked again at the next start; nothing is lost either way.
    func migrateColours() async {
        guard core110, let service, !colours.migrated, !colourMigrating, !colourMigrationDeclined, !readOnly,
            host.pausedReason == nil
        else { return }
        let todo = coloursToPush()
        guard !todo.isEmpty else {
            colours.migrated = true
            return
        }
        colourMigrating = true
        defer { colourMigrating = false }
        do {
            try await host.elevated(
                "Save the colours you picked for your projects on this Mac to the Core.", done: "saved",
                keepsEdit: false
            ) {
                for (p, c) in todo { try await service.update(project: p.id, patch: ProjectPatch(colour: c.rawValue)) }
            }
        } catch is AdminDeclined {
            colourMigrationDeclined = true
            return
        } catch {
            colourMigrationDeclined = true
            host.shell.showToast("Could not save the project colours to the Core: \(words(error))", kind: .warn)
            return
        }
        colours.migrated = true
        await reload()
    }

    // MARK: a repo's branch

    /// What `PATCH /projects/{id}/repos/{repo}` says when it refuses, in words.
    func branchWords(_ error: any Error, branch: String, repo: String) -> String {
        switch CoreFailure.of(error) ?? CoreError.unwrapping(error) {
        case .badRequest?:
            return
                "The Core’s copy of \(repo) has no branch called “\(branch)”. Check the name, or fetch the repo first."
        case .http(409, _, _)?:
            return "The Core has not copied \(repo) yet. Fetch it first, then change the branch."
        case .http(503, _, _)?:
            return "The Core is busy right now. Try again in a moment."
        default: return words(error)
        }
    }

    static func branchProblem(_ s: String) -> String? {
        let b = s.trimmingCharacters(in: .whitespaces)
        if b.isEmpty { return "Type the name of a branch." }
        if b.count > 200 || b.contains(where: { $0.isWhitespace }) || b.hasPrefix("-") || b.contains("..") {
            return "That is not a branch name."
        }
        return nil
    }

    /// Makes the repo follow `branch`. The Core checks it on its copy and fetches again so the copy follows. False leaves the
    /// dialog open with `writeError`.
    @discardableResult
    func changeBranch(_ project: ProjectItem, _ repo: RepoItem, to branch: String) async -> Bool {
        let branch = branch.trimmingCharacters(in: .whitespaces)
        guard core110, let service, !busy, mayWrite() else { return false }
        if let why = Self.branchProblem(branch) {
            writeError = why
            return false
        }
        if branch == repo.branch {
            host.shell.closeDialog()
            return true
        }
        busy = true
        writeError = nil
        fetching.insert(repo.id)
        defer {
            busy = false
            fetching.remove(repo.id)
        }
        do {
            try await host.elevated(
                "Make \(repo.name) of \(project.name) follow the branch \(branch).", done: "changed", keepsEdit: true
            ) { try await service.setBranch(project: project.id, repo: repo.id, branch: branch) }
        } catch is AdminDeclined {
            return false
        } catch {
            writeError = branchWords(error, branch: branch, repo: repo.name)
            return false
        }
        await reload()
        host.shell.closeDialog()
        host.shell.showToast("\(repo.name) follows \(branch)")
        return true
    }

    // MARK: crash alerts

    /// `project.service_crashed`: a toast with Open logs, and a badge on the project until it runs again.
    public func serviceCrashed(_ fields: [String: String]) {
        guard core110, let id = fields["id"].flatMap(Int64.init), let service = fields["service"] else { return }
        let crash = ServiceCrash(
            project: id, run: fields["run"] ?? "", service: service, exitCode: fields["exit_code"].flatMap(Int.init),
            restarts: fields["restarts"].flatMap(Int.init) ?? 0, config: fields["config"],
            environment: fields["environment"],
            at: now())
        crashes[id] = crash
        reapply(id)
        let name = project(id)?.name ?? "A project"
        host.shell.showToast(
            "\(name): \(crash.words)", kind: .warn, actionTitle: "Open Logs", lifetime: 12,
            undo: { [weak self] in self?.openLogs(id) })
    }

    func openLogs(_ id: Int64) {
        show()
        openProject(id, section: .run)
    }

    /// The crash to show on a project: nothing once its run has started again after it.
    func crash(for id: Int64, run: ProjectRunState?) -> ServiceCrash? {
        guard let c = crashes[id] else { return nil }
        if let run, run.summary.state == .running || run.summary.state == .starting, run.startedAt > c.at { return nil }
        return c
    }
}

/// A service that crashed, as the Core says it (`project.service_crashed`).
struct ServiceCrash: Equatable, Sendable {
    let project: Int64
    let run: String
    let service: String
    let exitCode: Int?
    let restarts: Int
    let config: String?
    let environment: String?
    let at: Date

    /// "api kept crashing and was stopped" once it was restarted several times; the exit code is in the logs.
    var words: String {
        if restarts >= 3 { return "\(service) kept crashing and was stopped" }
        return restarts > 0 ? "\(service) crashed and was restarted" : "\(service) crashed"
    }
}
