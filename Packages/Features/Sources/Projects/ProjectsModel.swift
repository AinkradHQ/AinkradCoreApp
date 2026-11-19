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
    /// The Core can keep a runner preference (minor 95); older Cores are never asked.
    private(set) var runnerSupported = false
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
    /// Bumps when a colour is picked, so the views that read `colour(_:)` redraw.
    private var colourTick = 0
    @ObservationIgnored let colours: ProjectColours
    @ObservationIgnored var now: () -> Date = { Date() }
    /// The Core's name, for "Runs on" (the Core this Mac is paired with).
    var coreName: String { host.shell.home.coreName.isEmpty ? "Home Core" : host.shell.home.coreName }
    #if DEBUG
    /// Snapshots only: draws this card in its hover state.
    var debugHover: Int64?
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
        catalog = LiveRepoCatalog(connection: connection)
        Task { [weak self] in
            let ok = await connection.serverSupports(minor: 95)
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
    public func event(kind: String) { if kind.hasPrefix("project.") { resync() } }

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
            projects = list.map(applying)
            load = .ready
            syncLauncherProjects()
            pollWhileCopying()
        } catch {
            // A list already on screen stays; only a first load that failed shows the failure.
            if projects.isEmpty { load = .failed(words(error)) }
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

    /// While the Core is copying a repo the page reads again every few seconds (the Core's `project.mirror_changed`
    /// event usually does it sooner), so "copying" always ends in ready or a reason.
    private func pollWhileCopying() {
        let copying = projects.contains { $0.repos.contains { if case .fetching = $0.copy { true } else { false } } }
        guard copying, pollTask == nil else { return }
        pollTask = Task {
            try? await Task.sleep(for: .seconds(3))
            pollTask = nil
            if !Task.isCancelled { await reload() }
        }
    }

    /// "Fetch Now" and "Try again": the Core copies the repo again. The call lasts as long as the fetch, so it is not
    /// awaited here; the Core says "fetching" at once and the page reads that.
    func fetchRepo(_ project: ProjectItem, _ repo: RepoItem) {
        guard let service else { return }
        Task { _ = try? await service.fetch(project: project.id, repo: repo.id) }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            await reload()
        }
    }

    /// Opens the Connections flow (GitHub).
    func connectGithub() { host.shell.launcher.entry("connections")?.run() }

    /// Reads the picker's repos (once per open of a sheet).
    func loadCatalog() async {
        do { catalogState = try await catalog.repos().map { .ready($0) } ?? .unavailable } catch {
            catalogState = .unavailable
        }
    }

    /// The picked repos in the order they were listed, then the pasted ones.
    func chosen(_ picked: Set<String>, pasted: [PickRepo]) -> [PickRepo] {
        var all: [PickRepo] = []
        if case .ready(let r) = catalogState { all = r }
        return (all + pasted).filter { picked.contains($0.id) }
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
        switch e {
        case .http(409, _, _): return "That link name is taken. Pick another."
        case .http(_, let code, _) where code == "conflict": return "That link name is taken. Pick another."
        default: return e.localizedDescription
        }
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
    @discardableResult
    func create(
        name: String, slug: String, colour: ProjectColour, repos: [PickRepo] = [], expose: Bool? = nil,
        runner: String? = nil, wizard: Bool = false
    ) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard let service, !busy, mayWrite() else { return false }
        if let problem = ProjectRules.nameProblem(name) ?? ProjectRules.slugProblem(slug) {
            writeError = problem
            return false
        }
        busy = true
        writeError = nil
        defer { busy = false }
        var made: ProjectItem?
        var missed: [String] = []
        do {
            try await host.elevated(
                "Create the project \(name) and its link \(ProjectRules.host(slug)).", done: "created", keepsEdit: true
            ) {
                let p = try await service.create(slug: slug, name: name)
                made = p
                for (i, r) in repos.enumerated() {
                    guard let pick = ProjectRules.repo(fromLink: r.url) else {
                        missed.append(r.name)
                        continue
                    }
                    do { try await service.addRepo(project: p.id, name: r.name, url: pick.url, primary: i == 0) } catch
                    {
                        missed.append(r.name)
                    }
                }
                // The wizard's choices; a failure here never undoes the project (they can be changed in Settings).
                if let expose { try? await service.setExpose(project: p.id, expose) }
                if let runner, runnerSupported, runner != "auto" { try? await service.setRunner(project: p.id, runner) }
            }
        } catch is AdminDeclined {
            // Nothing was written if the project is still nil; if it exists the person saw Touch ID succeed.
            if made == nil { return false }
        } catch {
            if made == nil {
                if CoreError.unwrapping(error) == .forbiddenScope { readOnly = true }
                writeError = words(error)
                return false
            }
        }
        guard let made else { return false }
        colours.set(colour, for: made.slug)
        quickOpen = false
        quickName = ""
        await reload()
        if wizard {
            // The wizard stays up and shows the copying; "Open project" there opens the space.
            wizardProjectID = made.id
            return true
        }
        openID = made.id
        host.shell.closeDialog()
        if missed.isEmpty {
            host.shell.showToast("\(made.name) created")
        } else {
            host.shell.showToast(
                "\(made.name) created, but \(missed.joined(separator: ", ")) could not be added. Add it from the project.",
                kind: .warn)
        }
        return true
    }

    /// "Add Repos…" in a project: adds the picked repos behind one Touch ID.
    @discardableResult
    func addRepos(to project: ProjectItem, _ picks: [PickRepo]) async -> Bool {
        guard let service, !busy, mayWrite(), !picks.isEmpty else { return false }
        busy = true
        writeError = nil
        defer { busy = false }
        var missed: [String] = []
        do {
            try await host.elevated(
                "Add \(ProjectItem.count(picks.count, "repo")) to \(project.name).", done: "added", keepsEdit: true
            ) {
                for (i, r) in picks.enumerated() {
                    do {
                        try await service.addRepo(
                            project: project.id, name: r.name, url: r.url, primary: project.repos.isEmpty && i == 0)
                    } catch { missed.append(r.name) }
                }
            }
        } catch is AdminDeclined {
            return false
        } catch {
            writeError = words(error)
            return false
        }
        await reload()
        if missed.count == picks.count {
            writeError = "None of the repos could be added. Check the links and try again."
            return false
        }
        host.shell.closeDialog()
        host.shell.showToast(
            missed.isEmpty
                ? "\(ProjectItem.count(picks.count, "repo")) added"
                : "\(missed.joined(separator: ", ")) could not be added", kind: missed.isEmpty ? .ok : .warn)
        return true
    }

    func setExpose(_ project: ProjectItem, _ on: Bool) async {
        guard let service, mayWrite() else { return }
        do {
            try await host.elevated(
                on ? "Make \(project.link) public while \(project.name) runs." : "Stop sharing \(project.link).",
                done: "changed", keepsEdit: false
            ) { try await service.setExpose(project: project.id, on) }
            await reload()
        } catch is AdminDeclined {
        } catch { host.shell.showToast(words(error), kind: .warn) }
    }

    // MARK: navigation

    /// Opens a project's space where Settings, Projects, Options says: in a pane of its own beside the gallery (the default), or
    /// in the Projects pane in place of the gallery.
    func openProject(_ id: Int64) {
        section = .overview
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

    func newProject() {
        guard !readOnly else { return }
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
    func repos() async throws -> [PickRepo]? {
        let now = Date()
        func r(_ org: String, _ name: String, _ lang: String, hoursAgo: Double) -> PickRepo {
            PickRepo(
                org: org, name: name, url: "https://github.com/\(org)/\(name)", language: lang,
                updatedAt: now.addingTimeInterval(-hoursAgo * 3600))
        }
        return [
            r("tidepool-labs", "tidepool-api", "Go", hoursAgo: 2),
            r("tidepool-labs", "tidepool-web", "Next.js", hoursAgo: 1),
            r("tidepool-labs", "tidepool-docs", "Markdown", hoursAgo: 24 * 8),
            r("lanterna-co", "design-tokens", "TypeScript", hoursAgo: 24 * 3),
            r("lanterna-co", "storefront", "Next.js", hoursAgo: 5),
            r("northwind-books", "ledger", "Rust", hoursAgo: 24 * 20),
        ]
    }
}
#endif
