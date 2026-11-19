import CoreKit
import Foundation

// Run configurations and environments (Core 0.10, E11-3): the Core's `/projects/{id}/run-configs`, `/run-envs` and `/runs`
// routes. Calls are gated by `serverSupports(minor: 95)` in `ProjectsModel`. Security model: no route returns a secret's
// value, and a plain variable's value comes only from `reveal`, on request; nothing here keeps one longer than the view that
// asked.

struct RunConfigItem: Equatable, Identifiable, Sendable {
    let id: Int64
    var name: String
    var command: String
    var workdir: String
    /// `automatic`, or a runner's id.
    var runner: String
    var port: Int?
    var restart: Bool
}

/// A change to a configuration: only the fields that are set are sent.
struct RunConfigPatch: Equatable, Sendable {
    var name: String?
    var command: String?
    var workdir: String?
    var runner: String?
    /// 0 clears the port.
    var port: Int?
    var restart: Bool?

    var json: [String: Any] {
        var o: [String: Any] = [:]
        if let name { o["name"] = name }
        if let command { o["command"] = command }
        if let workdir { o["workdir"] = workdir }
        if let runner { o["runner"] = runner }
        if let port { o["port"] = port }
        if let restart { o["restart"] = restart }
        return o
    }
}

/// A variable as the Core lists it: its name and where its value comes from, never the value.
struct RunVarItem: Equatable, Identifiable, Sendable {
    let key: String
    /// The project secret it comes from; nil for a plain value.
    let secret: String?
    /// A plain value's length, for the dots.
    let size: Int
    var id: String { key }
}

struct EnvDiffItem: Equatable, Identifiable, Sendable {
    enum Change: String, Sendable { case same, different, onlyA = "only_a", onlyB = "only_b" }
    let key: String
    let change: Change
    var id: String { key }
}

struct RunRecord: Equatable, Identifiable, Sendable {
    let id: String
    /// `starting`, `running`, `stopping`, `stopped` or `failed`.
    let state: String
    let configID: Int64?
    let environment: String?
    let runner: String
    let startedAt: Date?
    let stoppedAt: Date?
    let stopReason: String?
    let error: String?

    var live: Bool { ["starting", "running", "stopping"].contains(state) }
}

struct EnvImport: Equatable, Sendable {
    let imported: Int
    let skipped: Int
}

protocol RunConfigsService: Sendable {
    func configs(project: Int64) async throws -> [RunConfigItem]
    func createConfig(project: Int64, name: String, command: String) async throws -> RunConfigItem
    func updateConfig(project: Int64, id: Int64, _ patch: RunConfigPatch) async throws -> RunConfigItem
    func deleteConfig(project: Int64, id: Int64) async throws
    func duplicateConfig(project: Int64, id: Int64) async throws -> RunConfigItem
    /// Starts it in `environment` (admin, step-up). `replace` stops the project's live run first.
    func start(project: Int64, config: Int64, environment: String?, replace: Bool) async throws -> RunRecord
    func environments(project: Int64) async throws -> [String]
    func addEnvironment(project: Int64, name: String) async throws -> [String]
    func deleteEnvironment(project: Int64, name: String) async throws -> [String]
    func vars(project: Int64, config: Int64, env: String) async throws -> [RunVarItem]
    /// A plain `value`, or a project `secret` to link: exactly one.
    func setVar(project: Int64, config: Int64, env: String, key: String, value: String?, secret: String?) async throws
    func deleteVar(project: Int64, config: Int64, env: String, key: String) async throws
    func reveal(project: Int64, config: Int64, env: String, key: String) async throws -> String
    func importEnv(project: Int64, config: Int64, env: String, text: String) async throws -> EnvImport
    func diff(project: Int64, config: Int64, a: String, b: String) async throws -> [EnvDiffItem]
    func history(project: Int64) async throws -> [RunRecord]
    /// The Core's paired runners, for a configuration's Runner field: `(id, name)`.
    func runners() async throws -> [RunnerOption]
}

struct RunnerOption: Equatable, Sendable {
    let id: String
    let name: String
}

struct LiveRunConfigsService: RunConfigsService {
    let connection: CoreConnection

