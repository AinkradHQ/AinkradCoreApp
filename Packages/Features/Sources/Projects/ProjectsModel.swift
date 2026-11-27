import Admin
import CoreKit
import CoreUI
import Foundation
import Observation
import Shell
import SwiftUI

/// The Projects app: the gallery, the New Project flows and the project space the gallery opens. It owns the list, the Core
/// service and the writes (each behind Touch ID through the host), and registers the pane, the launcher entries and ⌘N.
@MainActor @Observable
public final class ProjectsModel {
    let host: any AdminHost
    var service: (any ProjectsService)?
    var catalog: any RepoCatalog
    /// The Run page's reads and writes (spec, secrets, run). Set with the connection; the Debug demo brings its own.
    var runService: (any ProjectRunService)?
    /// Run configurations and environments (Core 0.10, minor 95); nil on an older Core, so the page shows the old Run page.
    var configsService: (any RunConfigsService)?
    /// Code facts, usage, changes, Brain records and fetch tuning (minor 95); nil on an older Core.
    var insightsService: (any ProjectInsightsService)?
    private(set) var catalogState = RepoCatalogState.loading
    /// The picker's list is a page of GitHub's: more can be asked for, and GitHub may hold more than the Core reads.
    private(set) var catalogHasMore = false
    private(set) var catalogTruncated = false
    private(set) var catalogBusy = false
    /// Every repo the picker listed this session, in the order first seen, so a pick survives a new search.
    @ObservationIgnored private var catalogSeen: [PickRepo] = []
    @ObservationIgnored private var catalogQuery = ""
    @ObservationIgnored private var catalogPage = 1
    /// Runners the Core has, for "Where it runs".
    private(set) var runners: [RunnerInfo] = []
    /// Why the list on screen is out of date (a refresh failed while projects were showing); nil when it is fresh.
    internal(set) var stale: String?
    /// Repos being copied because the person asked (Fetch Now, Fetch All): their rows say "Copying" until the Core answers.
    internal(set) var fetching: Set<Int64> = []
    /// Projects whose public link is being changed (the switch waits).
    internal(set) var exposing: Set<Int64> = []
    /// What the wizard's create could not do: repos the Core refused and settings it could not apply.
    internal(set) var wizardMissed: [MissedRepo] = []
    internal(set) var wizardIssues: [String] = []
    @ObservationIgnored var pollAttempt = 0
    /// The Core can keep a runner preference (minor 95); older Cores are never asked.
    internal(set) var runnerSupported = false
    /// The project the New Project wizard just made: its review step shows that project's repos copying.
    internal(set) var wizardProjectID: Int64?

    internal(set) var projects: [ProjectItem] = []
    var load: ProjectsLoad = .notConnected
    /// The gallery's Filter field.
    var filter = ""
    /// The project whose space is open (nil: the gallery).
    var openID: Int64?
    /// The page of the open project's space.
    var section = ProjectSection.overview
    /// The gallery card the arrow keys are on.
    var cursor: Int64?
    /// ⌘N and the New Project button: the quick pop-over under the button.
    var quickOpen = false
    var quickName = ""
    /// What a run gets unless a project says otherwise (Settings > Projects > Options); nil until read, or on a Core without it.
    internal(set) var limits: ProjectLimits?
    internal(set) var limitsState = LimitsState.loading
    enum LimitsState: Equatable { case loading, ready, unsupported, failed }
    /// A refusal from the Core for the write in flight, in words.
    internal(set) var writeError: String?
    internal(set) var busy = false
    /// A write came back `forbidden_scope`: this device can read but not change.
    internal(set) var readOnly = false
    /// Projects whose Start, Stop or Restart is in flight (the buttons wait).
    internal(set) var controlling: Set<Int64> = []
    /// The newest run of each project, as the Core's run routes last said it.
    @ObservationIgnored var runStates: [Int64: ProjectRunState] = [:]
    /// What the Core says of each project's setup (its run spec); a project with no entry has not been read yet.
    @ObservationIgnored var setupStates: [Int64: SetupRead] = [:]
    /// The services, sessions and room of each project, read from the Core (the Overview's islands).
    @ObservationIgnored var liveParts: [Int64: LiveParts] = [:]
    /// Runner id to its name, for "on core-oracle".
    @ObservationIgnored var runnerNames: [String: String] = [:]
    /// Bumps when the Core says a run or its setup changed, so the Run pages read again at once.
    internal(set) var runTick = 0
    /// The last read of the Core failed: what is shown is how it last looked.
    @ObservationIgnored var coreSilent = false
    /// Starts an AI session in a project (the app wires it to the AI Sessions app); returns the refusal in words.
    @ObservationIgnored public var sessionStarter: (@MainActor (Int64) async -> String?)?
    /// Opens an AI session in the AI Sessions app.
    @ObservationIgnored public var sessionOpener: (@MainActor (String) -> Void)?
    /// A run's log: the Core's routes for a project (and one run by id). The Debug demo brings its own.
    @ObservationIgnored var logSources: (Int64, String?) -> (any RunLogSource)? = { _, _ in nil }
    /// Bumps when a colour is picked, so the views that read `colour(_:)` redraw.
    private var colourTick = 0
    @ObservationIgnored let colours: ProjectColours
    @ObservationIgnored var now: () -> Date = { Date() }
    /// The Core's name, for "Runs on" (the Core this Mac is paired with).
    var coreName: String { host.shell.home.coreName.isEmpty ? "Home Core" : host.shell.home.coreName }
    #if DEBUG
    /// Snapshots only: draws this card in its hover state.
    var debugHover: Int64?
    /// Snapshots only: a drawn page stands in for the web view of a running app (the demo's links go nowhere).
    var demoPage = false
    #endif

