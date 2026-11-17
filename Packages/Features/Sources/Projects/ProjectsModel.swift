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
    private(set) var catalogState = RepoCatalogState.loading

    private(set) var projects: [ProjectItem] = []
    var load: ProjectsLoad = .notConnected
    /// The gallery's Filter field.
    var filter = ""
    /// The project whose space is open (nil: the gallery).
    var openID: Int64?
    /// The gallery card the arrow keys are on.
    var cursor: Int64?
    /// ⌘N and the New Project button: the quick pop-over under the button.
    var quickOpen = false
    var quickName = ""
    /// A refusal from the Core for the write in flight, in words.
    private(set) var writeError: String?
    private(set) var busy = false
    /// A write came back `forbidden_scope`: this device can read but not change.
    private(set) var readOnly = false
    @ObservationIgnored let colours: ProjectColours
    @ObservationIgnored var now: () -> Date = { Date() }
    /// The Core's name, for "Runs on" (the Core this Mac is paired with).
    var coreName: String { host.shell.home.coreName.isEmpty ? "Home Core" : host.shell.home.coreName }
    #if DEBUG
    /// Snapshots only: draws this card in its hover state.
    var debugHover: Int64?
    #endif

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

    public func attach(connection: CoreConnection) { use(LiveProjectsService(connection: connection)) }

    func use(_ service: any ProjectsService) {
        self.service = service
        load = .loading
        Task { await reload() }
    }

    public func detach() {
        service = nil
        projects = []
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
            projects = try await service.projects().sorted { $0.updatedAt > $1.updatedAt }
            load = .ready
        } catch {
            // A list already on screen stays; only a first load that failed shows the failure.
            if projects.isEmpty { load = .failed(words(error)) }
        }
    }

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
    func colour(_ p: ProjectItem) -> ProjectColour { colours.colour(p.slug) }

    /// The gallery's cards after the Filter field.
    var shown: [ProjectItem] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty
            ? projects : projects.filter { $0.name.lowercased().contains(q) || $0.slug.contains(q) }
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

    // MARK: writes

    /// Creates the project and adds the picked repos, all behind one Touch ID. The new project opens. Returns false when
    /// nothing was created (the sheet stays open with its error, or the person did not elevate).
    @discardableResult
    func create(name: String, slug: String, colour: ProjectColour, repos: [PickRepo] = []) async -> Bool {
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

    func openProject(_ id: Int64) {
        withAnimation(Motion.out(Motion.move)) { openID = id }
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
        spec.onNew = { [weak self] in self?.newItem() }
        shell.openPane(spec)
        Task { await reload() }
    }

    // MARK: launcher

    public func install() {
        let shell = host.shell
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
