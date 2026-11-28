import AinkradClient
import CoreKit
import Foundation
import OpenAPIRuntime

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
            guard case CoreError.http(409, "no_connection", _)? = CoreFailure.of(error) else {
                throw CoreFailure.of(error) ?? error
            }
            // Connected, but never made the default (Connections does not set one): with exactly one GitHub
            // connection the choice is not ambiguous, so make it the default and ask once more.
            guard try await adoptOnlyGithub() else { return nil }
            list = try await connection.client.listGithubRepos(
                query: .init(q: query.isEmpty ? nil : query, page: Int64(page), perPage: 30)
            ).ok.body.json
        }
        return Self.page(list)
    }

    /// Makes the workspace's one usable GitHub connection its default; false when it has none or several.
    private func adoptOnlyGithub() async throws -> Bool {
        let all = try await connection.client.listConnections().ok.body.json
        let github = all.filter { $0.kind == "github" && !$0.disabled && $0.status != "disabled" }
        guard github.count == 1 else { return false }
        let body = try JSONSerialization.data(withJSONObject: ["connection": github[0].id])
        _ = try await connection.signedRequest(method: "PUT", target: "/api/v1/connection-defaults/github", body: body)
        return true
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
