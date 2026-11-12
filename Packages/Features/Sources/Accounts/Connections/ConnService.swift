import CoreKit
import Foundation

/// The Core's connection routes (C5) as these screens use them. A credential only ever goes in on the Core's side: nothing
/// here returns one. `LiveConnectionsService` is the real one; `SampleConnections` is Debug only, for screenshots and tests.
protocol ConnectionsService: Sendable {
    func kinds() async throws -> [ConnKind]
    func connections() async throws -> [ConnItem]
    func activity(connection: Int64?) async throws -> [ConnActivity]
    /// The repositories or projects a connection can reach, for the "Only these" picker.
    func resources(_ id: Int64) async throws -> [String]
    /// `again`: sign in again to that connection instead of making a new one.
    func start(kind: String, again: Int64?) async throws -> ConnFlow
    func flow(_ id: String) async throws -> ConnFlow
    /// GitHub: done choosing repositories (or skipped). Jira: the site picked.
    func choose(_ id: String, site: String?) async throws -> ConnFlow
    /// The Atlassian redirect the Mac caught on its loopback address (CN7).
    func deliver(_ id: String, code: String, state: String) async throws -> ConnFlow
    func cancel(_ id: String) async throws
    /// GitHub: the app was installed on GitHub (the Mac caught its setup redirect), so the chosen repositories are reachable.
    func install(kind: String, installation: Int64) async throws -> ConnItem
    /// Advanced: a token pasted by the person, sent once and never read back.
    func addToken(kind: String, name: String, fields: [String: String], token: String) async throws -> ConnItem
    /// One cheap call with the sign-in: a sentence, never a body.
    func test(_ id: Int64) async throws -> String
    func rename(_ id: Int64, to name: String) async throws
    func setDefault(_ id: Int64) async throws
    func setAccess(_ id: Int64, allowed: Set<String>, only: [String]?) async throws
    func delete(_ id: Int64) async throws
    /// Each kind's default connection, by kind. Admin only.
    func defaults() async throws -> [String: Int64]
    func clearDefault(kind: String) async throws
    /// Ainkrad's OAuth app registration for a kind. Admin only; a secret is never returned.
    func app(kind: String) async throws -> ConnApp
    /// Only the fields given change. A secret goes in once and is never read back.
    func setApp(kind: String, fields: [String: String]) async throws -> ConnApp
    /// A new token for an existing connection, sent once and never read back.
    func replaceCredential(_ id: Int64, token: String, fields: [String: String]) async throws
    /// One Core setting (server scope). "Turn on connections" reads `secrets.mode`, then sets it and `secrets.connections`.
    func coreSetting(_ key: String) async throws -> Int64
    func setCoreSetting(_ key: String, _ value: Int64) async throws
}

#if DEBUG
/// Stand-in data for Debug builds, screenshots and tests, labelled as such on screen. Made-up names, no credentials.
final class SampleConnections: ConnectionsService, @unchecked Sendable {
    // ponytail: one lock around plain vars; this is sample data, not a store.
    private let lock = NSLock()
    private var list: [ConnItem]
    private var appFields: [String: [String: String]] = ["github": ["client_id": "Iv1.sample1234"]]
    /// App registration: the next read says "admins only" / the next save fails (tests).
    var appReadOnly = false
    var failApp = false
    /// The next replaced token is refused.
    var failReplace = false
    /// Every token and secret sent in, for tests to check it arrived. Sample only.
    private(set) var sent: [String] = []
    private var flows: [String: (ConnFlow, Int)] = [:]
    private var nextID: Int64 = 10
    /// The next sign-in fails (the error scene).
    var failNext = false
    let now = Date()

