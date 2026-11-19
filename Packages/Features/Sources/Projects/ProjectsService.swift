import AinkradClient
import CoreKit
import Foundation
import OpenAPIRuntime

/// The Core as the Projects screens use it (`/api/v1/projects`, AinkradCore PR #279). Reads need `read`; every write is
/// `admin` and step-up, so the model runs them through the host's Touch ID. Tests and the demo bring their own.
protocol ProjectsService: Sendable {
    func projects() async throws -> [ProjectItem]
    func create(slug: String, name: String) async throws -> ProjectItem
    func addRepo(project: Int64, name: String, url: String, primary: Bool) async throws
    func setExpose(project: Int64, _ on: Bool) async throws
    func update(project: Int64, name: String, description: String) async throws
    func archive(project: Int64) async throws
    /// The newest run; nil when the project never ran.
    func run(project: Int64) async throws -> ProjectRunState?
    func control(project: Int64, _ action: RunAction) async throws -> ProjectRunState
    /// "A viewer is on the Run tab": pushes the idle stop back.
    func touch(project: Int64) async throws -> ProjectRunState?
    /// "Fetch now": the Core copies the repo again (a failed fetch is still an answer; the repo's state says why).
    func fetch(project: Int64, repo: Int64) async throws
}

extension ProjectsService {
    // Stand-ins and tests that do not run projects need not answer these.
    func update(project: Int64, name: String, description: String) async throws {}
    func archive(project: Int64) async throws {}
    func run(project: Int64) async throws -> ProjectRunState? { nil }
    func control(project: Int64, _ action: RunAction) async throws -> ProjectRunState {
        throw CoreError.protocolViolation("This Core cannot run projects.")
    }
    func touch(project: Int64) async throws -> ProjectRunState? { nil }
    func fetch(project: Int64, repo: Int64) async throws {}
}

struct LiveProjectsService: ProjectsService {
    let connection: CoreConnection
    private var client: Client { connection.client }

    func projects() async throws -> [ProjectItem] {
        try await run { try await client.listProjects().ok.body.json.filter { $0.state != "archived" }.map(Self.item) }
    }

    func create(slug: String, name: String) async throws -> ProjectItem {
        try await run {
            Self.item(try await client.createProject(body: .json(.init(name: name, slug: slug))).ok.body.json)
        }
    }

    func addRepo(project: Int64, name: String, url: String, primary: Bool) async throws {
        try await run {
            _ = try await client.addProjectRepo(
                path: .init(id: String(project)),
                body: .json(.init(defaultBranch: "main", name: name, primary: primary, remoteUrl: url))
            ).ok
        }
    }

    func fetch(project: Int64, repo: Int64) async throws {
        try await run { _ = try await client.fetchProjectRepo(path: .init(id: String(project), repo: String(repo))).ok }
    }

    func setExpose(project: Int64, _ on: Bool) async throws {
        try await run {
            _ = try await client.updateProject(path: .init(id: String(project)), body: .json(.init(expose: on))).ok
        }
    }

    func update(project: Int64, name: String, description: String) async throws {
        try await run {
            _ = try await client.updateProject(
                path: .init(id: String(project)), body: .json(.init(description: description, name: name))
            ).ok
        }
    }

    func archive(project: Int64) async throws {
        try await run { _ = try await client.archiveProject(path: .init(id: String(project))).ok }
    }

    // The run routes arrive with the Core's P5-03 (#318): `getProjectRun`, `startProjectRun`, `stopProjectRun`,
    // `restartProjectRun` and `touchProjectRun`, all answering `ProjectRun`. They are not in the synced client until the epic's
    // regen, so this compiles at the epic build.
    func run(project: Int64) async throws -> ProjectRunState? {
        do {
            return try await run {
                Self.state(try await client.getProjectRun(path: .init(id: String(project))).ok.body.json)
            }
        } catch CoreError.http(404, _, _) { return nil }
    }

    func control(project: Int64, _ action: RunAction) async throws -> ProjectRunState {
        try await run {
            switch action {
            case .start: Self.state(try await client.startProjectRun(path: .init(id: String(project))).ok.body.json)
            case .stop: Self.state(try await client.stopProjectRun(path: .init(id: String(project))).ok.body.json)
            case .restart: Self.state(try await client.restartProjectRun(path: .init(id: String(project))).ok.body.json)
            }
        }
    }

    func touch(project: Int64) async throws -> ProjectRunState? {
        do {
            return try await run {
                Self.state(try await client.touchProjectRun(path: .init(id: String(project))).ok.body.json)
            }
        } catch CoreError.http(404, _, _) { return nil }
    }

    /// `stopping` reads as stopped: the Core finishes it on its own and the next read says so.
    static func state(_ r: Components.Schemas.ProjectRun) -> ProjectRunState {
        let state: RunSummary.State =
            switch r.state {
            case "running": .running
            case "starting": .starting
            case "failed": .failed
            default: .stopped
            }
        return ProjectRunState(
            summary: RunSummary(
                state: state, lastRun: r.stoppedAt.map { PickRepo.ago($0, Date()) }),
            startedAt: r.startedAt, idleStopAt: r.idleStopAt, error: r.error, stopReason: r.stopReason)
    }

    private static let unknown = CoreError.protocolViolation("The Core answered something this app does not know.")

    /// Whatever the generated client threw, as the `CoreError` inside it.
    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch { throw CoreFailure.of(error) ?? Self.unknown }
    }

    static func item(_ p: Components.Schemas.ProjectInfo) -> ProjectItem {
        ProjectItem(
            id: p.id, slug: p.slug, name: p.name, description: p.description, expose: p.expose,
            repos: p.repos.map {
                RepoItem(
                    id: $0.id, name: $0.name, remoteURL: $0.remoteUrl, branch: $0.defaultBranch,
                    primary: $0.isPrimary, fetchedAt: $0.mirror?.fetchedAt, fetchError: $0.mirror?.error,
                    head: $0.mirror?.head, state: $0.mirror?.state, reason: $0.mirror?.reason,
                    startedAt: $0.mirror?.startedAt)
            }, updatedAt: p.updatedAt, cpuLimit: p.cpuLimit, memLimitMb: p.memLimitMb,
            idleMinutes: Int(p.idleMinutes))
    }
}


/// GitHub's repos as the Core lists them for the workspace's connection; nil while no connection is set up
/// (409 `no_connection`), so the picker says "Connect GitHub".
struct LiveRepoCatalog: RepoCatalog {
    let connection: CoreConnection

    func repos() async throws -> [PickRepo]? {
        var out: [PickRepo] = []
        var page: Int64 = 1
        while page <= 10 {
            let list: Components.Schemas.GithubRepoList
            do {
                list = try await connection.client.listGithubRepos(query: .init(page: page, perPage: 100)).ok.body.json
            } catch {
                if case CoreError.http(409, _, _)? = CoreFailure.of(error) { return nil }
                throw CoreFailure.of(error) ?? error
            }
            for o in list.owners {
                for r in o.repos {
                    out.append(PickRepo(org: o.owner, name: r.name, url: "https://github.com/\(r.fullName)"))
                }
            }
            if !list.hasMore { break }
            page += 1
        }
        return out
    }
}
