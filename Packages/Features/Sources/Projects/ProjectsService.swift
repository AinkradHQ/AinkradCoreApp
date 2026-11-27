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
    /// The archived projects (the Options tab's "Show archived projects").
    func archivedProjects() async throws -> [ProjectItem]
    func unarchive(project: Int64) async throws
    /// What a run gets unless a project says otherwise (Core 0.10); nil on a Core that has no such setting.
    func limits() async throws -> ProjectLimits?
    /// Saves them for every project.
    func setLimits(_ limits: ProjectLimits) async throws
    /// The newest run; nil when the project never ran.
    func run(project: Int64) async throws -> ProjectRunState?
    func control(project: Int64, _ action: RunAction) async throws -> ProjectRunState
    /// "A viewer is on the Run tab": pushes the idle stop back.
    func touch(project: Int64) async throws -> ProjectRunState?
    /// "Fetch now": the Core copies the repo again (a failed fetch is still an answer; the repo's state says why).
    func fetch(project: Int64, repo: Int64) async throws
    /// Where the project prefers to run: `auto`, `this_mac` or `home_server` (Core minor 95).
    func setRunner(project: Int64, _ runner: String) async throws
    /// A new project with a description and a runner preference in the same call (`POST /projects`).
    func create(slug: String, name: String, description: String, runner: String?) async throws -> ProjectItem
    /// A project made from GitHub repos (`owner/name`) in one step: the Core reads each repo's real default branch.
    func createFromGithub(slug: String, name: String, repos: [String]) async throws -> ProjectItem
    func addRepo(project: Int64, name: String, url: String, branch: String, primary: Bool) async throws
    /// Changes the fields set in the patch (`PATCH /projects/{id}`); the rest is kept.
    func update(project: Int64, patch: ProjectPatch) async throws
    func removeRepo(project: Int64, repo: Int64) async throws
    func setPrimary(project: Int64, repo: Int64) async throws
    /// One project, for the watch on a copy (the whole list is not read again for it); nil when the service has no such route.
    func project(id: Int64) async throws -> ProjectItem?
    /// The runners the Core has, for "Where it runs".
    func runners() async throws -> [RunnerInfo]
}

/// What a PATCH of a project changes: a nil field is left as it is.
struct ProjectPatch: Equatable, Sendable {
    var name: String?
    var description: String?
    var slug: String?
    var expose: Bool?
    var runner: String?
    var cpuLimit: Double?
    var memLimitMb: Int64?
    var idleMinutes: Int64?
    var idleNever: Bool?

    var isEmpty: Bool { self == ProjectPatch() }
}

/// A runner of the Core as "Where it runs" needs it: `this_mac` is a Mac runner and `home_server` a Linux one.
struct RunnerInfo: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    /// `macos` or `linux` once it has connected.
    let os: String?
    let online: Bool
}

extension ProjectsService {
    // Stand-ins and tests that do not run projects need not answer these.
    func update(project: Int64, name: String, description: String) async throws {}
    func archive(project: Int64) async throws {}
    func archivedProjects() async throws -> [ProjectItem] { [] }
    func unarchive(project: Int64) async throws {}
    func limits() async throws -> ProjectLimits? { nil }
    func setLimits(_ limits: ProjectLimits) async throws {}
    func run(project: Int64) async throws -> ProjectRunState? { nil }
    func control(project: Int64, _ action: RunAction) async throws -> ProjectRunState {
        throw CoreError.protocolViolation("This Core cannot run projects.")
    }
    func touch(project: Int64) async throws -> ProjectRunState? { nil }
    func fetch(project: Int64, repo: Int64) async throws {}
    func setRunner(project: Int64, _ runner: String) async throws {}
    func create(slug: String, name: String, description: String, runner: String?) async throws -> ProjectItem {
        try await create(slug: slug, name: name)
    }
    /// Stand-ins and tests: a project, then its repos (the live service makes them in one call).
    func createFromGithub(slug: String, name: String, repos: [String]) async throws -> ProjectItem {
        let p = try await create(slug: slug, name: name)
        for (i, full) in repos.enumerated() {
            try await addRepo(
                project: p.id, name: full.split(separator: "/").last.map(String.init) ?? full,
                url: "https://github.com/\(full)", branch: "main", primary: i == 0)
        }
        return p
    }
    func addRepo(project: Int64, name: String, url: String, branch: String, primary: Bool) async throws {
        try await addRepo(project: project, name: name, url: url, primary: primary)
    }
    func update(project: Int64, patch: ProjectPatch) async throws {}
    func removeRepo(project: Int64, repo: Int64) async throws {}
    func setPrimary(project: Int64, repo: Int64) async throws {}
    func project(id: Int64) async throws -> ProjectItem? { nil }
    func runners() async throws -> [RunnerInfo] { [] }
}