    /// The notes of the Docs page (R6-06): the Lore routes of the same Core.
    @ObservationIgnored var lore: (any LoreService)?
    /// Opens a note in the Lore space (the app wires this to `LoreModel.open(note:)`; Lore depends on Shell, not on Projects).
    @ObservationIgnored public var openNote: (@MainActor (String) -> Void)?

    /// The Designs island of the Overview, from the Design app (which depends on Projects, not the other way round).
    @ObservationIgnored public var designsIsland: (@MainActor (ProjectRef) -> AnyView)?

    /// The projects as other apps name them: the Core's id as text and the name.
    public var refs: [ProjectRef] { projects.map { ProjectRef(id: String($0.id), name: $0.name) } }

    /// Opens a project's space on its Overview (from another app's link).
    public func openSpace(_ id: String) {
        guard let pid = Int64(id) else { return }
        if ProjectsOptions.openIn == .newWorkspace, let p = project(pid) {
            section = .overview
            openInOwnPane(p)
            return
        }
        section = .overview
        show(project: pid)
    }

    public convenience init(host: any AdminHost) { self.init(host: host, defaults: .standard) }

    init(host: any AdminHost, defaults: UserDefaults) {
        self.host = host
        colours = ProjectColours(defaults: defaults)
        #if DEBUG
        catalog = SampleRepoCatalog()
        #else
        catalog = NoRepoCatalog()
        #endif
    }

    // MARK: connection

    public func attach(connection: CoreConnection) {
        lore = LiveLoreService(connection: connection)
        runService = LiveProjectRunService(connection: connection)
        logSources = { LiveRunLogSource(connection: connection, project: $0, run: $1) }
        catalog = LiveRepoCatalog(connection: connection)
        Task { [weak self] in
            let ok = await connection.serverSupports(minor: coreMinorV010)
            self?.runnerSupported = ok
            self?.configsService = ok ? LiveRunConfigsService(connection: connection) : nil
            self?.insightsService = ok ? LiveProjectInsightsService(connection: connection) : nil
        }
        use(LiveProjectsService(connection: connection))
    }

    func use(_ service: any ProjectsService) {
        self.service = service
        load = .loading
        Task { await reload() }
    }

    public func detach() {
        service = nil
        lore = nil
        runService = nil
        configsService = nil
        insightsService = nil
        projects = []
        setupStates = [:]
        liveParts = [:]
        limits = nil
        limitsState = .loading
        pollTask?.cancel()
        pollTask = nil
        load = .notConnected
        openID = nil
        cursor = nil
        quickOpen = false
        readOnly = false
    }

    public var isConnected: Bool { service != nil }
    public func resync() { if service != nil { Task { await reload() } } }

    /// An event from the Core that may change what the gallery shows.
    public func event(kind: String) {
        if kind.hasPrefix("project.") { resync() }
        // A run or its setup changed, or an AI session did: the open project's pages read again now, not at the next poll.
        if kind.hasPrefix("project.run_") || kind == "project.spec_saved" || kind.hasPrefix("agent"), let id = openID {
            if kind.hasPrefix("project.") { runTick += 1 }
            Task {
                await refreshRun(id)
                await refreshSetup(id)
                await refreshLive(id)
            }
        }
    }

