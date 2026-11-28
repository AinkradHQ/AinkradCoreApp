import Brain
import CoreKit
import CoreUI
import Foundation
import Shell
import SwiftUI

// The demo service and scenes are Debug only; `DemoSitePage` (after `#endif`) is used by the live app island in every build.
#if DEBUG

/// Debug only: every Projects state on sample data and a stand-in service, for screenshots and for the reviewer to click
/// through. Nothing here reaches a Core. The names are made up; the links go nowhere.
@MainActor
public final class ProjectsDemo {
    final class Service: ProjectsService, @unchecked Sendable {
        private let lock = NSLock()
        private var list: [ProjectItem]
        private var next: Int64 = 100
        private let hasArchived: Bool
        init(_ list: [ProjectItem], archived: Bool = true) {
            self.list = list
            hasArchived = archived
        }
        func projects() async throws -> [ProjectItem] { lock.withLock { list } }
        func create(slug: String, name: String) async throws -> ProjectItem {
            lock.withLock {
                next += 1
                let p = ProjectItem(
                    id: next, slug: slug, name: name, description: "", expose: true, repos: [], updatedAt: Date())
                list.insert(p, at: 0)
                return p
            }
        }
        func addRepo(project: Int64, name: String, url: String, primary: Bool) async throws {
            lock.withLock {
                guard let i = list.firstIndex(where: { $0.id == project }) else { return }
                next += 1
                list[i].repos.append(
                    RepoItem(
                        id: next, name: name, remoteURL: url, branch: "main", primary: primary, fetchedAt: Date(),
                        fetchError: nil))
            }
        }
        func setExpose(project: Int64, _ on: Bool) async throws {
            lock.withLock { if let i = list.firstIndex(where: { $0.id == project }) { list[i].expose = on } }
        }
        func update(project: Int64, name: String, description: String) async throws {
            lock.withLock {
                guard let i = list.firstIndex(where: { $0.id == project }) else { return }
                list[i].name = name
                list[i].description = description
            }
        }
        func archive(project: Int64) async throws { lock.withLock { list.removeAll { $0.id == project } } }
        func project(id: Int64) async throws -> ProjectItem? { lock.withLock { list.first { $0.id == id } } }
        func update(project: Int64, patch p: ProjectPatch) async throws {
            lock.withLock {
                guard let i = list.firstIndex(where: { $0.id == project }) else { return }
                if let v = p.runner { list[i].runner = v }
                if let v = p.cpuLimit { list[i].cpuLimit = v }
                if let v = p.memLimitMb { list[i].memLimitMb = v }
                if let v = p.idleMinutes { list[i].idleMinutes = Int(v) }
                if let v = p.idleNever { list[i].idleNever = v }
                if let v = p.slug { list[i] = ProjectItem.renamed(list[i], slug: v) }
                if let v = p.kinds { list[i].kinds = v.compactMap(ProjectKind.init(rawValue:)) }
            }
        }
        func setBranch(project: Int64, repo: Int64, branch: String) async throws {
            guard branch != "nope" else { throw CoreError.badRequest(message: "no such branch") }
            // The demo keeps the repo as it is: the branch dialog is what is shown.
        }
        func archivedProjects() async throws -> [ProjectItem] {
            guard hasArchived else { return [] }
            return [
                ProjectItem(
                    id: 90, slug: "old-quill", name: "Old Quill", description: "", expose: false,
                    repos: [DemoRepo.make(900, "old-quill-web", "old-quill-co")],
                    updatedAt: Date().addingTimeInterval(-86_400 * 40), archived: true)
            ]
        }
        func unarchive(project: Int64) async throws {}
        /// The sessions the sample project carries, so the Overview, the card and the Sessions page say the same.
        func sessions(project: Int64) async throws -> [ProjectLive.Session] {
            lock.withLock { list.first { $0.id == project }?.live?.sessions ?? [] }
        }
        func places() async throws -> [BrainPlace]? {
            [
                BrainPlace(id: "r1", name: "Tidepool research"), BrainPlace(id: "r2", name: "Client notes"),
                BrainPlace(id: "r3", name: "Side ideas"),
            ]
        }
        func runners() async throws -> [RunnerInfo] {
            [
                RunnerInfo(id: "d_mac", name: "Studio Mac", os: "macos", online: true),
                RunnerInfo(id: "d_srv", name: "home-server", os: "linux", online: false),
            ]
        }
        func setRun(_ project: Int64, _ state: RunSummary.State, progress: Double = 0) {
            lock.withLock {
                guard let i = list.firstIndex(where: { $0.id == project }) else { return }
                list[i].run = RunSummary(
                    state: state, services: 5, sessions: 2, lastRun: state == .stopped ? "just now" : nil)
                list[i].live = DemoLive.make(state, progress: progress)
            }
        }
    }

