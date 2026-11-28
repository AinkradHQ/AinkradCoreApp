import AinkradClient
import CoreKit
import Foundation
import OpenAPIRuntime

/// The API minor that brought the private preview, project colours, metrics, start steps, branch change and crash alerts.
let coreMinorProjects: Int32 = 110
/// The API minor that brought the project kind (`web`, `app`, `infra`, `other`).
let coreMinorKinds: Int32 = 111

/// The Core as the Projects screens use it (`/api/v1/projects`, AinkradCore PR #279). Reads need `read`; every write is
/// `admin` and step-up, so the model runs them through the host's Touch ID. Tests and the demo bring their own.
protocol ProjectsService: Sendable {
    func projects() async throws -> [ProjectItem]
    func create(slug: String, name: String) async throws -> ProjectItem
    func addRepo(project: Int64, name: String, url: String, primary: Bool) async throws
    func setExpose(project: Int64, _ on: Bool) async throws
    func update(project: Int64, name: String, description: String) async throws
    func archive(project: Int64) async throws
    /// Deletes an archived project for good, with its repos, copies and room link (`DELETE /projects/{id}`, API 112).
    func delete(project: Int64) async throws
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
    /// The Brain's places; nil when this Core has no Brain.
    func places() async throws -> [BrainPlace]?
    /// Links the project to an existing place, so the Brain makes no new one for it.
    func linkPlace(project: Int64, room: String) async throws
    func addRepo(project: Int64, name: String, url: String, branch: String, primary: Bool) async throws
    /// Changes the fields set in the patch (`PATCH /projects/{id}`); the rest is kept.
    func update(project: Int64, patch: ProjectPatch) async throws
    func removeRepo(project: Int64, repo: Int64) async throws
    func setPrimary(project: Int64, repo: Int64) async throws
    /// One project, for the watch on a copy (the whole list is not read again for it); nil when the service has no such route.
    func project(id: Int64) async throws -> ProjectItem?
    /// The runners the Core has, for "Where it runs".
    func runners() async throws -> [RunnerInfo]
    /// The project's AI sessions (newest first). The Core has no project filter on the list yet, so a live service reads a page
    /// and keeps the ones whose `project_id` is this project.
    func sessions(project: Int64) async throws -> [ProjectLive.Session]
    /// Makes a repo follow another branch of the Core's copy (`PATCH /projects/{id}/repos/{repo}`, API 110).
    func setBranch(project: Int64, repo: Int64, branch: String) async throws
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
    /// One of the accent names; "" clears it (API 110).
    var colour: String?
    /// One of `web`, `app`, `infra`, `other` (API 111).
    var kind: String?

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
    func sessions(project: Int64) async throws -> [ProjectLive.Session] { [] }
    func setBranch(project: Int64, repo: Int64, branch: String) async throws {
        throw CoreError.protocolViolation("This Core cannot change a repo's branch.")
    }
    // Stand-ins and tests that do not run projects need not answer these.
    func update(project: Int64, name: String, description: String) async throws {}
    func archive(project: Int64) async throws {}
    func delete(project: Int64) async throws { throw CoreError.protocolViolation("This Core cannot delete a project.") }
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
    func places() async throws -> [BrainPlace]? { nil }
    func linkPlace(project: Int64, room: String) async throws {}
}

struct LiveProjectsService: ProjectsService {
    let connection: CoreConnection
    private var client: Client { connection.client }

    private var has110: Bool { get async { await connection.serverSupports(minor: coreMinorProjects) } }

    func projects() async throws -> [ProjectItem] {
        // From minor 110 the list carries each project's `color`, which the synced client does not know: read it raw.
        if await has110 {
            return try Self.decode(try await signed("GET", "/api/v1/projects")).filter { !$0.archived }
        }
        return try await run {
            try await client.listProjects().ok.body.json.filter { $0.state != "archived" }.map(Self.item)
        }
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
        // `color` is not in the synced client: a patch that sets it goes as raw JSON.
        if p.colour != nil || p.kind != nil {
            _ = try await signed("PATCH", "/api/v1/projects/\(project)", body: Self.patchBody(p))
            return
        }
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
        if await has110 { return try Self.decode(try await signed("GET", "/api/v1/projects/\(id)")).first }
        return try await run { Self.item(try await client.getProject(path: .init(id: String(id))).ok.body.json) }
    }

