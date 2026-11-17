#if DEBUG
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
    }

    public static let scenes = [
        "gallery", "gallery-hover", "gallery-filtered", "gallery-empty", "gallery-loading", "gallery-offline",
        "gallery-failed", "new-quick-empty", "new-quick", "new-quick-error", "new-advanced", "space-no-repos",
        "space-add-repos", "space-copying", "space-setting-up", "space-ready",
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
                updatedAt: now.addingTimeInterval(-hours * 3600), run: run)
        }
        return [
            p(1, "lanterna", "Lanterna", RunSummary(state: .running, services: 5, sessions: 2), hours: 1),
            p(2, "northwind-ledger", "Northwind Ledger", RunSummary(state: .stopped, lastRun: "yesterday"), hours: 2),
            p(3, "quill", "Quill", RunSummary(state: .failed, lastRun: "20 min ago"), hours: 3),
            p(4, "harbor-crm", "Harbor CRM", RunSummary(state: .stopped, lastRun: "Mon"), hours: 80),
        ]
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

    /// The screens behave as if Reduce Motion were on (the system setting cannot be set from inside the app).
    public static func forceReduceMotion(_ on: Bool) { ProjectsMotion.forceReduce = on }

    /// For clicking through by hand.
    public func showInteractive(_ scene: String) async { await show(scene) }

    public func show(_ scene: String) async {
        let shell = model.host.shell
        shell.dialog = nil
        shell.overlay = nil
        shell.launcherOpen = false
        shell.linkNotice = nil
        shell.coreLink = .live
        model.host.clearElevationNotice()
        model.quickOpen = false
        model.quickName = ""
        model.filter = ""
        model.cursor = nil
        model.openID = nil
        model.debugHover = nil
        model.clearWriteError()
        var list = Self.sample()
        switch scene {
        case "gallery-empty": list = []
        case "space-no-repos", "space-add-repos": list.insert(Self.tidepool(repos: 0), at: 0)
        case "space-copying": list.insert(Self.tidepool(repos: 2, fetched: false), at: 0)
        case "space-setting-up": list.insert(Self.tidepool(repos: 2), at: 0)
        case "space-ready": list.insert(Self.tidepool(repos: 2, draft: true), at: 0)
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
        case "space-add-repos":
            model.openID = 7
            if let p = model.open { NewProjectDialogs.openAddRepos(model, p, picked: [Self.apiURL]) }
        default: break
        }
    }
}

extension ProjectsModel {
    /// Debug only: attaches a stand-in service and reads it before returning (no background reload to race a scene).
    func useNow(_ s: any ProjectsService) async {
        service = s
        load = .loading
        await reload()
    }
    func setLoad(_ l: ProjectsLoad) { load = l }
}
#endif