    public static let scenes =
        [
            "gallery", "gallery-hover", "gallery-filtered", "gallery-empty", "gallery-loading", "gallery-offline",
            "gallery-failed", "new-empty", "space-no-repos",
            "space-add-repos", "space-copying", "space-many-repos", "space-setting-up", "space-ready",
            "overview-running",
            "overview-starting",
            "overview-stopped", "overview-failed", "overview-real-core", "page-run", "page-settings",
            "page-settings-stopped", "page-repos", "page-sessions",
            "page-brain", "page-brain-empty", "page-run-failed", "page-run-draft",
            // Look: Settings, Appearance with strong blur and low opacity (and Solid), on the gallery and a space.
            "gallery-look", "gallery-look-solid", "overview-look", "overview-private", "overview-never-opened",
            "gallery-stale", "gallery-archived", "gallery-running", "gallery-no-match", "gallery-starting",
            "gallery-cursor", "gallery-copy-failed-hover", "gallery-kinds-hover", "new-from-tile",
            "gallery-copy-failed", "settings-runner", "settings-limits",
            "repo-menu",
            "space-needs-setup", "space-ready-secrets", "overview-stale", "overview-crash-loop",
            "overview-stopped-real",
            "page-run-logs", "dialog-history", "dialog-secret-file", "dialog-instructions", "overview-starting-honest",
            // Core API 110: the private live preview, start steps, metrics, Core colour, branch change, crash alerts.
            "overview-private-live", "overview-preview-busy", "overview-starting-steps", "overview-failed-step",
            "overview-metrics", "page-run-metrics", "page-settings-core-colour", "page-repos-branch", "dialog-branch",
            "dialog-branch-error", "gallery-crashed", "overview-crashed",
            // One run model (the Default and its configurations), Environment with secrets, Repos, Settings.
            "page-run-config", "page-run-env", "page-run-live", "page-run-history", "page-run-old-core",
            "page-repos-many", "page-repos-failed", "page-settings-limits-edit", "page-settings-colour-more",
        ] + kindScenes + wizardScenes + spaceScenes + overviewScenes + moduleScenes + pagesBScenes

    /// The scenes that show a Core with API 110; every other scene is an older Core, exactly as before.
    static let core110Scenes: Set<String> = [
        "overview-private-live", "overview-preview-busy", "overview-starting-steps", "overview-failed-step",
        "overview-metrics", "page-run-metrics", "page-settings-core-colour", "page-repos-branch", "dialog-branch",
        "dialog-branch-error", "gallery-crashed", "overview-crashed",
    ]

    let model: ProjectsModel
    public init(model: ProjectsModel) { self.model = model }

    private static func repo(_ id: Int64, _ name: String, fetched: Bool = true) -> RepoItem {
        RepoItem(
            id: id, name: name, remoteURL: "https://github.com/tidepool-labs/\(name)", branch: "main", primary: id == 1,
            fetchedAt: fetched ? Date() : nil, fetchError: nil)
    }

    private static func sample() -> [ProjectItem] {
        let now = Date()
        func p(_ id: Int64, _ slug: String, _ name: String, _ run: RunSummary, repos: Int = 2, hours: Double)
            -> ProjectItem
        {
            ProjectItem(
                id: id, slug: slug, name: name, description: "", expose: true,
                repos: (0..<repos).map {
                    RepoItem(
                        id: id * 10 + Int64($0), name: "\(slug)-\($0)",
                        remoteURL: "https://github.com/\(slug)-co/\(slug)-\($0)",
                        branch: "main", primary: $0 == 0, fetchedAt: now, fetchError: nil)
                },
                updatedAt: now.addingTimeInterval(-hours * 3600), run: run, live: DemoLive.make(run.state))
        }
        var lanterna = p(1, "lanterna", "Lanterna", RunSummary(state: .running, services: 5, sessions: 2), hours: 1)
        lanterna.description = "Online shop for handmade lighting"
        lanterna.repos = [
            Self.lanternaRepo(0, "lanterna-api", branch: "development", head: "4e1c9a2", minutes: 4),
            Self.lanternaRepo(1, "lanterna-web", branch: "development", head: "a81f03d", minutes: 4),
            Self.lanternaRepo(2, "lanterna-admin", branch: "main", head: "91aa0c4", minutes: 180, failing: true),
        ]
        return [
            lanterna,
            p(2, "northwind-ledger", "Northwind Ledger", RunSummary(state: .stopped, lastRun: "yesterday"), hours: 2),
            p(3, "quill", "Quill", RunSummary(state: .failed, lastRun: "20 min ago"), hours: 3),
            p(4, "harbor-crm", "Harbor CRM", RunSummary(state: .stopped, lastRun: "Mon"), hours: 80),
        ]
    }