    func reload() async {
        guard let service else { return }
        do {
            var all = try await service.projects()
            // "Show archived projects" (Settings > Projects > Options): they come after the active ones in the same order.
            if ProjectsOptions.showArchived { all += (try? await service.archivedProjects()) ?? [] }
            let list = all.sorted { ($0.archived ? 1 : 0, $1.updatedAt) < ($1.archived ? 1 : 0, $0.updatedAt) }
            // One read of each run, in parallel: the gallery's tags and the top bar need them.
            let runs = await withTaskGroup(of: (Int64, ProjectRunState?).self) { group in
                for p in list where !p.repos.isEmpty && !p.archived {
                    group.addTask { (p.id, try? await service.run(project: p.id)) }
                }
                var out: [Int64: ProjectRunState] = [:]
                for await (id, r) in group { if let r { out[id] = r } }
                return out
            }
            runStates = runs
            // The setup of a project that never ran (and of the open one): spec present means ready to start.
            let wanted = list.filter { !$0.repos.isEmpty && !$0.archived && (runs[$0.id] == nil || $0.id == openID) }
            let rs = runService
            let reads = await withTaskGroup(of: (Int64, SetupRead?).self) { group in
                for p in wanted { group.addTask { (p.id, await Self.readSetup(rs, p.id)) } }
                var out: [Int64: SetupRead] = [:]
                for await (id, r) in group { if let r { out[id] = r } }
                return out
            }
            for (id, r) in reads { setupStates[id] = r }
            coreSilent = false
            projects = list.map(applying)
            load = .ready
            stale = nil
            syncLauncherProjects()
            pollWhileCopying()
        } catch {
            // A list already on screen stays, marked as old; only a first load that failed shows the failure.
            if projects.isEmpty {
                load = .failed(words(error))
            } else {
                stale = words(error)
                markSilent(true)
            }
        }
    }

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var registeredProjects: Set<String> = []

    /// The twelve most recently touched projects as launcher entries (⌘K → Projects).
    private func syncLauncherProjects() {
        let recent = projects.prefix(12)
        let ids = Set(recent.map { "project-\($0.id)" })
        for gone in registeredProjects.subtracting(ids) { host.shell.launcher.unregister(gone) }
        for p in recent {
            host.shell.launcher.register(
                LauncherEntry(
                    id: "project-\(p.id)", title: p.name, sub: p.description.isEmpty ? "Project" : p.description,
                    symbol: "folder", keywords: ["project", p.slug]
                ) { [weak self] in self?.show(project: p.id) })
        }
        registeredProjects = ids
    }

    /// While the Core is copying a repo, only the projects that are copying are read again (each one, not the list and every
    /// run), at a growing interval (the Core's `project.mirror_changed` event usually says it sooner). A repo with no copy
    /// at all is waited for a few reads and then left alone, so "copying" always ends.
    private func pollWhileCopying() {
        let ids = copyingProjects()
        guard !ids.isEmpty, pollTask == nil else {
            if ids.isEmpty { pollAttempt = 0 }
            return
        }
        let wait = Self.backoff(pollAttempt)
        pollAttempt += 1
        pollTask = Task {
            try? await Task.sleep(for: wait)
            pollTask = nil
            if !Task.isCancelled { await refreshCopying(ids) }
        }
    }

    /// 3 s, 3 s, 5 s, 8 s, 13 s, 20 s, then 30 s.
    static func backoff(_ attempt: Int) -> Duration {
        .seconds([3, 3, 5, 8, 13, 20][min(max(attempt, 0), 5)] + (attempt > 5 ? 10 : 0))
    }

    /// The projects with a repo the Core is copying (or, for the first reads, one it has not started).
    func copyingProjects() -> [Int64] {
        projects.filter { p in
            p.repos.contains {
                switch $0.copy {
                case .fetching: true
                case .unknown: pollAttempt < 4
                default: false
                }
            }
        }.map(\.id)
    }

    func refreshCopying(_ ids: [Int64]) async {
        guard let service else { return }
        for id in ids {
            do {
                guard let fresh = try await service.project(id: id) else { return await reload() }
                if let i = projects.firstIndex(where: { $0.id == id }) { projects[i] = applying(fresh) }
            } catch {
                return await reload()
            }
        }
        stale = nil
        pollWhileCopying()
    }

