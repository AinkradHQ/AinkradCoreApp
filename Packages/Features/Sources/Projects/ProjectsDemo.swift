#if DEBUG
import Brain
import Foundation
import Shell
import SwiftUI

/// Debug only: every Projects state on sample data and a stand-in service, for screenshots and for the reviewer to click
/// through. Nothing here reaches a Core. The names are made up; the links go nowhere.
@MainActor
public final class ProjectsDemo {
    final class Service: ProjectsService, @unchecked Sendable {
        private let lock = NSLock()
        private var list: [ProjectItem]
        private var next: Int64 = 100
        init(_ list: [ProjectItem]) { self.list = list }
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
        func setRun(_ project: Int64, _ state: RunSummary.State, progress: Double = 0) {
            lock.withLock {
                guard let i = list.firstIndex(where: { $0.id == project }) else { return }
                list[i].run = RunSummary(
                    state: state, services: 5, sessions: 2, lastRun: state == .stopped ? "just now" : nil)
                list[i].live = DemoLive.make(state, progress: progress)
            }
        }
    }

    public static let scenes = [
        "gallery", "gallery-hover", "gallery-filtered", "gallery-empty", "gallery-loading", "gallery-offline",
        "gallery-failed", "new-quick-empty", "new-quick", "new-quick-error", "new-advanced", "space-no-repos",
        "space-add-repos", "space-copying", "space-setting-up", "space-ready", "overview-running", "overview-starting",
        "overview-stopped", "overview-failed", "overview-real-core", "page-run", "page-repos", "page-sessions",
        "page-brain", "page-brain-empty",
    ]

    private let model: ProjectsModel
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

    private static func tidepool(repos: Int, fetched: Bool = true, draft: Bool = false) -> ProjectItem {
        ProjectItem(
            id: 7, slug: "tidepool", name: "Tidepool", description: "", expose: true,
            repos: [repo(1, "tidepool-api", fetched: fetched), repo(2, "tidepool-web", fetched: fetched)].prefix(repos)
                .map { $0 },
            updatedAt: Date(), run: nil,
            draft: draft
                ? RunDraft(
                    source: "docker-compose.yml", services: ["web", "api", "postgres"],
                    secrets: ["DATABASE_URL", "JWT_SECRET"]) : nil)
    }

    private static let apiURL = "https://github.com/tidepool-labs/tidepool-api"
    private static let webURL = "https://github.com/tidepool-labs/tidepool-web"

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
        model.quickOpen = false
        model.quickName = ""
        model.filter = ""
        model.cursor = nil
        model.openID = nil
        model.section = .overview
        model.debugHover = nil
        model.clearWriteError()
        var list = Self.sample()
        switch scene {
        case "gallery-empty": list = []
        case "space-no-repos", "space-add-repos": list.insert(Self.tidepool(repos: 0), at: 0)
        case "space-copying": list.insert(Self.tidepool(repos: 2, fetched: false), at: 0)
        case "space-setting-up": list.insert(Self.tidepool(repos: 2), at: 0)
        case "space-ready": list.insert(Self.tidepool(repos: 2, draft: true), at: 0)
        case "overview-starting":
            list[1].run = RunSummary(state: .starting, services: 5)
            list[1].live = DemoLive.make(.starting, progress: 0.4)
        // A real Core today: no run state, services, logs, sessions or room.
        case "overview-real-core", "page-brain-empty":
            list[3].run = nil
            list[3].live = nil
        default: break
        }
        await model.useNow(Service(list))
        model.show()
        try? await Task.sleep(for: .milliseconds(400))
        switch scene {
        case "gallery-hover": model.debugHover = 1
        case "gallery-filtered": model.filter = "n"
        case "gallery-loading": model.setLoad(.loading)
        case "gallery-offline": model.setLoad(.notConnected)
        case "gallery-failed": model.setLoad(.failed("The Core did not answer in time (timeout)."))
        case "new-quick-empty": model.quickOpen = true
        case "new-quick":
            model.quickName = "Tidepool"
            model.quickOpen = true
        case "new-quick-error":
            model.quickName = "7 seas"
            model.quickOpen = true
        case "new-advanced":
            NewProjectDialogs.openAdvanced(model, name: "Tidepool", picked: [Self.apiURL, Self.webURL])
        case "space-no-repos", "space-copying", "space-setting-up", "space-ready": model.openID = 7
        case "overview-running": model.openID = 1
        case "page-run":
            model.openID = 1
            model.section = .run
        case "page-repos":
            model.openID = 1
            model.section = .repos
        case "page-sessions":
            model.openID = 1
            model.section = .sessions
        case "page-brain", "page-brain-empty":
            model.openID = scene == "page-brain" ? 1 : 4
            model.section = .brain
        case "overview-starting": model.openID = 2
        case "overview-failed": model.openID = 3
        case "overview-stopped", "overview-real-core": model.openID = 4
        case "space-add-repos":
            model.openID = 7
            if let p = model.open { NewProjectDialogs.openAddRepos(model, p, picked: [Self.apiURL]) }
        default: break
        }
    }
}

/// The stand-in "live" data of a project in each run state. Made-up names and lines; nothing reaches a Core.
enum DemoLive {
    static func make(_ state: RunSummary.State, progress: Double = 0) -> ProjectLive {
        let svc = [("web", "212 MB"), ("api", "148 MB"), ("queue", "96 MB"), ("mysql", "402 MB"), ("redis", "12 MB")]
        let services = svc.enumerated().map { i, s -> ProjectLive.Service in
            let st: ProjectLive.Service.State
            switch state {
            case .running: st = .up
            case .stopped: st = .down
            case .starting: st = Double(i) / 5 < progress ? .up : .down
            case .failed: st = s.0 == "api" ? .exited : .up
            }
            return ProjectLive.Service(name: s.0, memory: s.1, state: st)
        }
        let ok: [ProjectLive.LogLine] = [
            .init(service: "mysql", text: "ready for connections · 8.4.2"),
            .init(service: "api", text: "Server running on 0.0.0.0:8000"),
            .init(service: "web", text: "Next.js 15.1 · ready in 2.1 s"),
            .init(service: "web", text: "GET / 200 in 84 ms"),
            .init(service: "api", text: "GET /api/products?page=1 200 31 ms"),
            .init(service: "queue", text: "ResizeImage ........ 212 ms DONE"),
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
                            "Lanterna is an online shop for handmade lighting. A Laravel API handles catalogue, orders and payments; a Next.js storefront sells to customers and a small admin manages stock.",
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
                items: 2320, updated: "2 h ago", approved: "yesterday"))
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
}
#endif