    private static func lanternaRepo(
        _ i: Int64, _ name: String, branch: String, head: String, minutes: Double, failing: Bool = false
    ) -> RepoItem {
        RepoItem(
            id: 10 + i, name: name, remoteURL: "https://github.com/lanterna-co/\(name)", branch: branch,
            primary: i == 0,
            fetchedAt: Date().addingTimeInterval(-minutes * 60),
            fetchError: failing ? "The GitHub connection can no longer read this repo." : nil, head: head)
    }

    /// A project whose first copy failed for every repo, one the Core never started: "Setting up" would never end.
    private static func copyFailed() -> ProjectItem {
        var p = tidepool(repos: 2, fetched: false)
        p.repos = [
            RepoItem(
                id: 71, name: "tidepool-api", remoteURL: apiURL, branch: "main", primary: true, fetchedAt: nil,
                fetchError: "This repo is private and no GitHub connection covers it.", state: "failed",
                reason: "needs_github"),
            RepoItem(
                id: 72, name: "tidepool-web", remoteURL: webURL, branch: "main", primary: false, fetchedAt: nil,
                fetchError: "The Core could not reach the repo.", state: "failed", reason: "timeout"),
        ]
        return p
    }

    private static func tidepool(repos: Int, fetched: Bool = true, draft: Bool = false, missing: Bool = false)
        -> ProjectItem
    {
        ProjectItem(
            id: 7, slug: "tidepool", name: "Tidepool", description: "", expose: true,
            repos: [repo(1, "tidepool-api", fetched: fetched), repo(2, "tidepool-web", fetched: fetched)].prefix(repos)
                .map { $0 },
            updatedAt: Date(), run: nil,
            draft: draft
                ? RunDraft(
                    source: "docker-compose.yml", services: ["web", "api", "postgres"],
                    secrets: missing ? ["jwt_secret"] : []) : nil)
    }

    static let apiURL = "https://github.com/tidepool-labs/tidepool-api"
    static let webURL = "https://github.com/tidepool-labs/tidepool-web"

    /// The sample projects on the model without opening the pane (other apps' demos name them).
    public func loadSample() async { await model.useNow(Service(Self.sample())) }

    /// For clicking through by hand.
    public func showInteractive(_ scene: String) async { await show(scene) }