    /// "Fetch Now" and "Try again": the Core copies the repo again. The call lasts as long as the fetch, so the row says
    /// "Copying" meanwhile; one read of the project follows, and a toast says how it ended.
    func fetchRepo(_ project: ProjectItem, _ repo: RepoItem) { Task { await fetch([repo], in: project) } }

    /// "Fetch All": every repo at once and one read at the end.
    func fetchAll(_ project: ProjectItem) { Task { await fetch(project.repos, in: project) } }

    func isCopying(_ repo: RepoItem) -> Bool {
        if fetching.contains(repo.id) { return true }
        if case .fetching = repo.copy { return true }
        return false
    }

    func fetch(_ repos: [RepoItem], in project: ProjectItem) async {
        guard let service, mayWrite() else { return }
        let todo = repos.filter { !fetching.contains($0.id) }
        guard !todo.isEmpty else { return }
        fetching.formUnion(todo.map(\.id))
        var refused: [MissedRepo] = []
        await withTaskGroup(of: MissedRepo?.self) { group in
            for r in todo {
                group.addTask {
                    do { try await service.fetch(project: project.id, repo: r.id) } catch {
                        return await MissedRepo(name: r.name, why: self.words(error))
                    }
                    return nil
                }
            }
            for await m in group { if let m { refused.append(m) } }
        }
        fetching.subtract(todo.map(\.id))
        pollAttempt = 0
        await reload()
        let now = self.project(project.id)?.repos.filter { r in todo.contains { $0.id == r.id } } ?? []
        var failed = refused
        for r in now {
            if case .failed(_, let why) = r.copy, !failed.contains(where: { $0.name == r.name }) {
                failed.append(MissedRepo(name: r.name, why: why))
            }
        }
        if failed.isEmpty {
            host.shell.showToast(todo.count == 1 ? "\(todo[0].name) is up to date" : "\(todo.count) repos fetched")
        } else {
            host.shell.showToast(
                "Could not fetch " + failed.map { "\($0.name) (\($0.why))" }.joined(separator: ", "), kind: .warn)
        }
    }

    /// Opens the Connections flow (GitHub).
    func connectGithub() { host.shell.launcher.entry("connections")?.run() }

    /// Reads the picker's first page at once (once per open of a sheet); search and "Show more" read the rest.
    func loadCatalog() async { await readCatalog(query: "", page: 1) }

    /// A search typed in the picker, asked of the Core (it matches owner/name over all of GitHub's repos).
    func searchCatalog(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q != catalogQuery || catalogState == .loading else { return }
        if case .unavailable = catalogState { return }
        await readCatalog(query: q, page: 1)
    }

    func moreCatalog() async {
        guard catalogHasMore, !catalogBusy else { return }
        await readCatalog(query: catalogQuery, page: catalogPage + 1)
    }

    private func readCatalog(query: String, page: Int) async {
        catalogBusy = true
        defer { catalogBusy = false }
        do {
            guard let r = try await catalog.page(query: query, page: page) else {
                catalogState = .unavailable
                return
            }
            catalogQuery = query
            catalogPage = page
            catalogHasMore = r.hasMore
            catalogTruncated = r.truncated
            for p in r.repos where !catalogSeen.contains(where: { $0.id == p.id }) { catalogSeen.append(p) }
            if page == 1 {
                catalogState = .ready(r.repos)
            } else if case .ready(let have) = catalogState {
                catalogState = .ready(have + r.repos.filter { n in !have.contains { $0.id == n.id } })
            }
        } catch {
            if case .ready = catalogState, page > 1 { return }
            let problem = CatalogProblem(error)
            if problem == .rateLimited { host.rateLimited(retryAfter: nil) }
            catalogState = problem == .noConnection ? .unavailable : .failed(problem)
        }
    }

    /// The picked repos in the order they were listed, then the pasted ones.
    func chosen(_ picked: Set<String>, pasted: [PickRepo]) -> [PickRepo] {
        var all = catalogSeen
        if case .ready(let r) = catalogState { all += r.filter { n in !all.contains { $0.id == n.id } } }
        return (all + pasted).filter { picked.contains($0.id) }
    }

    /// "Where it runs": the runners the Core has (Mac runners serve this_mac, Linux ones home_server).
    func loadRunners() async {
        guard runnerSupported, let service else { return }
        runners = (try? await service.runners()) ?? []
    }