struct LiveProjectsService: ProjectsService {
    let connection: CoreConnection
    private var client: Client { connection.client }

    func projects() async throws -> [ProjectItem] {
        try await run { try await client.listProjects().ok.body.json.filter { $0.state != "archived" }.map(Self.item) }
    }

    func create(slug: String, name: String) async throws -> ProjectItem {
        try await create(slug: slug, name: name, description: "", runner: nil)
    }

    func create(slug: String, name: String, description: String, runner: String?) async throws -> ProjectItem {
        try await run {
            Self.item(
                try await client.createProject(
                    body: .json(
                        .init(
                            description: description.isEmpty ? nil : description, name: name,
                            runner: runner == "auto" ? nil : runner, slug: slug))
                ).ok.body.json)
        }
    }

    func createFromGithub(slug: String, name: String, repos: [String]) async throws -> ProjectItem {
        try await run {
            Self.item(
                try await client.createProjectFromGithub(body: .json(.init(name: name, repos: repos, slug: slug))).ok
                    .body.json)
        }
    }

    func addRepo(project: Int64, name: String, url: String, primary: Bool) async throws {
        try await addRepo(project: project, name: name, url: url, branch: "main", primary: primary)
    }

    func addRepo(project: Int64, name: String, url: String, branch: String, primary: Bool) async throws {
        try await run {
            _ = try await client.addProjectRepo(
                path: .init(id: String(project)),
                body: .json(.init(defaultBranch: branch, name: name, primary: primary, remoteUrl: url))
            ).ok
        }
    }

    func update(project: Int64, patch p: ProjectPatch) async throws {
        try await run {
            _ = try await client.updateProject(
                path: .init(id: String(project)),
                body: .json(
                    .init(
                        cpuLimit: p.cpuLimit, description: p.description, expose: p.expose,
                        idleMinutes: p.idleMinutes, idleNever: p.idleNever, memLimitMb: p.memLimitMb, name: p.name,
                        runner: p.runner, slug: p.slug))
            ).ok
        }
    }

    func removeRepo(project: Int64, repo: Int64) async throws {
        try await run {
            _ = try await client.removeProjectRepo(path: .init(id: String(project), repo: String(repo))).ok
        }
    }

    func setPrimary(project: Int64, repo: Int64) async throws {
        try await run {
            _ = try await client.setProjectRepoPrimary(path: .init(id: String(project), repo: String(repo))).ok
        }
    }

    func project(id: Int64) async throws -> ProjectItem? {
        try await run { Self.item(try await client.getProject(path: .init(id: String(id))).ok.body.json) }
    }

    func runners() async throws -> [RunnerInfo] {
        try await run {
            try await client.listRunners().ok.body.json.map {
                RunnerInfo(id: $0.id, name: $0.name, os: $0.os, online: $0.online ?? false)
            }
        }
    }

    func fetch(project: Int64, repo: Int64) async throws {
        try await run { _ = try await client.fetchProjectRepo(path: .init(id: String(project), repo: String(repo))).ok }
    }