    public func show(_ scene: String) async {
        let shell = model.host.shell
        shell.dialog = nil
        shell.overlay = nil
        shell.launcherOpen = false
        shell.linkNotice = nil
        shell.coreLink = .live
        shell.home.coreName = "core-oracle"
        model.host.clearElevationNotice()
        model.filter = ""
        model.segment = .all
        model.galleryRisen = true
        model.loadedAt = Date()
        model.cursor = nil
        model.openID = nil
        model.section = .overview
        model.module = .overview
        model.core112 = false
        model.debugHover = nil
        model.stale = nil
        model.wizardMissed = []
        model.wizardIssues = []
        model.wizardDraft = nil
        model.wizardProjectID = nil
        model.creating = nil
        model.catalog = SampleRepoCatalog()
        ProjectsOptions.options.set(ProjectsOptions.showArchivedKey, false)
        model.clearWriteError()
        model.demoPage = true
        model.demoPreviewProblem = nil
        model.crashes = [:]
        model.setupStates = [:]
        model.liveParts = [:]
        model.runStates = [:]
        model.core110 = Self.core110Scenes.contains(scene)
        model.core111 = Self.core111Scenes.contains(scene)
        model.previewFetch = model.core110 ? { @Sendable _, _, _, _ in throw CancellationError() } : nil
        // Every scene starts from the standard Look; the look scenes change it below.
        let look = LookPrefs.shared
        (look.mode, look.opacity, look.blur) = (CoreLook.standard.mode, CoreLook.standard.opacity, 1)
        PreviewStore.shared.forget()
        for (id, name, colour) in [
            (1, "Lanterna", ProjectColour.green), (2, "Northwind Ledger", .violet), (3, "Quill", .copper),
        ] {
            let r = ImageRenderer(content: DemoSitePage(name: name, colour: colour).frame(width: 1100, height: 680))
            r.scale = 1
            if let img = r.nsImage { PreviewStore.shared.seed(img, for: Int64(id)) }
        }
        var list = Self.sample()
        switch scene {
        case "gallery-empty": list = []
        case "space-no-repos", "space-add-repos": list.insert(Self.tidepool(repos: 0), at: 0)
        case "gallery-copy-failed", "gallery-copy-failed-hover", "new-failed-repos", "page-repos-failed":
            list.insert(Self.copyFailed(), at: 0)
        case "gallery-starting": list[1].run = RunSummary(state: .starting, services: 5)
        case "new-paste-link", "new-paste-link-ssh", "new-code-no-github": model.catalog = NoRepoCatalog()
        case "new-copying": list.insert(Self.tidepool(repos: 2, fetched: false), at: 0)
        case "new-finished": list.insert(Self.tidepool(repos: 2), at: 0)
        case "settings-runner", "settings-limits":
            list[0].runner = "this_mac"
            list[0].cpuLimit = 4
            list[0].memLimitMb = 8192
            list[0].idleNever = scene == "settings-limits"
            list[0].source = "github"
            list[0].createdAt = Date().addingTimeInterval(-86_400 * 12)
        case "space-many-repos", "page-repos-many":
            list[0].repos = (0..<14).map {
                Self.lanternaRepo(
                    Int64($0), "lanterna-\($0)", branch: "main", head: "4e1c9a2", minutes: 4, failing: $0 == 9)
            }
        case "space-copying": list.insert(Self.tidepool(repos: 2, fetched: false), at: 0)
        case "space-setting-up": list.insert(Self.tidepool(repos: 2), at: 0)
        case "space-ready": list.insert(Self.tidepool(repos: 2, draft: true), at: 0)
        case "space-ready-secrets": list.insert(Self.tidepool(repos: 2, draft: true, missing: true), at: 0)
        case "space-needs-setup":
            var t = Self.tidepool(repos: 2)
            t.setupChecked = true
            list.insert(t, at: 0)
        case "overview-starting":
            list[1].run = RunSummary(state: .starting, services: 5)
            list[1].live = DemoLive.make(.starting, progress: 0.4)
        // The Core reports no services yet: a moving bar and words, no number.
        case "overview-starting-honest":
            list[1].run = RunSummary(state: .starting, services: 0)
            var l = DemoLive.make(.starting)
            l.services = []
            l.progress = nil
            l.progressLine = "Starting on core-oracle…"
            list[1].live = l
        case "overview-stopped-real":
            var l = DemoLive.make(.stopped)
            l.services = []
            l.stopWords = "It stopped after a while with no visits."
            l.lastActivity = Date().addingTimeInterval(-3 * 3600)
            l.runner = "core-oracle"
            list[3].live = l
            list[3].draft = RunDraft(source: "docker-compose.yml", services: ["web", "api", "db"], secrets: [])
        case "overview-crash-loop":
            var l = DemoLive.make(.failed)
            l.failure = ProjectsModel.crashLoopWords
            l.failureFix = "Read the log of the last run, fix what stops it, then start it again."
            list[2].live = l
        // A real Core today: no run state, services, logs, sessions or room.
        case "overview-real-core", "page-brain-empty":
            list[3].run = nil
            list[3].live = nil
        case "overview-private":
            list[0].expose = false
        case "overview-private-live", "overview-preview-busy":
            list[0].expose = false
        case "overview-starting-steps":
            list[1].run = RunSummary(state: .starting, services: 5)
            var l = DemoLive.make(.starting, progress: 0.4)
            l.progressLine = "Starting on core-oracle · 2 of 5 services up"
            l.steps = [
                StartStep(title: "Getting the code", state: .done),
                StartStep(title: "Building the images", state: .done),
                StartStep(title: "Starting the services", state: .active, detail: "2 of 5 services up"),
                StartStep(title: "Checking they are healthy", state: .pending),
            ]
            list[1].live = l
        case "overview-failed-step":
            var l = DemoLive.make(.failed)
            l.failure = "The last start failed."
            l.failureFix = "Check the run setup, then start it again."
            l.steps = [
                StartStep(title: "Getting the code", state: .done),
                StartStep(title: "Building the images", state: .failed, detail: "web: npm ci exited with code 1"),
                StartStep(title: "Starting the services", state: .pending),
                StartStep(title: "Checking they are healthy", state: .pending),
            ]
            list[2].live = l
        case "overview-metrics", "page-run-metrics":
            list[0].live?.metrics = DemoLive.metrics()
        case "page-settings-core-colour": list[0].colourName = "teal"
        case "overview-never-opened":
            PreviewStore.shared.forget()
        default: break
        }
        Self.kindSample(scene, &list)
        Self.spaceSample(scene, &list)
        Self.overviewSample(scene, &list)
        Self.moduleSample(scene, &list)
        Self.pagesBSample(scene, &list)
        await model.useNow(Service(list, archived: scene != "gallery-empty"))
        model.runService = DemoRunService()
        model.configsService = scene == "page-run-old-core" ? nil : DemoConfigsService()
        model.logSources = { _, _ in DemoLogSource() }
        model.demoRunTab = nil
        model.demoRunSelected = nil
        // The running Lanterna reports its services, as a Core with the run engine does.
        (model.runService as? DemoRunService)?.services[1] = DemoLive.make(.running).services
        model.demoLimitsDraft = nil
        Self.configureRun(scene, model.runService as? DemoRunService)
        // The list was read with the last scene's run service: forget what it said of each project's setup.
        model.setupStates = [:]
        for p in model.projects { model.reapply(p.id) }
        model.setRunnerSupported(true)
        await model.loadRunners()
        model.show()
        try? await Task.sleep(for: .milliseconds(400))
        switch scene {
        case "gallery-look", "overview-look":
            (look.mode, look.opacity, look.blur) = (.blurred, 0.12, 1)
            if scene == "overview-look" { model.openID = 1 }
        case "gallery-look-solid": (look.mode, look.opacity, look.blur) = (.solid, 1, 1)
        case "overview-private", "overview-running", "space-many-repos", "overview-private-live",
            "overview-preview-busy",
            "overview-metrics", "overview-crashed":
            model.openID = 1
        case "overview-never-opened": model.openID = 4
        default: break
        }
        switch scene {
        case "gallery-hover": model.debugHover = 1
        case "gallery-archived": model.segment = .archived
        case "gallery-running": model.segment = .running
        case "gallery-no-match": model.filter = "xyzzy"
        case "gallery-cursor": model.cursor = 2
        case "gallery-copy-failed-hover": model.debugHover = 7
        case "gallery-kinds-hover": model.debugHover = 4
        case "new-from-tile": NewProjectDialogs.openWizard(model, name: "", kind: .app)
        case "gallery-stale":
            model.stale = "The Core did not answer in time (timeout)."
            model.loadedAt = Date().addingTimeInterval(-240)
        case "settings-runner", "settings-limits":
            model.openID = 1
            model.section = .settings
        case "repo-menu":
            model.openID = 1
            model.section = .repos
        case "gallery-filtered": model.filter = "n"
        case "gallery-loading": model.setLoad(.loading)
        case "gallery-offline": model.setLoad(.notConnected)
        case "gallery-failed": model.setLoad(.failed("The Core did not answer in time (timeout)."))
        case "new-empty": model.newProject()
        case "space-no-repos", "space-copying", "space-setting-up", "space-ready", "space-needs-setup": model.openID = 7
        case "overview-running": model.openID = 1
        case "page-run":
            model.openID = 1
            model.section = .run
        case "page-run-failed":
            model.openID = 3
            model.section = .run
        case "page-run-draft":
            model.openID = 2
            model.section = .run
        case "page-run-logs", "page-run-live":
            model.openID = 1
            model.section = .run
            model.demoRunTab = .live
        case "page-run-config":
            model.openID = 1
            model.section = .run
            model.demoRunSelected = 1
        case "page-run-env":
            model.openID = 1
            model.section = .run
            model.demoRunTab = .environment
        case "page-run-history":
            model.openID = 1
            model.section = .run
            model.demoRunTab = .history
        case "page-run-old-core":
            model.openID = 1
            model.section = .run
        case "page-repos-many", "page-repos-failed":
            model.openID = scene == "page-repos-many" ? 1 : 7
            model.section = .repos
        case "page-settings-limits-edit":
            model.openID = 4
            model.section = .settings
            var l = ProjectLimits.standard
            l.cpus = 4
            l.memoryMb = 8192
            model.demoLimitsDraft = l
        case "page-settings-colour-more":
            model.openID = 1
            model.section = .settings
            model.setColour(.orange, for: model.open ?? list[0])
        case "dialog-history", "dialog-secret-file", "dialog-instructions":
            model.openID = 1
            model.section = scene == "dialog-instructions" ? .brain : .run
            try? await Task.sleep(for: .milliseconds(800))
            guard let p = model.open else { break }
            let run = RunPageModel(model: model, projectID: p.id)
            await run.load()
            switch scene {
            case "dialog-history": RunDialogs.openHistory(run, project: p)
            case "dialog-secret-file":
                RunDialogs.openSecret(run, project: p, name: "service_account", replacing: true, kind: "file")
            default: model.openInstructions(p)
            }
        case "overview-preview-busy":
            model.demoPreviewProblem = "The app is busy with other requests. Try again in a moment."
        case "gallery-crashed", "overview-crashed":
            model.serviceCrashed(
                [
                    "id": "1", "run": "r_demo", "service": "api", "exit_code": "1", "restarts": "3", "config": "web",
                    "environment": "development",
                ])
        case "page-run-metrics":
            model.openID = 1
            model.section = .run
        case "page-settings-core-colour":
            model.openID = 1
            model.section = .settings
        case "page-repos-branch", "dialog-branch", "dialog-branch-error":
            model.openID = 1
            model.section = .repos
            try? await Task.sleep(for: .milliseconds(500))
            if scene != "page-repos-branch", let p = model.open, let r = p.repos.first {
                RepoDialogs.openBranch(model, p, r)
                if scene == "dialog-branch-error" {
                    model.writeError = model.branchWords(
                        CoreError.badRequest(message: "no such branch"), branch: "release/9", repo: r.name)
                }
            }
        case "overview-stale":
            model.openID = 1
            try? await Task.sleep(for: .milliseconds(700))
            model.markSilent(true)
        case "space-ready-secrets": model.openID = 7
        case "page-settings", "page-settings-stopped":
            model.openID = scene == "page-settings" ? 1 : 4
            model.section = .settings
        case "page-repos":
            model.openID = 1
            model.section = .repos
        case "page-sessions":
            model.openID = 1
            model.section = .sessions
        case "page-brain", "page-brain-empty":
            model.openID = scene == "page-brain" ? 1 : 4
            model.section = .brain
        case "overview-starting", "overview-starting-honest": model.openID = 2
        case "overview-failed", "overview-crash-loop": model.openID = 3
        case "overview-stopped", "overview-real-core", "overview-stopped-real": model.openID = 4
        case "space-add-repos":
            model.openID = 7
            if let p = model.open { NewProjectDialogs.openAddRepos(model, p, picked: [Self.apiURL]) }
        default: break
        }
        await showKind(scene)
        await showWizard(scene)
        await showSpace(scene)
        await showOverviewScene(scene)
        await showModules(scene)
        await showPagesB(scene)
    }
}