    init(empty: Bool = false) {
        let n = Date()
        list =
            empty
            ? []
            : [
                ConnItem(
                    id: 1, kind: "github", name: "Personal GitHub", identity: "@sample-dev", status: .connected,
                    isDefault: true, allowed: ["read"], only: nil, lastUsed: n.addingTimeInterval(-720), users: 4),
                ConnItem(
                    id: 2, kind: "github", name: "Sample org", identity: "@sample-org · organisation",
                    status: .needsLook, reason: "GitHub says this sign-in expired.", isDefault: false,
                    allowed: ["read"], only: nil, lastChecked: n.addingTimeInterval(-3600), users: 3),
                ConnItem(
                    id: 3, kind: "jira", name: "Sample Jira", identity: "sample.atlassian.net",
                    status: .connected, isDefault: true, allowed: ["read"], only: nil,
                    lastUsed: n.addingTimeInterval(-10800), users: 4),
            ]
    }

    func kinds() async throws -> [ConnKind] { Self.kinds }
    static let kinds: [ConnKind] = [
        ConnKind(
            id: "github", name: "GitHub", say: "Issues, pull requests and code", signIn: .deviceCode,
            resource: "repositories",
            capabilities: [
                ConnCapability(
                    id: "read", title: "Read code and issues", say: "Look at repositories, issues and pull requests.",
                    writes: false),
                ConnCapability(
                    id: "write", title: "Create and change things",
                    say: "Open issues and pull requests, comment, add labels.", writes: true),
                ConnCapability(
                    id: "push", title: "Push code", say: "Send commits to branches. Never to protected branches.",
                    writes: true),
            ],
            tokenTitle: "Use a personal access token",
            tokenHelp: [
                "On github.com, open Settings → Developer settings → Personal access tokens.",
                "Make a fine-grained token for the repositories you want.", "Copy it and paste it below.",
            ], tokenFields: []),
        ConnKind(
            id: "jira", name: "Jira", say: "Issues and boards on your Atlassian sites", signIn: .browser,
            resource: "projects",
            capabilities: [
                ConnCapability(
                    id: "read", title: "Read issues", say: "Look at issues, boards and comments.", writes: false),
                ConnCapability(
                    id: "write", title: "Create and change issues", say: "Create issues, comment, edit fields.",
                    writes: true),
                ConnCapability(id: "transition", title: "Move issues", say: "Change an issue's status.", writes: true),
            ],
            tokenTitle: "Use an API token",
            tokenHelp: [
                "Open id.atlassian.com → Security → API tokens.", "Create a token with a name you will recognise.",
                "Copy it and paste it below.",
            ], tokenFields: ["Site", "Your Atlassian email"]),
        ConnKind(
            id: "linear", name: "Linear", say: "Issues and projects", signIn: .browser, resource: "teams",
            capabilities: [], tokenTitle: "", tokenHelp: [], tokenFields: [], available: false),
        ConnKind(
            id: "slack", name: "Slack", say: "Messages and channels", signIn: .browser, resource: "channels",
            capabilities: [], tokenTitle: "", tokenHelp: [], tokenFields: [], available: false),
    ]

    func connections() async throws -> [ConnItem] { lock.withLock { list } }

    func activity(connection: Int64?) async throws -> [ConnActivity] {
        let rows: [ConnActivity] = [
            .init(
                id: 1, connection: 1, who: "claude · fix-login", what: "Read issue #142", ok: true, result: "Done",
                at: now.addingTimeInterval(-120)),
            .init(
                id: 2, connection: 1, who: "claude · fix-login", what: "Open a pull request", ok: false,
                result: "Not allowed", at: now.addingTimeInterval(-240)),
            .init(
                id: 3, connection: 3, who: "claude · fix-login", what: "Read KAN-142", ok: true, result: "Done",
                at: now.addingTimeInterval(-360)),
            .init(
                id: 4, connection: 2, who: "Core", what: "Checked the sign-in", ok: false, result: "Expired",
                at: now.addingTimeInterval(-3600)),
            .init(
                id: 5, connection: 3, who: "codex · triage", what: "Moved KAN-140 to In Review", ok: true,
                result: "Done", at: now.addingTimeInterval(-10800)),
            .init(
                id: 6, connection: 1, who: "You", what: "Connected", ok: true, result: "Done",
                at: now.addingTimeInterval(-90000)),
        ]
        return rows.filter { connection == nil || $0.connection == connection }
    }