    // MARK: derived

    func project(_ id: Int64?) -> ProjectItem? { id.flatMap { id in projects.first { $0.id == id } } }
    var open: ProjectItem? { project(openID) }
    func colour(_ p: ProjectItem) -> ProjectColour {
        _ = colourTick
        return colours.colour(p.slug)
    }

    func setColour(_ c: ProjectColour, for p: ProjectItem) {
        colours.set(c, for: p.slug)
        colourTick += 1
    }

    // MARK: words

    func words(_ error: any Error) -> String {
        if case .rateLimited(let after)? = CoreError.unwrapping(error) { host.rateLimited(retryAfter: after) }
        guard let e = CoreFailure.of(error) ?? CoreError.unwrapping(error) else { return error.localizedDescription }
        // Any write the Core refuses for scope marks this device read-only, wherever it came from.
        if e == .forbiddenScope {
            readOnly = true
            return "This device can look at projects but not change them."
        }
        if let c = ProjectConflict.of(error) { return c.words }
        return e.localizedDescription
    }

    /// Writes are refused while the Core is unreachable or rate limiting: a toast says so.
    func mayWrite() -> Bool {
        if readOnly {
            host.shell.showToast("This device can look at projects but not change them.", kind: .warn)
            return false
        }
        guard let why = host.pausedReason else { return true }
        host.shell.showToast(why)
        return false
    }

    func clearWriteError() { writeError = nil }

    /// The wizard's "Open project": closes it and opens the new project's space.
    func openWizardProject() {
        host.shell.closeDialog()
        if let id = wizardProjectID { openProject(id) }
        wizardProjectID = nil
    }

    // MARK: writes