    func setBranch(project: Int64, repo: Int64, branch: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["branch": branch])
        _ = try await signed("PATCH", "/api/v1/projects/\(project)/repos/\(repo)", body: body)
    }

    /// `PATCH /projects/{id}` as JSON: the fields the patch sets, by the Core's names.
    static func patchBody(_ p: ProjectPatch) throws -> Data {
        var o: [String: Any] = [:]
        if let v = p.name { o["name"] = v }
        if let v = p.description { o["description"] = v }
        if let v = p.slug { o["slug"] = v }
        if let v = p.expose { o["expose"] = v }
        if let v = p.runner { o["runner"] = v }
        if let v = p.cpuLimit { o["cpu_limit"] = v }
        if let v = p.memLimitMb { o["mem_limit_mb"] = v }
        if let v = p.idleMinutes { o["idle_minutes"] = v }
        if let v = p.idleNever { o["idle_never"] = v }
        if let v = p.colour { o["color"] = v }
        if let v = p.kind { o["kind"] = v }
        return try JSONSerialization.data(withJSONObject: o)
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

    func delete(project: Int64) async throws {
        guard await connection.serverSupports(minor: 112) else {
            throw CoreError.protocolViolation("This Core cannot delete a project.")
        }
        _ = try await signed("DELETE", "/api/v1/projects/\(project)")
    }

    func limits() async throws -> ProjectLimits? {
        guard await connection.serverSupports(minor: coreMinorV010) else { return nil }
        return try ProjectLimits.decode(try await signed("GET", "/api/v1/projects/defaults"))
    }

    func setLimits(_ limits: ProjectLimits) async throws {
        _ = try await signed("PUT", "/api/v1/projects/defaults", body: try limits.encoded())
    }

    func sessions(project: Int64) async throws -> [ProjectLive.Session] {
        // From minor 110 the Core filters by project itself.
        if await has110 {
            let data = try await signed("GET", "/api/v1/agent-sessions?project=\(project)&limit=200")
            let list = try Self.decoder().decode([Components.Schemas.AgentSession].self, from: data)
            return Self.rows(list, now: Date())
        }
        return try await run {
            let list = try await client.listAgentSessions(query: .init(limit: 200)).ok.body.json
            return Self.sessions(list, project: project, now: Date())
        }
    }

    /// The project's sessions as the Overview rows: waiting on a person, working, or done.
    static func sessions(_ all: [Components.Schemas.AgentSession], project: Int64, now: Date) -> [ProjectLive.Session] {
        rows(all.filter { $0.projectId == project }, now: now)
    }

    /// Sessions as the Overview rows, newest first as the Core sent them.
    static func rows(_ all: [Components.Schemas.AgentSession], now: Date) -> [ProjectLive.Session] {
        all.map { s in
            let state: ProjectLive.Session.State =
                s.waiting != nil ? .needsYou : ["starting", "running"].contains(s.state) ? .running : .done
            let micros = s.usage?.costUsdMicros
            return ProjectLive.Session(
                title: s.title ?? "AI session", state: state, harness: s.harness,
                when: PickRepo.ago(s.updatedAt, now), runner: s.placedOn ?? s.runner,
                branch: s.workspace?.value["branch"] as? String ?? "–",
                cost: micros.map { CostWords.money(Double($0) / 1_000_000) } ?? "–", id: s.id)
        }
    }

    func places() async throws -> [BrainPlace]? {
        struct Room: Decodable {
            let id: String
            let name: String
            let state: String?
        }
        let data: Data
        do { data = try await signed("GET", "/modules/brain/v1/rooms") } catch CoreError.http(404, _, _) { return nil }
        return try JSONDecoder().decode([Room].self, from: data).filter { $0.state != "archived" }
            .map { BrainPlace(id: $0.id, name: $0.name) }
    }

    /// The Brain gives a new project its own place a few seconds after it is made, unless one was linked first. If it
    /// was quicker, its new place is let go (it stays in the Brain, empty) and the chosen one linked.
    func linkPlace(project: Int64, room: String) async throws {
        let path = "/modules/brain/v1/projects/\(project)/room"
        let body = try JSONSerialization.data(withJSONObject: ["room": room])
        do { _ = try await signed("PUT", path, body: body) } catch CoreError.http(409, "project_linked", _) {
            _ = try await signed("DELETE", path)
            _ = try await signed("PUT", path, body: body)
        }
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
        // From minor 110 `GET /run` carries the start's steps, which the synced client does not know: read it raw.
        if await has110 {
            do {
                return try Self.runState(try await signed("GET", "/api/v1/projects/\(project)/run"))
            } catch CoreError.http(404, _, _) { return nil }
        }
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
            startedAt: r.startedAt, idleStopAt: r.idleStopAt, error: r.error, stopReason: r.stopReason,
            runner: r.runner, lastActivityAt: r.lastActivityAt)
    }

    /// `GET /run` as JSON: the generated type reads the run, the raw object adds the steps.
    static func runState(_ data: Data) throws -> ProjectRunState {
        var state = Self.state(try decoder().decode(Components.Schemas.ProjectRun.self, from: data))
        state.steps = RunStep.read((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["steps"])
        return state
    }

    private static let unknown = CoreError.protocolViolation("The Core answered something this app does not know.")

    /// Whatever the generated client threw, as the `CoreError` inside it.
    private func run<T>(_ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch {
            if let core = CoreFailure.of(error) { throw core }
            // A slow or dropped connection is said as such, never as an answer the app "does not know".
            if let net = Self.network(error) { throw net }
            throw Self.unknown
        }
    }

    /// The URLError inside whatever the generated client wrapped, if the request never got its answer.
    static func network(_ error: any Error) -> URLError? {
        var current: (any Error)? = error
        for _ in 0..<6 {
            guard let e = current else { return nil }
            if let u = e as? URLError { return u }
            current =
                (e as NSError).userInfo[NSUnderlyingErrorKey] as? any Error
                ?? Mirror(reflecting: e).children.lazy.compactMap { $0.value as? any Error }.first
        }
        return nil
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
            source: p.source, createdAt: p.createdAt, roomID: p.room?.roomId, archived: p.state == "archived")
    }

    /// The decoder for the Core's JSON: dates read as the client reads them.
    static func decoder() -> JSONDecoder {
        let transcoder = Configuration(dateTranscoder: .iso8601WithFractionalSeconds).dateTranscoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            try transcoder.decode(try d.singleValueContainer().decode(String.self))
        }
        return decoder
    }

    /// The Core's list (or one project) as JSON (the shapes of `api/openapi.json`): the projects, each with the `color` the
    /// Core holds (API 110), which the synced client does not know.
    static func decode(_ data: Data) throws -> [ProjectItem] {
        let json = try? JSONSerialization.jsonObject(with: data)
        var colours: [Int64: String] = [:]
        var kinds: [Int64: String] = [:]
        for o in (json as? [[String: Any]]) ?? (json as? [String: Any]).map({ [$0] }) ?? [] {
            if let id = (o["id"] as? NSNumber)?.int64Value, let c = o["color"] as? String, !c.isEmpty {
                colours[id] = c
            }
            if let id = (o["id"] as? NSNumber)?.int64Value, let k = o["kind"] as? String, !k.isEmpty { kinds[id] = k }
        }
        let infos: [Components.Schemas.ProjectInfo] =
            json is [Any]
            ? try decoder().decode([Components.Schemas.ProjectInfo].self, from: data)
            : [try decoder().decode(Components.Schemas.ProjectInfo.self, from: data)]
        return infos.map {
            var p = item($0)
            p.colourName = colours[$0.id]
            p.kindName = kinds[$0.id]
            return p
        }
    }
}