    func resources(_ id: Int64) async throws -> [String] {
        lock.withLock { list.first { $0.id == id }?.kind } == "jira"
            ? ["KAN", "OPS", "WEB"]
            : ["sample/core", "sample/app", "sample/site", "sample/docs", "sample/infra", "sample/tap"]
    }

    func start(kind: String, again: Int64?) async throws -> ConnFlow {
        let f = ConnFlow(
            id: UUID().uuidString, kind: kind, userCode: kind == "github" ? "WDJB-MJHT" : nil,
            url: URL(string: kind == "github" ? "https://github.com/login/device" : "https://auth.atlassian.com")!,
            step: .waiting)
        lock.withLock { flows[f.id] = (f, 0) }
        return f
    }

    /// Each read moves the sign-in along a little, so the sheet's live steps can be watched.
    func flow(_ id: String) async throws -> ConnFlow {
        try lock.withLock {
            guard var (f, n) = flows[id] else { throw URLError(.badURL) }
            n += 1
            if n == 3, case .waiting = f.step {
                if failNext {
                    failNext = false
                    f.step =
                        f.kind == "github"
                        ? .failed(
                            title: "The code ran out before you approved it.",
                            fix: "Codes work for 15 minutes. Try again for a new code, then approve it on github.com.")
                        : .failed(
                            title: "The browser didn't come back in time.",
                            fix: "Atlassian may still be open in your browser. Press Accept there, or try again.")
                } else {
                    f.step =
                        f.kind == "github"
                        ? .chooseResources(
                            login: "@sample-dev",
                            install: URL(string: "https://github.com/apps/ainkradhq/installations/new")!)
                        : .pickSite(["sample.atlassian.net", "other.atlassian.net"])
                }
            } else if n >= 5, case .chooseResources = f.step {
                add(&f, site: nil)  // the person picked repositories on GitHub
            }
            flows[id] = (f, n)
            return f
        }
    }

    func choose(_ id: String, site: String?) async throws -> ConnFlow {
        try lock.withLock {
            guard let (old, n) = flows[id] else { throw URLError(.badURL) }
            var f = old
            add(&f, site: site)
            flows[id] = (f, n)
            return f
        }
    }

    /// Called under the lock: the new connection, and the flow marked done.
    private func add(_ f: inout ConnFlow, site: String?) {
        nextID += 1
        let gh = f.kind == "github"
        list.append(
            ConnItem(
                id: nextID, kind: f.kind, name: gh ? "GitHub (\(nextID))" : "Jira (\(nextID))",
                identity: gh ? "@sample-dev" : (site ?? "sample.atlassian.net"), status: .connected,
                isDefault: !list.contains { $0.kind == f.kind }, allowed: ["read"], only: nil, users: 1))
        f.step = .connected(nextID)
    }

    func deliver(_ id: String, code: String, state: String) async throws -> ConnFlow { try await flow(id) }
    func cancel(_ id: String) async throws { _ = lock.withLock { flows.removeValue(forKey: id) } }

    func install(kind: String, installation: Int64) async throws -> ConnItem {
        try await addToken(kind: kind, name: "GitHub App", fields: [:], token: "")
    }

    /// Connections are off on this stand-in Core until its settings are set (tests); `failSetting` refuses the write.
    var gated = false
    var failSetting: (any Error)?
    private var settings: [String: Int64] = ["secrets.mode": 0, "secrets.connections": 0]
    /// Every setting written and every credential write, in order. Sample only.
    private(set) var order: [String] = []
    private func gate(_ what: String) throws {
        try lock.withLock {
            if gated, settings["secrets.connections"] != 1 || (settings["secrets.mode"] ?? 0) < 1 {
                order.append("\(what) refused")
                throw CoreError.http(status: 409, code: "real_secret_refused", message: "")
            }
            order.append(what)
        }
    }
    func coreSetting(_ key: String) async throws -> Int64 { lock.withLock { settings[key] ?? 0 } }
    func setCoreSetting(_ key: String, _ value: Int64) async throws {
        if let failSetting { throw failSetting }
        lock.withLock {
            settings[key] = value
            order.append("\(key)=\(value)")
        }
    }