    /// Creates the project and adds the picked repos, all behind one Touch ID. The new project opens. Returns false when
    /// nothing was created (the sheet stays open with its error, or the person did not elevate).
    ///
    /// Repos that came from GitHub's list go through the Core's from-github route (one call, GitHub's own default branches);
    /// pasted links are added one by one. `autoSuffix`: the link name was made from the name, so a taken one becomes
    /// "tidepool-2" instead of an error. Whatever the Core refuses (a repo, the public link, the runner) is told, never dropped.
    @discardableResult
    func create(
        name: String, slug: String, colour: ProjectColour, repos: [PickRepo] = [], expose: Bool? = nil,
        runner: String? = nil, description: String = "", autoSuffix: Bool = false, wizard: Bool = false
    ) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard let service, !busy, mayWrite() else { return false }
        if let problem = ProjectRules.nameProblem(name) ?? ProjectRules.slugProblem(slug) {
            writeError = problem
            return false
        }
        // A link the Core would refuse (ssh, a password in it) is said now, before Touch ID.
        let github = repos.filter { $0.fullName != nil }
        for r in repos where r.fullName == nil {
            if let why = ProjectRules.repoLinkProblem(r.url) {
                writeError = "\(r.name): \(why)"
                return false
            }
        }
        busy = true
        writeError = nil
        wizardMissed = []
        wizardIssues = []
        defer { busy = false }
        var made: ProjectItem?
        var missed: [MissedRepo] = []
        var issues: [String] = []
        let runner = runnerSupported ? runner : nil
        do {
            try await host.elevated(
                "Create the project \(name) and its link \(ProjectRules.host(slug)).", done: "created", keepsEdit: true
            ) {
                var patch = ProjectPatch(expose: expose)
                let viaGithub = !github.isEmpty && github.count == repos.count && repos.count <= 10
                if viaGithub {
                    made = try await self.createRetrying(slug: slug, suffix: autoSuffix) {
                        try await service.createFromGithub(slug: $0, name: name, repos: github.compactMap(\.fullName))
                    }
                    patch.description = description.isEmpty ? nil : description
                    patch.runner = runner == nil || runner == "auto" ? nil : runner
                } else {
                    let p = try await self.createRetrying(slug: slug, suffix: autoSuffix) {
                        try await service.create(slug: $0, name: name, description: description, runner: runner)
                    }
                    made = p
                    for (i, r) in repos.enumerated() {
                        do {
                            try await service.addRepo(
                                project: p.id, name: r.name, url: r.url, branch: r.defaultBranch ?? "main",
                                primary: i == 0)
                        } catch { missed.append(MissedRepo(name: r.name, why: self.words(error))) }
                    }
                }
                if let made, !patch.isEmpty {
                    do { try await service.update(project: made.id, patch: patch) } catch {
                        let what = patch.expose == nil ? "the runner" : "the public link"
                        issues.append("Could not set \(what): \(self.words(error)) Change it in Settings.")
                    }
                }
            }
        } catch is AdminDeclined {
            // Nothing was written if the project is still nil; if it exists the person saw Touch ID succeed.
            if made == nil { return false }
        } catch {
            if made == nil {
                writeError = words(error)
                return false
            }
        }
        guard let made else { return false }
        colours.set(colour, for: made.slug)
        quickOpen = false
        quickName = ""
        pollAttempt = 0
        await reload()
        if made.slug != slug { issues.append("The link is \(ProjectRules.host(made.slug)): \(slug) was taken.") }
        if wizard {
            // The wizard stays up and shows the copying; "Open project" there opens the space.
            wizardMissed = missed
            wizardIssues = issues
            wizardProjectID = made.id
            return true
        }
        openID = made.id
        host.shell.closeDialog()
        if missed.isEmpty, issues.isEmpty {
            host.shell.showToast("\(made.name) created")
        } else {
            let said = missed.map { "\($0.name) (\($0.why))" }.joined(separator: ", ")
            host.shell.showToast(
                "\(made.name) created" + (missed.isEmpty ? "." : ", but not added: \(said). Add it from the project.")
                    + (issues.isEmpty ? "" : " " + issues.joined(separator: " ")),
                kind: .warn)
        }
        return true
    }

    /// Runs a create with the link name, and with "-2", "-3"… on a taken one when the name made it (`suffix`).
    private func createRetrying(
        slug: String, suffix: Bool, _ make: (String) async throws -> ProjectItem
    ) async throws -> ProjectItem {
        var candidate = slug
        for n in 2...8 {
            do { return try await make(candidate) } catch {
                guard suffix, ProjectConflict.of(error) == .slugTaken else { throw error }
                candidate = ProjectRules.suffixed(slug, n)
            }
        }
        return try await make(candidate)
    }

    /// "Add Repos…" in a project: adds the picked repos behind one Touch ID. Repos the project has are left out.
    @discardableResult
    func addRepos(to project: ProjectItem, _ picks: [PickRepo]) async -> Bool {
        let picks = picks.filter { p in !project.repos.contains { ProjectRules.same($0.remoteURL, p.url) } }
        guard let service, !busy, mayWrite(), !picks.isEmpty else { return false }
        for r in picks where r.fullName == nil {
            if let why = ProjectRules.repoLinkProblem(r.url) {
                writeError = "\(r.name): \(why)"
                return false
            }
        }
        busy = true
        writeError = nil
        defer { busy = false }
        var missed: [MissedRepo] = []
        do {
            try await host.elevated(
                "Add \(ProjectItem.count(picks.count, "repo")) to \(project.name).", done: "added", keepsEdit: true
            ) {
                for (i, r) in picks.enumerated() {
                    do {
                        try await service.addRepo(
                            project: project.id, name: r.name, url: r.url, branch: r.defaultBranch ?? "main",
                            primary: project.repos.isEmpty && i == 0)
                    } catch { missed.append(MissedRepo(name: r.name, why: self.words(error))) }
                }
            }
        } catch is AdminDeclined {
            return false
        } catch {
            writeError = words(error)
            return false
        }
        pollAttempt = 0
        await reload()
        let said = missed.map { "\($0.name): \($0.why)" }.joined(separator: " ")
        if missed.count == picks.count {
            writeError = said
            return false
        }
        host.shell.closeDialog()
        host.shell.showToast(
            missed.isEmpty ? "\(ProjectItem.count(picks.count, "repo")) added" : "Not added. \(said)",
            kind: missed.isEmpty ? .ok : .warn)
        return true
    }

    /// The public link switch: it waits (and cannot be flipped again) until the Core answers.
    func setExpose(_ project: ProjectItem, _ on: Bool) async {
        guard let service, !exposing.contains(project.id), mayWrite() else { return }
        exposing.insert(project.id)
        defer { exposing.remove(project.id) }
        do {
            try await host.elevated(
                on ? "Make \(project.link) public while \(project.name) runs." : "Stop sharing \(project.link).",
                done: "changed", keepsEdit: false
            ) { try await service.setExpose(project: project.id, on) }
            await reload()
        } catch is AdminDeclined {
        } catch { host.shell.showToast(words(error), kind: .warn) }
    }

    /// One change to a project (runner, limits, link name…) behind Touch ID; true when the Core took it.
    @discardableResult
    func change(_ project: ProjectItem, _ patch: ProjectPatch, why: String) async -> Bool {
        guard let service, !busy, mayWrite(), !patch.isEmpty else { return false }
        busy = true
        defer { busy = false }
        do {
            try await host.elevated(why, done: "saved", keepsEdit: false) {
                try await service.update(project: project.id, patch: patch)
            }
        } catch is AdminDeclined {
            return false
        } catch {
            host.shell.showToast(words(error), kind: .warn)
            return false
        }
        await reload()
        return true
    }

    /// Where it runs: `auto`, `this_mac` or `home_server`.
    func setRunner(_ project: ProjectItem, _ runner: String) async {
        guard runner != project.runner else { return }
        _ = await change(project, ProjectPatch(runner: runner), why: "Change where \(project.name) runs.")
    }

    /// What this project may use; a value out of the Core's range is refused with the Core's words.
    func setLimits(_ project: ProjectItem, _ l: ProjectLimits) async {
        let old = project.limits
        guard l != old else { return }
        var p = ProjectPatch()
        if l.cpus != old.cpus { p.cpuLimit = l.cpus }
        if l.memoryMb != old.memoryMb { p.memLimitMb = l.memoryMb }
        if l.idleMinutes != old.idleMinutes { p.idleMinutes = Int64(l.idleMinutes) }
        if l.idleNever != old.idleNever { p.idleNever = l.idleNever }
        _ = await change(project, p, why: "Change what \(project.name) may use while it runs.")
    }

    /// Make a repo the primary one of its project.
    func makePrimary(_ project: ProjectItem, _ repo: RepoItem) async {
        guard let service, !busy, mayWrite() else { return }
        busy = true
        defer { busy = false }
        do {
            try await host.elevated(
                "Make \(repo.name) the primary repo of \(project.name).", done: "changed", keepsEdit: false
            ) {
                try await service.setPrimary(project: project.id, repo: repo.id)
            }
        } catch is AdminDeclined {
            return
        } catch {
            host.shell.showToast(words(error), kind: .warn)
            return
        }
        await reload()
        host.shell.showToast("\(repo.name) is the primary repo")
    }

    /// Takes a repo out of the project after one question; the repo itself stays on GitHub.
    func confirmRemove(_ project: ProjectItem, _ repo: RepoItem) {
        let shell = host.shell
        shell.present(
            ShellDialog(id: "project-remove-repo") {
                CoreConfirmDialog(
                    "Remove \(repo.name)?",
                    message: "The Core drops its copy and sessions stop getting it. The repo stays on GitHub.",
                    confirmTitle: "Remove", destructive: true,
                    onConfirm: { [weak self] in
                        shell.closeDialog()
                        Task { await self?.removeRepo(project, repo) }
                    }, onCancel: { shell.closeDialog() })
            })
    }

    func removeRepo(_ project: ProjectItem, _ repo: RepoItem) async {
        guard let service, !busy, mayWrite() else { return }
        busy = true
        defer { busy = false }
        do {
            try await host.elevated("Remove \(repo.name) from \(project.name).", done: "removed", keepsEdit: false) {
                try await service.removeRepo(project: project.id, repo: repo.id)
            }
        } catch is AdminDeclined {
            return
        } catch {
            host.shell.showToast(words(error), kind: .warn)
            return
        }
        await reload()
        host.shell.showToast("\(repo.name) removed")
    }

    // MARK: navigation

    /// Opens a project's space where Settings, Projects, Options says: in a pane of its own beside the gallery (the default), or
    /// in the Projects pane in place of the gallery.
    func openProject(_ id: Int64, section page: ProjectSection = .overview) {
        section = page
        if ProjectsOptions.openIn == .newWorkspace, let p = project(id) {
            openInOwnPane(p)
            return
        }
        withAnimation(Motion.out(Motion.move)) { openID = id }
    }

    static func paneID(_ id: Int64) -> String { "project-\(id)" }

    private func openInOwnPane(_ p: ProjectItem) {
        let id = p.id
        host.shell.openPane(
            PaneSpec(id: Self.paneID(id), title: p.name, sub: "Project", symbol: "square.grid.2x2", minWidth: 720) {
                ProjectPaneView(model: self, id: id)
            })
        Task { await reload() }
    }

    func closeProject() {
        withAnimation(Motion.out(Motion.move)) { openID = nil }
    }

    /// Why New Project cannot be used now, in words; nil when it can.
    var newProjectBlock: String? {
        if readOnly { return "This device can look at projects but not change them." }
        switch load {
        case .notConnected: return "Connect this Mac to a Core first."
        case .failed: return "The Core did not answer. Try again first."
        case .loading, .ready: return stale == nil ? nil : "The Core is not answering right now."
        }
    }

    func newProject() {
        if let why = newProjectBlock {
            host.shell.showToast(why, kind: .warn)
            return
        }
        show()
        quickName = ""
        writeError = nil
        quickOpen = true
    }

    /// ⌘N while the gallery is up: the same as the New Project button.
    func newItem() { if openID == nil { newProject() } }

    func show(project id: Int64? = nil) {
        if let id { openID = id }
        let shell = host.shell
        var spec = PaneSpec(
            id: "projects", title: "Projects", sub: "Home Core", symbol: "square.grid.2x2", minWidth: 720
        ) { ProjectsView(model: self) }
        spec.tab = "Projects"
        spec.fullScreenOnly = true
        spec.onNew = { [weak self] in self?.newItem() }
        shell.openPane(spec)
        Task { await reload() }
    }

    // MARK: launcher

    public func install() {
        let shell = host.shell
        // Settings, Apps, Projects: its Look (follows Appearance unless turned off) and its Options.
        shell.settings.section(
            SettingsSection(
                id: "projects", group: .apps, title: "Projects", sub: "Its look and what a run may use",
                symbol: "square.grid.2x2", order: 1,
                tabs: [
                    SettingsTab("look", "Look", order: 0) {
                        AppLookSection(appName: "Projects", prefs: AppLookPrefs.shared("projects"))
                            .foregroundStyle(GlassInk.primary)
                    },
                    SettingsTab("options", "Options", order: 1) { ProjectsOptionsTab(model: self) },
                ]))
        func entry(
            _ id: String, _ title: String, _ sub: String, _ symbol: String, _ keys: [String], action: Bool = false,
            _ run: @escaping @MainActor (ProjectsModel) -> Void
        ) {
            shell.launcher.register(
                LauncherEntry(id: id, title: title, sub: sub, symbol: symbol, keywords: keys, isAction: action) {
                    [weak self] in if let self { run(self) }
                })
        }
        entry(
            "projects", "Projects", "Your projects, their repos and their links", "square.grid.2x2",
            ["repo", "app", "run"]
        ) { $0.show() }
        entry(
            "new-project", "New Project", "Name it; the room and the link come with it · needs Touch ID", "plus",
            ["create", "project", "repo"], action: true
        ) { $0.newProject() }
        entry(
            "new-project-advanced", "New Project (advanced)…", "Name, colour, GitHub repos, link",
            "slider.horizontal.3",
            ["create", "project", "repo", "github"], action: true
        ) {
            $0.show()
            NewProjectDialogs.openAdvanced($0, name: "")
        }
    }
}

