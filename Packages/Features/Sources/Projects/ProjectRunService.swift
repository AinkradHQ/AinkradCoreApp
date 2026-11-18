import CoreKit
import Foundation

// The Run page's side of the Core: a project's run spec (AinkradCore #306), its secrets (#316) and its run (#318). The live
// service calls the routes through `CoreConnection.signedRequest`, the way Leyline and Design do. Security model: a secret's
// value goes in (`setSecret`) and never comes back; no type here carries one except the argument of that one call, and no
// route this file calls returns one.

/// One service of a run spec, as the table shows it.
struct SpecService: Equatable, Sendable {
    let name: String
    /// The image, or "build <repo>" for a service built from a repo.
    let image: String
    /// The first port, "3000", and whether it has a public URL.
    let port: Int?
    let isPublic: Bool
    /// The secret names its `env` refers to.
    let secrets: [String]
}

/// One saved version of the spec. `json` is the spec itself, pretty printed with sorted keys, so two versions diff by line.
struct SpecVersionItem: Equatable, Sendable {
    let version: Int
    /// `manual`, `compose`, `package_json`, `makefile` or `run_sh`.
    let origin: String
    let createdAt: Date?
    let json: String
    let services: [SpecService]

    var drafted: Bool { origin != "manual" }
    /// "docker-compose.yml": what a converter read, for the draft line.
    var source: String {
        switch origin {
        case "compose": "docker-compose.yml"
        case "package_json": "package.json"
        case "makefile": "Makefile"
        case "run_sh": "run.sh"
        default: "the setup"
        }
    }
    /// Every secret the spec refers to, once.
    var secretNames: [String] {
        var seen = Set<String>()
        return services.flatMap(\.secrets).filter { seen.insert($0).inserted }.sorted()
    }
}

/// A stored secret: its name and when it last changed, never its value.
struct SecretItem: Equatable, Sendable {
    let name: String
    let version: Int
    let updatedAt: Date?
}

/// What the Core says of the project's run (the live one, else the newest).
struct RunStatus: Equatable, Sendable {
    /// `starting`, `running`, `stopping`, `stopped` or `failed`.
    let state: String
    let error: String?
    let idleStopAt: Date?
}

/// A failure the Run page can word.
struct RunFailure: Error, Equatable, Sendable {
    let sentence: String
    let code: String
    var status = 0
}

protocol ProjectRunService: Sendable {
    /// The newest spec version; nil when the project has none yet.
    func spec(project: Int64) async throws -> SpecVersionItem?
    func specVersion(project: Int64, _ version: Int) async throws -> SpecVersionItem
    /// Saves `json` as the next version (admin, step-up). `origin` is `manual` for a person's edit or an undo.
    func saveSpec(project: Int64, json: String, origin: String) async throws -> SpecVersionItem
    func secrets(project: Int64) async throws -> [SecretItem]
    /// Stores or replaces a secret (admin, step-up). The value is written, never read back.
    func setSecret(project: Int64, name: String, value: String) async throws
    /// The project's run; nil when it never ran.
    func run(project: Int64) async throws -> RunStatus?
    /// Says a viewer is on the Run page, so the idle stop moves back.
    func touch(project: Int64) async throws
}

struct LiveProjectRunService: ProjectRunService {
    let connection: CoreConnection

    func spec(project: Int64) async throws -> SpecVersionItem? {
        do {
            return try RunWire.specVersion(try await call("GET", "\(Self.base(project))/spec"))
        } catch let f as RunFailure where f.status == 404 { return nil }
    }

    func specVersion(project: Int64, _ version: Int) async throws -> SpecVersionItem {
        try RunWire.specVersion(try await call("GET", "\(Self.base(project))/spec/versions/\(version)"))
    }