    func addToken(kind: String, name: String, fields: [String: String], token: String) async throws -> ConnItem {
        try gate("addToken")
        return lock.withLock {
            nextID += 1
            let c = ConnItem(
                id: nextID, kind: kind, name: name, identity: fields["Site"] ?? "@sample-dev", status: .connected,
                isDefault: !list.contains { $0.kind == kind }, allowed: ["read"], only: nil, users: 1)
            list.append(c)
            return c
        }
    }

    func test(_ id: Int64) async throws -> String {
        lock.withLock { list.first { $0.id == id }?.status } == .needsLook
            ? "GitHub refused the sign-in. Sign in again." : "Works. GitHub answered in 180 ms."
    }

    func rename(_ id: Int64, to name: String) async throws { edit(id) { $0.name = name } }
    func setDefault(_ id: Int64) async throws {
        lock.withLock {
            guard let kind = list.first(where: { $0.id == id })?.kind else { return }
            for i in list.indices where list[i].kind == kind { list[i].isDefault = list[i].id == id }
        }
    }
    func setAccess(_ id: Int64, allowed: Set<String>, only: [String]?) async throws {
        edit(id) {
            $0.allowed = allowed
            $0.only = only
        }
    }
    /// A sign-in GitHub stopped taking (the health scene and tests).
    func expire(_ id: Int64) {
        edit(id) {
            $0.status = .needsLook
            $0.reason = "GitHub says this sign-in expired."
        }
    }
    func delete(_ id: Int64) async throws { lock.withLock { list.removeAll { $0.id == id } } }

    func defaults() async throws -> [String: Int64] {
        lock.withLock { Dictionary(list.filter(\.isDefault).map { ($0.kind, $0.id) }, uniquingKeysWith: { a, _ in a }) }
    }
    func clearDefault(kind: String) async throws {
        lock.withLock { for i in list.indices where list[i].kind == kind { list[i].isDefault = false } }
    }

    func app(kind: String) async throws -> ConnApp {
        if appReadOnly { throw CoreError.forbiddenScope }
        return lock.withLock { Self.app(kind, appFields[kind] ?? [:]) }
    }
    func setApp(kind: String, fields: [String: String]) async throws -> ConnApp {
        if failApp { throw CoreError.http(status: 500, code: "internal_error", message: "") }
        return lock.withLock {
            sent += fields.values
            appFields[kind, default: [:]].merge(fields) { _, new in new }
            return Self.app(kind, appFields[kind] ?? [:])
        }
    }
    func replaceCredential(_ id: Int64, token: String, fields: [String: String]) async throws {
        try gate("replace")
        if failReplace {
            failReplace = false
            throw CoreError.http(status: 400, code: "bad_request", message: "")
        }
        lock.withLock { sent.append(token) }
        edit(id) {
            $0.status = .connected
            $0.reason = nil
        }
    }
    private static func app(_ kind: String, _ set: [String: String]) -> ConnApp {
        let rows: [(String, String, Bool)] =
            kind == "jira"
            ? [("client_id", "Client ID", false), ("client_secret", "Client secret", true)]
            : [("client_id", "Client ID", false), ("app_id", "App ID", false), ("app_key", "App private key", true)]
        return ConnApp(
            kind: kind, configured: set["client_id"] != nil,
            fields: rows.map { r in
                ConnApp.Field(id: r.0, title: r.1, secret: r.2, isSet: set[r.0] != nil, value: r.2 ? nil : set[r.0])
            }, redirect: kind == "jira" ? "http://127.0.0.1:47613/callback" : nil)
    }
    private func edit(_ id: Int64, _ f: (inout ConnItem) -> Void) {
        lock.withLock { if let i = list.firstIndex(where: { $0.id == id }) { f(&list[i]) } }
    }
}
#endif