enum DemoRepo {
    static func make(_ id: Int64, _ name: String, _ org: String) -> RepoItem {
        RepoItem(
            id: id, name: name, remoteURL: "https://github.com/\(org)/\(name)", branch: "main", primary: true,
            fetchedAt: Date(), fetchError: nil)
    }
}

extension ProjectItem {
    /// A copy with another link name (the id and the rest stay).
    static func renamed(_ p: ProjectItem, slug: String) -> ProjectItem {
        var q = ProjectItem(
            id: p.id, slug: slug, name: p.name, description: p.description, expose: p.expose, repos: p.repos,
            updatedAt: p.updatedAt)
        q.run = p.run
        q.live = p.live
        return q
    }
}

/// The stand-in "live" data of a project in each run state. Made-up names and lines; nothing reaches a Core.
enum DemoLive {
    static func make(_ state: RunSummary.State, progress: Double = 0) -> ProjectLive {
        let svc = [("web", "212 MB"), ("api", "148 MB"), ("queue", "96 MB"), ("mysql", "402 MB"), ("redis", "12 MB")]
        let cpu = [18, 9, 3, 6, 1]
        let services = svc.enumerated().map { i, s -> ProjectLive.Service in
            let st: ProjectLive.Service.State
            switch state {
            case .running: st = .up
            case .stopped: st = .down
            case .starting: st = Double(i) / 5 < progress ? .up : .down
            case .failed: st = s.0 == "api" ? .exited : .up
            }
            return ProjectLive.Service(
                name: s.0, memory: s.1, state: st, cpu: cpu[i], restarts: st == .exited ? 3 : 0)
        }
        let t = Date()
        let ok: [ProjectLive.LogLine] = [
            .init(service: "mysql", text: "ready for connections · 8.4.2", at: t.addingTimeInterval(-60)),
            .init(
                service: "api", text: "\u{1B}[32mServer running\u{1B}[0m on 0.0.0.0:8000", at: t.addingTimeInterval(-50)
            ),
            .init(service: "web", text: "Next.js 15.1 · ready in 2.1 s", at: t.addingTimeInterval(-40)),
            .init(service: "web", text: "GET / 200 in 84 ms", at: t.addingTimeInterval(-30)),
            .init(service: "api", text: "GET /api/products?page=1 200 31 ms", at: t.addingTimeInterval(-20)),
            .init(service: "queue", text: "ResizeImage ........ 212 ms DONE", at: t.addingTimeInterval(-10)),
        ]
        let bad: [ProjectLive.LogLine] = [
            .init(service: "mysql", text: "ready for connections · 8.4.2"),
            .init(service: "web", text: "Next.js 15.1 · ready in 2.1 s"),
            .init(service: "api", text: "Missing environment variable STRIPE_SECRET"),
            .init(service: "api", text: "exited with code 1"),
        ]
        var live = ProjectLive(
            services: services, logs: state == .failed ? bad : state == .starting ? [] : ok,
            sessions: [
                .init(
                    title: "Fix coupon rounding for EU orders", state: .needsYou, harness: "Claude Code", when: "14 m",
                    runner: "core-oracle", branch: "fix/coupon-rounding", cost: "$0.42"),
                .init(
                    title: "Move image uploads to object storage", state: .running, harness: "Codex", when: "1 h 2 m",
                    runner: "core-oracle", branch: "feat/object-storage", cost: "$1.10"),
                .init(
                    title: "Checkout rewrite: payment step", state: .done, harness: "Claude Code", when: "38 m",
                    runner: "this Mac", branch: "feat/checkout-pay", cost: "$0.64"),
                .init(
                    title: "Tidy the product page empty state", state: .done, harness: "Codex", when: "12 m",
                    runner: "core-oracle", branch: "ux/empty-state", cost: "$0.18"),
            ],
            repoExtras: [
                "lanterna-admin": .init(
                    usedBy: "2 AI sessions · the run (api)", size: "48 MB",
                    commits: [
                        .init(
                            title: "Round coupon totals per line, not per order", by: "Lina M. · 4 m", hash: "4e1c9a2"),
                        .init(title: "Add EU VAT rates for 2027", by: "AI session · 2 h", hash: "a81f03d"),
                        .init(title: "Cache product images for 1 day", by: "Omar K. · yesterday", hash: "5c2e7b0"),
                        .init(title: "Fix stock count after refunds", by: "Lina M. · Mon", hash: "e09d1aa"),
                        .init(title: "Upgrade Laravel to 11.31", by: "Omar K. · Sun", hash: "77b3c12"),
                    ])
            ],
            room: .init(
                overview: RoomOverview(
                    state: .written,
                    overview: OverviewBody(
                        summary:
                            "What this project is, how its parts fit together, and the rules an AI session follows here. Written from the repos, the docs and past sessions.",
                        facts: OverviewFacts(stack: "Laravel 11, Next.js 15, MySQL, Redis"),
                        rules: OverviewRules(
                            workflow: [
                                OverviewRule("Branch from development; one PR per change."),
                                OverviewRule("Run the API tests before pushing."),
                            ],
                            code: [
                                OverviewRule("Money is stored in cents, never floats."),
                                OverviewRule("Form requests validate; controllers stay thin."),
                            ],
                            design: [OverviewRule("Storefront components come from the shared kit.")],
                            never: [
                                OverviewRule("Never edit a migration that has shipped."),
                                OverviewRule("Never log customer addresses."),
                            ])),
                    instructionsApprovedAt: "2026-11-16T10:00:00Z"),
                items: 2320, updated: "2 h ago", approved: "yesterday"),
            roomID: "room_demo")
        if state == .running { live.idle = "idle 4 min of 30" }
        if state == .starting {
            live.progress = progress
            live.progressLine = "Pulling images · \(min(5, 1 + Int(progress * 5))) of 5 services"
        }
        if state == .failed {
            live.failure = "api stopped 40 s after start."
            live.failureFix = "STRIPE_SECRET is not set. Set it in Run › Secrets, then start again."
        }
        return live
    }
}