    func configs(project: Int64) async throws -> [RunConfigItem] {
        try RunConfigsWire.configs(try await call("GET", "\(Self.base(project))/run-configs"))
    }

    func createConfig(project: Int64, name: String, command: String) async throws -> RunConfigItem {
        let body = try JSONSerialization.data(withJSONObject: ["name": name, "command": command])
        return try RunConfigsWire.config(try await call("POST", "\(Self.base(project))/run-configs", body))
    }

    func updateConfig(project: Int64, id: Int64, _ patch: RunConfigPatch) async throws -> RunConfigItem {
        let body = try JSONSerialization.data(withJSONObject: patch.json)
        return try RunConfigsWire.config(try await call("PATCH", "\(Self.base(project))/run-configs/\(id)", body))
    }

    func deleteConfig(project: Int64, id: Int64) async throws {
        _ = try await call("DELETE", "\(Self.base(project))/run-configs/\(id)")
    }

    func duplicateConfig(project: Int64, id: Int64) async throws -> RunConfigItem {
        try RunConfigsWire.config(try await call("POST", "\(Self.base(project))/run-configs/\(id)/duplicate"))
    }

    func start(project: Int64, config: Int64, environment: String?, replace: Bool) async throws -> RunRecord {
        var o: [String: Any] = ["replace": replace]
        if let environment { o["environment"] = environment }
        let body = try JSONSerialization.data(withJSONObject: o)
        return try RunConfigsWire.run(
            try await call("POST", "\(Self.base(project))/run-configs/\(config)/run", body))
    }

    func environments(project: Int64) async throws -> [String] {
        try RunConfigsWire.envs(try await call("GET", "\(Self.base(project))/run-envs"))
    }

    func addEnvironment(project: Int64, name: String) async throws -> [String] {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        return try RunConfigsWire.envs(try await call("POST", "\(Self.base(project))/run-envs", body))
    }

    func deleteEnvironment(project: Int64, name: String) async throws -> [String] {
        try RunConfigsWire.envs(
            try await call("DELETE", "\(Self.base(project))/run-envs/\(LiveProjectRunService.seg(name))"))
    }

    func vars(project: Int64, config: Int64, env: String) async throws -> [RunVarItem] {
        try RunConfigsWire.vars(try await call("GET", Self.envPath(project, config, env)))
    }

    func setVar(project: Int64, config: Int64, env: String, key: String, value: String?, secret: String?) async throws
    {
        var o: [String: Any] = [:]
        if let value { o["value"] = value }
        if let secret { o["secret"] = secret }
        let body = try JSONSerialization.data(withJSONObject: o)
        _ = try await call("PUT", "\(Self.envPath(project, config, env))/\(LiveProjectRunService.seg(key))", body)
    }

    func deleteVar(project: Int64, config: Int64, env: String, key: String) async throws {
        _ = try await call("DELETE", "\(Self.envPath(project, config, env))/\(LiveProjectRunService.seg(key))")
    }

    func reveal(project: Int64, config: Int64, env: String, key: String) async throws -> String {
        let data = try await call(
            "GET", "\(Self.envPath(project, config, env))/\(LiveProjectRunService.seg(key))/value")
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let v = o["value"] as? String
        else { throw RunWire.bad }
        return v
    }

    func importEnv(project: Int64, config: Int64, env: String, text: String) async throws -> EnvImport {
        let body = try JSONSerialization.data(withJSONObject: ["text": text])
        return try RunConfigsWire.imported(
            try await call("POST", "\(Self.envPath(project, config, env))/import", body))
    }

    func diff(project: Int64, config: Int64, a: String, b: String) async throws -> [EnvDiffItem] {
        let q = "a=\(LiveProjectRunService.seg(a))&b=\(LiveProjectRunService.seg(b))"
        return try RunConfigsWire.diff(
            try await call("GET", "\(Self.base(project))/run-configs/\(config)/env-diff?\(q)"))
    }

    func history(project: Int64) async throws -> [RunRecord] {
        try RunConfigsWire.runs(try await call("GET", "\(Self.base(project))/runs?limit=30"))
    }

