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
    /// `text`, `multiline`, `file` or `env_bundle`.
    var kind = "text"
    var description = ""
    var lastUsedAt: Date? = nil
    var useCount = 0
}

/// What a secret is stored as: its kind decides how the value is read. For `file` the value is the file's base64.
struct SecretInput: Equatable, Sendable {
    var value: String
    var kind = "text"
    var description = ""
    var fileName: String?
}

/// One saved version without its spec (`GET /spec/versions`).
struct SpecVersionSummary: Equatable, Identifiable, Sendable {
    let version: Int
    let origin: String
    let createdAt: Date?
    var id: Int { version }
}

/// What the Core says of the project's run (the live one, else the newest).
struct RunStatus: Equatable, Sendable {
    /// `starting`, `running`, `stopping`, `stopped` or `failed`.
    let state: String
    let error: String?
    let idleStopAt: Date?
    var stopReason: String? = nil
    var lastActivityAt: Date? = nil
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
    /// The live run's services (state, health, CPU, memory, restarts); none while the project is not running.
    func services(project: Int64) async throws -> [ProjectLive.Service]
    /// Log lines of the live run after `after` (0 for the oldest held), and the `seq` to ask with next.
    func logs(project: Int64, after: Int) async throws -> RunLogPage
    /// CPU and memory history per service of the live run (API 110); empty when there is none.
    func metrics(project: Int64) async throws -> [String: ServiceSeries]
    /// Drafts the setup from a file in the project's primary repo (compose, run.sh, Makefile or package.json), saved as the
    /// next version (admin, step-up). `image` is what a Makefile or script runs in; a Makefile cannot be drafted without one.
    func draft(project: Int64, image: String?) async throws -> SpecVersionItem
    /// Every saved version, newest first, without the spec.
    func specVersions(project: Int64) async throws -> [SpecVersionSummary]
    /// Stores a secret of any kind (admin, step-up); `setSecret(project:name:value:)` is the text one.
    func setSecret(project: Int64, name: String, _ input: SecretInput) async throws
    /// Deletes a secret (admin, step-up). The Core refuses with `conflict` while a spec version still uses it, unless `force`.
    func deleteSecret(project: Int64, name: String, force: Bool) async throws
}

/// The last readings of one service (API 110, `GET /run/metrics`): oldest first, at most 60, one a minute or so.
struct ServiceSeries: Equatable, Sendable {
    /// Percent of one CPU; 0 where the service was not running.
    var cpu: [Double] = []
    /// Bytes.
    var memory: [Double] = []
}

/// A page of run log lines.
struct RunLogPage: Equatable, Sendable {
    var lines: [ProjectLive.LogLine] = []
    var next = 0
    /// Lines the runner had dropped before the first one here (a flood, or a slow reader).
    var lost = 0
}

