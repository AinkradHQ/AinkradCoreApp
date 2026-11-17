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
}

struct LiveProjectsService: ProjectsService {
    let connection: CoreConnection
    private var client: Client { connection.client }

    func projects() async throws -> [ProjectItem] {
        try await run { try await client.listProjects().ok.body.json.map(Self.item) }
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

    func setExpose(project: Int64, _ on: Bool) async throws {
        try await run {
            _ = try await client.updateProject(path: .init(id: String(project)), body: .json(.init(expose: on))).ok
        }
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
                    head: $0.mirror?.head)
            }, updatedAt: p.updatedAt)
    }
}