extension DemoLive {
    /// A calm hour of readings for the demo's five services, 30 a service.
    static func metrics() -> [String: ServiceSeries] {
        let base: [(String, Double, Double)] = [
            ("web", 18, 212), ("api", 9, 148), ("queue", 3, 96), ("mysql", 6, 402), ("redis", 1, 12),
        ]
        return Dictionary(
            uniqueKeysWithValues: base.enumerated().map { i, b in
                (
                    b.0,
                    ServiceSeries(
                        cpu: (0..<30).map { max(0, b.1 * (1 + 0.6 * sin(Double($0 + i * 5) / 3))) },
                        memory: (0..<30).map { (b.2 + Double($0) * b.2 / 120 + 4 * sin(Double($0 + i))) * 1_048_576 })
                )
            })
    }
}

extension ProjectsModel {
    /// Debug only: Start, Stop and Restart on the stand-in service; Start walks "starting" up to "running".
    func demoControl(_ action: RunAction, _ project: ProjectItem) {
        guard let s = service as? ProjectsDemo.Service else { return }
        Task { @MainActor in
            if action == .stop {
                s.setRun(project.id, .stopped)
                await reload()
                return
            }
            for step in 0...5 {
                s.setRun(project.id, .starting, progress: Double(step) / 5)
                await reload()
                try? await Task.sleep(for: .milliseconds(450))
            }
            s.setRun(project.id, .running)
            await reload()
        }
    }

