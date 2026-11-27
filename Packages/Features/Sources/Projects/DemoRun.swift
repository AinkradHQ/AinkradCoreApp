#if DEBUG
import Foundation

/// Debug only: the Run page's spec, secrets and run on made-up data, for screenshots and for clicking through. Writes work
/// in memory (a saved setup is a new version, a secret keeps only its name and date). Nothing reaches a Core.
final class DemoRunService: ProjectRunService, @unchecked Sendable {
    private let lock = NSLock()
    private var versions: [Int64: [SpecVersionItem]] = [:]
    private var stored: [Int64: [SecretItem]] = [:]

    static let full = """
        {"services": {
          "web": {"image": "node:22-alpine", "ports": [{"port": 3000, "expose": true}], "env": {"API_URL": "http://api:8000"}},
          "api": {"image": "php:8.3-fpm", "ports": [{"port": 8000}], "depends_on": ["mysql"],
                  "env": {"APP_KEY": "${secret:app_key}", "DB_PASSWORD": "${secret:db_password}", "STRIPE_SECRET": "${secret:stripe_secret}"}},
          "queue": {"image": "php:8.3-cli"},
          "mysql": {"image": "mysql:8.4", "ports": [{"port": 3306}]},
          "redis": {"image": "redis:7", "ports": [{"port": 6379}]}}}
        """
    static let small = """
        {"services": {"web": {"image": "node:22-alpine", "ports": [{"port": 3000, "expose": true}]},
          "api": {"image": "php:8.3-fpm", "ports": [{"port": 8000}]}}}
        """
    static let compose = """
        {"services": {"web": {"image": "node:22-alpine", "ports": [{"port": 3000, "expose": true}]},
          "api": {"image": "golang:1.24", "ports": [{"port": 8080}], "env": {"JWT_SECRET": "${secret:jwt_secret}"}},
          "postgres": {"image": "postgres:17", "ports": [{"port": 5432}]}}}
        """

    private func item(_ version: Int, _ origin: String, _ json: String) -> SpecVersionItem {
        let wrapped = Data(#"{"version": \#(version), "origin": "\#(origin)", "spec": \#(json)}"#.utf8)
        return (try? RunWire.specVersion(wrapped))!
    }

    private func history(_ id: Int64) -> [SpecVersionItem] {
        if let v = versions[id] { return v }
        let v: [SpecVersionItem]
        switch id {
        case 7: v = [item(1, "compose", Self.compose)]
        case 2: v = [item(1, "manual", Self.small), item(2, "compose", Self.full)]
        default: v = [item(1, "manual", Self.full)]
        }
        versions[id] = v
        return v
    }

    private func secretList(_ id: Int64) -> [SecretItem] {
        if let s = stored[id] { return s }
        let day = 86_400.0
        let s: [SecretItem] =
            id == 7
            ? []
            : [
                SecretItem(name: "app_key", version: 1, updatedAt: Date().addingTimeInterval(-3 * day)),
                SecretItem(name: "db_password", version: 1, updatedAt: Date().addingTimeInterval(-3 * day)),
                SecretItem(
                    name: "tls_key", version: 2, updatedAt: Date().addingTimeInterval(-day), kind: "multiline"),
                SecretItem(
                    name: "service_account", version: 1, updatedAt: Date().addingTimeInterval(-2 * day), kind: "file"),
            ] + (id == 3 ? [] : [SecretItem(name: "stripe_secret", version: 1, updatedAt: Date())])
        stored[id] = s
        return s
    }

    func spec(project: Int64) async throws -> SpecVersionItem? { lock.withLock { history(project).last } }

    func specVersion(project: Int64, _ version: Int) async throws -> SpecVersionItem {
        try lock.withLock {
            guard let v = history(project).first(where: { $0.version == version }) else {
                throw RunFailure(sentence: "The Core does not know that.", code: "not_found", status: 404)
            }
            return v
        }
    }

    func saveSpec(project: Int64, json: String, origin: String) async throws -> SpecVersionItem {
        try lock.withLock {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                let data = try? JSONSerialization.data(withJSONObject: obj),
                let text = String(data: data, encoding: .utf8), obj["services"] is [String: Any]
            else { throw RunFailure(sentence: "spec: missing field `services`", code: "invalid_spec", status: 400) }
            var all = history(project)
            let v = item(all.count + 1, origin, text)
            all.append(v)
            versions[project] = all
            return v
        }
    }

    func secrets(project: Int64) async throws -> [SecretItem] { lock.withLock { secretList(project) } }

    func setSecret(project: Int64, name: String, value: String) async throws {
        lock.withLock {
            var s = secretList(project)
            let version = (s.first { $0.name == name }?.version ?? 0) + 1
            s.removeAll { $0.name == name }
            s.append(SecretItem(name: name, version: version, updatedAt: Date()))
            stored[project] = s
        }
    }

    func run(project: Int64) async throws -> RunStatus? {
        project == 3
            ? RunStatus(
                state: "failed",
                error: "api stopped 40 s after start. stripe_secret is not set. Set it, then start again.",
                idleStopAt: nil) : nil
    }

    func touch(project: Int64) async throws {}

    func specVersions(project: Int64) async throws -> [SpecVersionSummary] {
        lock.withLock {
            history(project).reversed().map {
                SpecVersionSummary(
                    version: $0.version, origin: $0.origin,
                    createdAt: Date().addingTimeInterval(-Double($0.version) * 3600))
            }
        }
    }
}
#endif