    // `UpdateProject.runner` arrives with the Core's E11-2 (#395); it compiles at the epic's regen.
    func setRunner(project: Int64, _ runner: String) async throws {
        try await run {
            _ = try await client.updateProject(path: .init(id: String(project)), body: .json(.init(runner: runner))).ok
        }
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

    func archivedProjects() async throws -> [ProjectItem] {
        try await run {
            try await client.listProjects(query: .init(archived: true)).ok.body.json.filter { $0.state == "archived" }
                .map(Self.item)
        }
    }

    // The 0.10 routes are not in the synced client until the epic's regeneration, so they go through the signed transport,
    // and only when the Core speaks API minor 95.
    func unarchive(project: Int64) async throws {
        _ = try await signed("POST", "/api/v1/projects/\(project)/unarchive")
    }

    func limits() async throws -> ProjectLimits? {
        guard await connection.serverSupports(minor: coreMinorV010) else { return nil }
        return try ProjectLimits.decode(try await signed("GET", "/api/v1/projects/defaults"))
    }

    func setLimits(_ limits: ProjectLimits) async throws {
        _ = try await signed("PUT", "/api/v1/projects/defaults", body: try limits.encoded())
    }

    private func signed(_ method: String, _ path: String, body: Data = Data()) async throws -> Data {
        do { return try await connection.signedRequest(method: method, target: path, body: body) } catch {
            throw CoreFailure.of(error) ?? error
        }
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
                    startedAt: $0.mirror?.startedAt, hasMirror: $0.mirror != nil)
            }, updatedAt: p.updatedAt, cpuLimit: p.cpuLimit, memLimitMb: p.memLimitMb,
            idleMinutes: Int(p.idleMinutes), idleNever: p.idleNever ?? false, runner: p.runner ?? "auto",
            source: p.source, createdAt: p.createdAt, archived: p.state == "archived")
    }

    /// The Core's list as JSON (the shapes of `api/openapi.json`), for tests: dates read as the client reads them.
    static func decode(_ data: Data) throws -> [ProjectItem] {
        let transcoder = Configuration(dateTranscoder: .iso8601WithFractionalSeconds).dateTranscoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            try transcoder.decode(try d.singleValueContainer().decode(String.self))
        }
        return try decoder.decode([Components.Schemas.ProjectInfo].self, from: data).map(item)
    }
}

/// GitHub's repos as the Core lists them for the workspace's connection, a page at a time and searched on the Core (`q`);
/// nil while no connection is set up (409 `no_connection`), so the picker says "Connect GitHub".
struct LiveRepoCatalog: RepoCatalog {
    let connection: CoreConnection

    func page(query: String, page: Int) async throws -> RepoPage? {
        let list: Components.Schemas.GithubRepoList
        do {
            list = try await connection.client.listGithubRepos(
                query: .init(q: query.isEmpty ? nil : query, page: Int64(page), perPage: 30)
            ).ok.body.json
        } catch {
            if case CoreError.http(409, "no_connection", _)? = CoreFailure.of(error) { return nil }
            throw CoreFailure.of(error) ?? error
        }
        return Self.page(list)
    }

    /// The Core's answer as JSON, for tests.
    static func decode(_ data: Data) throws -> RepoPage {
        try Self.page(JSONDecoder().decode(Components.Schemas.GithubRepoList.self, from: data))
    }

    static func page(_ list: Components.Schemas.GithubRepoList) -> RepoPage {
        RepoPage(
            repos: list.owners.flatMap { o in
                o.repos.map {
                    PickRepo(
                        org: o.owner, name: $0.name, url: "https://github.com/\($0.fullName)", fullName: $0.fullName,
                        defaultBranch: $0.defaultBranch.isEmpty ? nil : $0.defaultBranch, isPrivate: $0._private,
                        blurb: $0.description)
                }
            }, hasMore: list.hasMore, truncated: list.truncated)
    }
}