    /// Debug only: attaches a stand-in service and reads it before returning (no background reload to race a scene).
    func useNow(_ s: any ProjectsService) async {
        service = s
        load = .loading
        await reload()
    }
    func setLoad(_ l: ProjectsLoad) { load = l }
    func setRunnerSupported(_ on: Bool) { runnerSupported = on }
}
#endif

/// A made-up web page: the stand-in for the running app's live view and for the pictures behind the cards.
struct DemoSitePage: View {
    let name: String
    let colour: ProjectColour
    // Drawn as a wide desktop page, so a frame shows it as a compact preview (details v2 mockup).
    private let design = CGSize(width: 1680, height: 1040)

    var body: some View {
        GeometryReader { g in
            page.frame(width: design.width, height: design.height)
                .scaleEffect(g.size.width / design.width, anchor: .topLeading)
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading).clipped()
        }
        .accessibilityHidden(true)
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 28) {
                Text(name).font(.system(size: 22, weight: .bold))
                ForEach(["Shop", "Stories", "About"], id: \.self) { Text($0).font(.system(size: 16)).opacity(0.6) }
                Spacer()
                Text("Cart (2)").font(.system(size: 16))
            }
            .padding(.horizontal, 48).frame(height: 76)
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [colour.fill.opacity(0.9), colour.fill.opacity(0.45)], startPoint: .topLeading,
                    endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Light for every room").font(.system(size: 54, weight: .bold))
                    Text("Handmade lamps, shipped in three days.").font(.system(size: 22)).opacity(0.85)
                    Text("Shop the collection").font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 22).frame(height: 44)
                        .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.black)
                }
                .foregroundStyle(.white).padding(.horizontal, 48)
            }
            .frame(height: 340)
            HStack(spacing: 20) {
                ForEach(0..<4, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 10).fill(colour.fill.opacity(0.18 + Double(i) * 0.06)).frame(
                            height: 130)
                        Text(["Dune", "Halo", "Moth", "Ember"][i]).font(.system(size: 16, weight: .semibold))
                        Text("$\(80 + i * 15)").font(.system(size: 14)).opacity(0.6)
                    }
                }
            }
            .padding(48)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.12))
        .background(Color(red: 0.98, green: 0.97, blue: 0.95))
    }
}