extension ProjectRunService {
    func services(project: Int64) async throws -> [ProjectLive.Service] { [] }
    func metrics(project: Int64) async throws -> [String: ServiceSeries] { [:] }
    func logs(project: Int64, after: Int) async throws -> RunLogPage { RunLogPage(next: after) }
    func draft(project: Int64, image: String?) async throws -> SpecVersionItem {
        throw RunFailure(sentence: "This Core cannot draft a setup.", code: "unsupported")
    }
    func specVersions(project: Int64) async throws -> [SpecVersionSummary] { [] }
    func setSecret(project: Int64, name: String, _ input: SecretInput) async throws {
        try await setSecret(project: project, name: name, value: input.value)
    }
    func deleteSecret(project: Int64, name: String, force: Bool) async throws {
        throw RunFailure(sentence: "This Core cannot delete a secret.", code: "unsupported")
    }
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
        try await setSecret(project: project, name: name, SecretInput(value: value))
    }

    func setSecret(project: Int64, name: String, _ input: SecretInput) async throws {
        let body = try JSONSerialization.data(withJSONObject: RunWire.secretBody(input))
        _ = try await call("PUT", "\(Self.base(project))/secrets/\(Self.seg(name))", body)
    }

    func deleteSecret(project: Int64, name: String, force: Bool) async throws {
        _ = try await call("DELETE", "\(Self.base(project))/secrets/\(Self.seg(name))\(force ? "?force=true" : "")")
    }

    func specVersions(project: Int64) async throws -> [SpecVersionSummary] {
        try RunWire.versions(try await call("GET", "\(Self.base(project))/spec/versions"))
    }

    func run(project: Int64) async throws -> RunStatus? {
        do {
            return try RunWire.run(try await call("GET", "\(Self.base(project))/run"))
        } catch let f as RunFailure where f.status == 404 || f.status == 501 { return nil }
    }

    func touch(project: Int64) async throws { _ = try await call("POST", "\(Self.base(project))/run/activity") }

    func draft(project: Int64, image: String?) async throws -> SpecVersionItem {
        let body = try JSONSerialization.data(withJSONObject: image.map { ["image": $0] } ?? [:])
        let data = try await call("POST", "\(Self.base(project))/run/spec/draft", body)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let v = o["version"] else {
            throw RunWire.bad
        }
        return try RunWire.specVersion(try JSONSerialization.data(withJSONObject: v))
    }

    func services(project: Int64) async throws -> [ProjectLive.Service] {
        do {
            return try RunWire.services(try await call("GET", "\(Self.base(project))/run/services"))
        } catch let f as RunFailure where f.status == 404 || f.status == 501 { return [] }
    }

    func metrics(project: Int64) async throws -> [String: ServiceSeries] {
        do {
            return try RunWire.metrics(try await call("GET", "\(Self.base(project))/run/metrics"))
        } catch let f as RunFailure where f.status == 404 || f.status == 501 { return [:] }
    }

    func logs(project: Int64, after: Int) async throws -> RunLogPage {
        do {
            return try RunWire.logs(
                try await call("GET", "\(Self.base(project))/run/logs?after=\(after)"), after: after)
        } catch let f as RunFailure where f.status == 404 || f.status == 501 { return RunLogPage(next: after) }
    }

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
            // A value may be a number or a flag in the file; it is kept as its text, never dropped.
            let env = (s["env"] as? [String: Any] ?? [:]).mapValues { Self.text($0) }
            return SpecService(
                name: name, image: (s["image"] as? String) ?? build.map { "build \($0)" } ?? "–",
                port: first?["port"] as? Int, isPublic: ports.contains { ($0["expose"] as? Bool) == true },
                secrets: Array(Set(env.values.flatMap(secretRefs))).sorted())
        }
    }

    /// An env value as text: a string as it is, a number or a flag as it would be written.
    static func text(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
        }
        return String(describing: v)
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
                name: name, version: $0["version"] as? Int ?? 1, updatedAt: date($0["updated_at"] as? String),
                kind: $0["kind"] as? String ?? "text", description: $0["description"] as? String ?? "",
                lastUsedAt: date($0["last_used_at"] as? String), useCount: ($0["use_count"] as? NSNumber)?.intValue ?? 0
            )
        }
    }

    /// The body of `PUT /secrets/{name}`: the value, its kind, and what only some kinds take.
    static func secretBody(_ i: SecretInput) -> [String: Any] {
        var o: [String: Any] = ["value": i.value, "kind": i.kind]
        if !i.description.isEmpty { o["description"] = i.description }
        if i.kind == "file", let n = i.fileName { o["file_name"] = n }
        return o
    }

    static func versions(_ data: Data) throws -> [SpecVersionSummary] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw bad }
        return try list.map {
            guard let v = $0["version"] as? Int, let origin = $0["origin"] as? String else { throw bad }
            return SpecVersionSummary(version: v, origin: origin, createdAt: date($0["created_at"] as? String))
        }
    }

    static func run(_ data: Data) throws -> RunStatus {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let state = o["state"] as? String
        else { throw bad }
        return RunStatus(
            state: state, error: o["error"] as? String, idleStopAt: date(o["idle_stop_at"] as? String),
            stopReason: o["stop_reason"] as? String, lastActivityAt: date(o["last_activity_at"] as? String))
    }

    /// The Core's service rows: Podman's `state` read as up (running), exited (it stopped on its own) or down (anything else),
    /// `cpu_percent` rounded, `memory_bytes` as a size, `health` and `restarts` as they are.
    static func services(_ data: Data) throws -> [ProjectLive.Service] {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = o["services"] as? [[String: Any]]
        else { throw bad }
        return try list.map {
            guard let name = $0["name"] as? String else { throw bad }
            let bytes = ($0["memory_bytes"] as? NSNumber)?.int64Value ?? 0
            return ProjectLive.Service(
                name: name, memory: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory),
                state: state(($0["state"] as? String) ?? ""),
                cpu: ($0["cpu_percent"] as? Double).map { Int($0.rounded()) },
                restarts: ($0["restarts"] as? NSNumber)?.intValue ?? 0, health: ($0["health"] as? String) ?? "none")
        }
    }

    /// `GET /run/metrics`: per service the CPU and memory samples, oldest first.
    static func metrics(_ data: Data) throws -> [String: ServiceSeries] {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = o["services"] as? [[String: Any]]
        else { throw bad }
        var out: [String: ServiceSeries] = [:]
        for s in list {
            guard let name = s["name"] as? String else { throw bad }
            let samples = s["samples"] as? [[String: Any]] ?? []
            out[name] = ServiceSeries(
                cpu: samples.map { ($0["cpu_percent"] as? NSNumber)?.doubleValue ?? 0 },
                memory: samples.map { ($0["memory_bytes"] as? NSNumber)?.doubleValue ?? 0 })
        }
        return out
    }

    static func state(_ podman: String) -> ProjectLive.Service.State {
        switch podman {
        case "running": .up
        case "exited", "dead": .exited
        default: .down
        }
    }

    static func logs(_ data: Data, after: Int) throws -> RunLogPage {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let lines = o["lines"] as? [[String: Any]]
        else { throw bad }
        return RunLogPage(
            lines: lines.compactMap {
                guard let s = $0["service"] as? String, let t = $0["text"] as? String else { return nil }
                return ProjectLive.LogLine(
                    service: s, text: t, seq: ($0["seq"] as? NSNumber)?.intValue ?? 0, at: date($0["at"] as? String))
            }, next: (o["next"] as? NSNumber)?.intValue ?? after, lost: (o["lost"] as? NSNumber)?.intValue ?? 0)
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

/// The lines that differ between two spec versions, for "See Changes": added (`+`) and removed (`-`) lines in file order, each
/// change with a few unchanged lines around it for context, and `…` where a stretch of unchanged lines was left out.
enum SpecDiff {
    enum Kind: Hashable, Sendable { case added, removed, context, gap }
    struct Line: Hashable, Sendable {
        let kind: Kind
        let text: String
        var added: Bool { kind == .added }
        init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }
        init(added: Bool, text: String) { self.init(kind: added ? .added : .removed, text: text) }
    }

    /// Unchanged lines kept on each side of a change.
    static let context = 3

    static func lines(from old: String?, to new: String) -> [Line] {
        let n = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let old else { return n.map { Line(kind: .added, text: $0) } }
        let o = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in n.difference(from: o) {
            switch change {
            case .insert(let at, _, _): inserted.insert(at)
            case .remove(let at, _, _): removed.insert(at)
            }
        }
        if removed.isEmpty && inserted.isEmpty { return [] }
        // Walk both files together: a removed old line, an inserted new line, else a line both have.
        var all: [Line] = []
        var i = 0
        var j = 0
        while i < o.count || j < n.count {
            if i < o.count, removed.contains(i) {
                all.append(Line(kind: .removed, text: o[i]))
                i += 1
            } else if j < n.count, inserted.contains(j) {
                all.append(Line(kind: .added, text: n[j]))
                j += 1
            } else {
                if j < n.count { all.append(Line(kind: .context, text: n[j])) }
                i += 1
                j += 1
            }
        }
        // Keep the changes and `context` lines around each; the rest becomes one gap line.
        var keep = [Bool](repeating: false, count: all.count)
        for (k, l) in all.enumerated() where l.kind != .context {
            for m in max(0, k - context)...min(all.count - 1, k + context) { keep[m] = true }
        }
        var out: [Line] = []
        var skipped = false
        for (k, l) in all.enumerated() {
            if keep[k] {
                out.append(l)
                skipped = false
            } else if !skipped {
                out.append(Line(kind: .gap, text: "…"))
                skipped = true
            }
        }
        return out
    }
}