    func saveSpec(project: Int64, json: String, origin: String) async throws -> SpecVersionItem {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)), object is [String: Any] else {
            throw RunFailure(sentence: "That is not valid JSON. Check the braces and quotes.", code: "bad_json")
        }
        let body = try JSONSerialization.data(withJSONObject: ["spec": object, "origin": origin])
        return try RunWire.specVersion(try await call("PUT", "\(Self.base(project))/spec", body))
    }

    func secrets(project: Int64) async throws -> [SecretItem] {
        do {
            return try RunWire.secrets(try await call("GET", "\(Self.base(project))/secrets"))
        } catch let f as RunFailure where f.status == 404 || f.status == 501 { return [] }
    }

    func setSecret(project: Int64, name: String, value: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["value": value, "kind": "text"])
        _ = try await call("PUT", "\(Self.base(project))/secrets/\(Self.seg(name))", body)
    }

    func run(project: Int64) async throws -> RunStatus? {
        do {
            return try RunWire.run(try await call("GET", "\(Self.base(project))/run"))
        } catch let f as RunFailure where f.status == 404 || f.status == 501 { return nil }
    }

    func touch(project: Int64) async throws { _ = try await call("POST", "\(Self.base(project))/run/activity") }

    private static func base(_ id: Int64) -> String { "/api/v1/projects/\(id)" }

    private func call(_ method: String, _ path: String, _ body: Data = Data()) async throws -> Data {
        do {
            return try await connection.signedRequest(method: method, target: path, body: body)
        } catch CoreError.http(let status, let code, let message) {
            throw Self.failure(status: status, code: code, message: message)
        } catch CoreError.badRequest(let message) {
            throw Self.failure(status: 400, code: "bad_request", message: message)
        }
    }

    /// One path segment, escaped so a name can never add a slash or a query.
    static func seg(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#")))
            ?? s
    }

    /// The Core's own sentence when it gave one (a bad spec names its field), else words from the code or the status.
    static func failure(status: Int, code: String, message: String) -> RunFailure {
        let sentence: String
        switch code {
        case "secrets_disabled": sentence = "Secrets are turned off on this Core."
        case "limit_reached": sentence = "This project has reached its limit of secrets."
        case "secrets_unavailable": sentence = "The Core's secret store is not available right now. Try again soon."
        case "real_secret_refused": sentence = "That looks like a real credential. Projects run on test data only."
        default:
            if !message.isEmpty {
                sentence = message
            } else if status == 404 {
                sentence = "The Core does not know that."
            } else {
                sentence = "The Core refused that."
            }
        }
        return RunFailure(sentence: sentence, code: code, status: status)
    }
}

/// The JSON the three routes answer, read by hand: a spec's keys are environment names and services, which a key strategy
/// would rewrite.
enum RunWire {
    static let bad = RunFailure(sentence: "The Core answered something this app does not know.", code: "bad_answer")

    static func specVersion(_ data: Data) throws -> SpecVersionItem {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = o["version"] as? Int, let origin = o["origin"] as? String,
            let spec = o["spec"] as? [String: Any],
            let pretty = try? JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted, .sortedKeys])
        else { throw bad }
        return SpecVersionItem(
            version: version, origin: origin, createdAt: date(o["created_at"] as? String),
            json: String(decoding: pretty, as: UTF8.self), services: services(spec))
    }

    static func services(_ spec: [String: Any]) -> [SpecService] {
        let all = spec["services"] as? [String: [String: Any]] ?? [:]
        return all.keys.sorted().map { name in
            let s = all[name] ?? [:]
            let ports = (s["ports"] as? [[String: Any]]) ?? []
            let first = ports.first
            let build = (s["build"] as? [String: Any])?["repo"] as? String
            let env = (s["env"] as? [String: String]) ?? [:]
            return SpecService(
                name: name, image: (s["image"] as? String) ?? build.map { "build \($0)" } ?? "–",
                port: first?["port"] as? Int, isPublic: ports.contains { ($0["expose"] as? Bool) == true },
                secrets: Array(Set(env.values.flatMap(secretRefs))).sorted())
        }
    }

    /// The names in `${secret:NAME}` references of one value.
    static func secretRefs(_ value: String) -> [String] {
        var out: [String] = []
        var rest = Substring(value)
        while let open = rest.range(of: "${secret:") {
            rest = rest[open.upperBound...]
            guard let close = rest.firstIndex(of: "}") else { break }
            out.append(String(rest[..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return out
    }

    static func secrets(_ data: Data) throws -> [SecretItem] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw bad }
        return try list.map {
            guard let name = $0["name"] as? String else { throw bad }
            return SecretItem(
                name: name, version: $0["version"] as? Int ?? 1, updatedAt: date($0["updated_at"] as? String))
        }
    }

    static func run(_ data: Data) throws -> RunStatus {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let state = o["state"] as? String
        else { throw bad }
        return RunStatus(
            state: state, error: o["error"] as? String, idleStopAt: date(o["idle_stop_at"] as? String))
    }

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// A secret name as the Core takes it (`[a-z][a-z0-9_.-]{0,63}`), checked here first.
enum SecretRules {
    static func nameProblem(_ name: String) -> String? {
        if name.isEmpty { return "Give the secret a name." }
        guard let first = name.first, first.isASCII, first.isLowercase, first.isLetter else {
            return "The name has to start with a lowercase letter."
        }
        if name.count > 64 { return "The name can be at most 64 characters." }
        if name.contains(where: { !($0.isASCII && ($0.isLowercase || $0.isNumber || "_.-".contains($0))) }) {
            return "Use lowercase letters, digits, dots, dashes and underscores in the name."
        }
        return nil
    }
}

/// The lines that differ between two spec versions, for "See Changes": `+` added, `-` removed, in file order.
enum SpecDiff {
    struct Line: Equatable, Sendable {
        let added: Bool
        let text: String
    }

    static func lines(from old: String?, to new: String) -> [Line] {
        let n = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let old else { return n.map { Line(added: true, text: $0) } }
        let o = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [Line] = []
        for change in n.difference(from: o).inferringMoves() {
            switch change {
            case .insert(_, let text, _): out.append(Line(added: true, text: text))
            case .remove(_, let text, _): out.append(Line(added: false, text: text))
            }
        }
        return out
    }
}