#if DEBUG
/// Debug only: the picker's stand-in repos. Made-up names; the links go nowhere real.
struct SampleRepoCatalog: RepoCatalog {
    func page(query: String, page: Int) async throws -> RepoPage? {
        let now = Date()
        func r(_ org: String, _ name: String, _ lang: String, hoursAgo: Double, priv: Bool = false) -> PickRepo {
            PickRepo(
                org: org, name: name, url: "https://github.com/\(org)/\(name)", language: lang,
                updatedAt: now.addingTimeInterval(-hoursAgo * 3600), fullName: "\(org)/\(name)", defaultBranch: "main",
                isPrivate: priv)
        }
        let all = [
            r("tidepool-labs", "tidepool-api", "Go", hoursAgo: 2, priv: true),
            r("tidepool-labs", "tidepool-web", "Next.js", hoursAgo: 1),
            r("tidepool-labs", "tidepool-docs", "Markdown", hoursAgo: 24 * 8),
            r("lanterna-co", "design-tokens", "TypeScript", hoursAgo: 24 * 3),
            r("lanterna-co", "storefront", "Next.js", hoursAgo: 5),
            r("northwind-books", "ledger", "Rust", hoursAgo: 24 * 20, priv: true),
        ]
        let q = query.lowercased()
        return RepoPage(repos: all.filter { q.isEmpty || "\($0.org)/\($0.name)".lowercased().contains(q) })
    }
}
#endif