    func runners() async throws -> [RunnerOption] {
        try RunConfigsWire.runners(try await call("GET", "/api/v1/runners"))
    }

    private static func base(_ id: Int64) -> String { "/api/v1/projects/\(id)" }
    private static func envPath(_ p: Int64, _ c: Int64, _ env: String) -> String {
        "\(base(p))/run-configs/\(c)/env/\(LiveProjectRunService.seg(env))"
    }

    private func call(_ method: String, _ path: String, _ body: Data = Data()) async throws -> Data {
        do {
            return try await connection.signedRequest(method: method, target: path, body: body)
        } catch CoreError.http(let status, let code, let message) {
            throw LiveProjectRunService.failure(status: status, code: code, message: message)
        } catch CoreError.badRequest(let message) {
            throw LiveProjectRunService.failure(status: 400, code: "bad_request", message: message)
        }
    }
}

/// The JSON the routes answer, read by hand like `RunWire`.
enum RunConfigsWire {
    static func configs(_ data: Data) throws -> [RunConfigItem] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw RunWire.bad }
        return try list.map(item)
    }

    static func config(_ data: Data) throws -> RunConfigItem {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RunWire.bad }
        return try item(o)
    }

    private static func item(_ o: [String: Any]) throws -> RunConfigItem {
        guard let id = (o["id"] as? NSNumber)?.int64Value, let name = o["name"] as? String,
            let command = o["command"] as? String
        else { throw RunWire.bad }
        return RunConfigItem(
            id: id, name: name, command: command, workdir: o["workdir"] as? String ?? "",
            runner: o["runner"] as? String ?? "automatic", port: (o["port"] as? NSNumber)?.intValue,
            restart: o["restart"] as? Bool ?? false)
    }

    static func envs(_ data: Data) throws -> [String] {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = o["environments"] as? [String]
        else { throw RunWire.bad }
        return list
    }

    static func vars(_ data: Data) throws -> [RunVarItem] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw RunWire.bad }
        return try list.map {
            guard let key = $0["key"] as? String else { throw RunWire.bad }
            return RunVarItem(
                key: key, secret: $0["secret"] as? String, size: ($0["size"] as? NSNumber)?.intValue ?? 0)
        }
    }

    static func imported(_ data: Data) throws -> EnvImport {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let n = (o["imported"] as? NSNumber)?.intValue
        else { throw RunWire.bad }
        return EnvImport(imported: n, skipped: (o["skipped"] as? [Any])?.count ?? 0)
    }

    static func diff(_ data: Data) throws -> [EnvDiffItem] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw RunWire.bad }
        return try list.map {
            guard let key = $0["key"] as? String, let c = ($0["change"] as? String).flatMap(EnvDiffItem.Change.init)
            else { throw RunWire.bad }
            return EnvDiffItem(key: key, change: c)
        }
    }

    /// A list of runners, bare or under `runners`.
    static func runners(_ data: Data) throws -> [RunnerOption] {
        let json = try? JSONSerialization.jsonObject(with: data)
        guard let list = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["runners"] as? [[String: Any]])
        else { throw RunWire.bad }
        return list.compactMap {
            guard let id = $0["id"] as? String else { return nil }
            return RunnerOption(id: id, name: $0["name"] as? String ?? id)
        }
    }

    static func run(_ data: Data) throws -> RunRecord {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RunWire.bad }
        return try record(o)
    }

    static func runs(_ data: Data) throws -> [RunRecord] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw RunWire.bad }
        return try list.map(record)
    }

    private static func record(_ o: [String: Any]) throws -> RunRecord {
        guard let id = o["id"] as? String, let state = o["state"] as? String else { throw RunWire.bad }
        return RunRecord(
            id: id, state: state, configID: (o["config_id"] as? NSNumber)?.int64Value,
            environment: o["environment"] as? String, runner: o["runner"] as? String ?? "",
            startedAt: RunWire.date(o["started_at"] as? String), stoppedAt: RunWire.date(o["stopped_at"] as? String),
            stopReason: o["stop_reason"] as? String, error: o["error"] as? String)
    }
}
