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
    /// The same with names and a second line, for the guided Add's list (Core minor 95 and later; older Cores say only the
    /// ones already chosen).
    func picks(_ id: Int64) async throws -> ConnPicks
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

extension ConnectionsService {
    func picks(_ id: Int64) async throws -> ConnPicks {
        ConnPicks(items: try await resources(id).map { ConnPick(id: $0, name: $0) })
    }
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
    /// The picker's list can't be read (tests, the error scene).
    var failPicks = false
    let now = Date()

    init(empty: Bool = false) {
        let n = Date()
        list =
            empty
            ? []
            : [
                ConnItem(
                    id: 1, kind: "github", name: "Personal GitHub", identity: "@maple-fox", status: .connected,
                    isDefault: true, allowed: ["read_repo"], only: nil, lastUsed: n.addingTimeInterval(-720), users: 4),
                ConnItem(
                    id: 2, kind: "github", name: "Sample org", identity: "@maple-studio · organisation",
                    status: .needsLook, reason: "GitHub says this sign-in expired.", isDefault: false,
                    allowed: ["read_repo"], only: nil, lastChecked: n.addingTimeInterval(-3600), users: 3,
                    signInNeeded: true),
                ConnItem(
                    id: 3, kind: "jira", name: "Sample Jira", identity: "maple@example.test",
                    status: .connected, isDefault: true, allowed: ["read_issues"], only: nil,
                    lastUsed: n.addingTimeInterval(-10800), users: 4),
            ]
    }

    func kinds() async throws -> [ConnKind] { Self.kinds }
    /// The five services of the mockup, with its made-up wording.
    static let kinds: [ConnKind] = [
        kind(
            "github", "GitHub", "Code, pull requests and issues", .deviceCode, "repositories", "repos",
            [
                (
                    "read_repo", "Read code, pull requests and issues",
                    "See what is in your projects. Nothing changes.", false
                ),
                ("pr_write", "Comment on pull requests", "Leave notes for you and your team.", true),
                ("push", "Open pull requests and push branches", "Make changes in your repositories.", true),
            ]),
        kind(
            "jira", "Jira", "Tickets and boards", .browser, "projects", "projects",
            [
                ("read_issues", "Read tickets and boards", "See your tickets. Nothing changes.", false),
                ("write_issues", "Comment on tickets", "Leave notes on a ticket.", true),
                ("transition", "Create and move tickets", "Add tickets and change their status.", true),
            ]),
        kind(
            "linear", "Linear", "Issues and cycles", .browser, "teams", "teams",
            [
                ("read_issues", "Read issues and cycles", "See your issues. Nothing changes.", false),
                ("write_issues", "Create and update issues", "Add issues and change their status.", true),
            ]),
        kind(
            "slack", "Slack", "Messages and channels", .browser, "channels", "channels",
            [
                (
                    "read_messages", "Read messages in channels you pick", "See the conversation. Nothing is sent.",
                    false
                ),
                ("post_messages", "Post new messages", "Write in the channels you pick.", true),
            ]),
        kind(
            "teams", "Microsoft Teams", "Chats and channels", .deviceCode, "channels", "channels",
            [
                (
                    "read_messages", "Read messages in channels you pick", "See the conversation. Nothing is sent.",
                    false
                ),
                ("post_messages", "Post new messages", "Write in the channels you pick.", true),
            ]),
    ]

    private static func kind(
        _ id: String, _ name: String, _ say: String, _ signIn: ConnKind.SignIn, _ resource: String, _ key: String,
        _ caps: [(String, String, String, Bool)]
    ) -> ConnKind {
        let help: [String: [String]] = [
            "github": [
                "On github.com, open Settings, then Developer settings, then Personal access tokens.",
                "Make a fine-grained token for the repositories you want.", "Copy it and paste it below.",
            ],
            "jira": [
                "Open id.atlassian.com, then Security, then API tokens.",
                "Create a token with a name you will recognise.", "Copy it and paste it below.",
            ],
        ]
        return ConnKind(
            id: id, name: name, say: say, signIn: signIn, resource: resource,
            capabilities: caps.map { ConnCapability(id: $0.0, title: $0.1, say: $0.2, writes: $0.3) },
            tokenTitle: help[id] == nil ? "" : "Use a token", tokenHelp: help[id] ?? [],
            tokenFields: id == "jira" ? ["Site", "Your Atlassian email"] : [], limitKey: key)
    }

    /// The pick lists of the mockup, by kind: an id and the line the mockup shows.
    static let pickLists: [String: [(String, String)]] = [
        "github": [
            ("maple/harbor-web", "Updated today"), ("maple/notes-app", "Updated yesterday"),
            ("maple/release-tools", "3 days ago"), ("maple/photo-sorter", "Last week"),
            ("maple/garden-planner", "Last month"), ("maple/recipe-box", "Last month"),
        ],
        "jira": [("HAR", "Harbor"), ("GRD", "Garden"), ("KIT", "Kitchen"), ("PLN", "Planning")],
        "linear": [("PRO", "Product"), ("DES", "Design"), ("SUP", "Support")],
        "slack": [("C01", "#general"), ("C02", "#build"), ("C03", "#ideas"), ("C04", "#launch")],
        "teams": [("t1/g", "General"), ("t1/b", "Build team"), ("t1/p", "Planning")],
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
                id: 3, connection: 3, who: "claude · fix-login", what: "Read SHOP-142", ok: true, result: "Done",
                at: now.addingTimeInterval(-360)),
            .init(
                id: 4, connection: 2, who: "Core", what: "Checked the sign-in", ok: false, result: "Expired",
                at: now.addingTimeInterval(-3600)),
            .init(
                id: 5, connection: 3, who: "codex · triage", what: "Moved SHOP-140 to In Review", ok: true,
                result: "Done", at: now.addingTimeInterval(-10800)),
            .init(
                id: 6, connection: 1, who: "You", what: "Connected", ok: true, result: "Done",
                at: now.addingTimeInterval(-90000)),
        ]
        return rows.filter { connection == nil || $0.connection == connection }
    }

    func resources(_ id: Int64) async throws -> [String] {
        let kind = lock.withLock { list.first { $0.id == id }?.kind } ?? "github"
        return (Self.pickLists[kind] ?? []).map(\.0)
    }

    /// Made-up lists, the second line as the mockup words it. Sample only.
    func picks(_ id: Int64) async throws -> ConnPicks {
        if failPicks { throw CoreError.http(status: 502, code: "upstream_failed", message: "") }
        let kind = lock.withLock { list.first { $0.id == id }?.kind } ?? "github"
        let days: [String: Double] = [
            "Updated today": 0, "Updated yesterday": 1, "3 days ago": 3, "Last week": 8, "Last month": 40,
        ]
        return ConnPicks(
            items: (Self.pickLists[kind] ?? []).map { r in
                kind == "github"
                    ? ConnPick(id: r.0, name: r.0, updatedAt: Date().addingTimeInterval(-86_400 * (days[r.1] ?? 40)))
                    : ConnPick(id: r.0, name: r.1, detail: r.0)
            })
    }

    func start(kind: String, again: Int64?) async throws -> ConnFlow {
        let f = ConnFlow(
            id: UUID().uuidString, kind: kind, userCode: kind == "github" || kind == "teams" ? "WDJB-MJHT" : nil,
            url: URL(string: kind == "github" ? "https://github.com/login/device" : "https://auth.example.test")!,
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
                            fix: "The service may still be open in your browser. Press Accept there, or try again.")
                } else if f.kind == "jira" {
                    f.step = .pickSite(["sample.atlassian.net", "other.atlassian.net"])
                } else {
                    add(&f, site: nil)
                }
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
        let title = Self.kinds.first { $0.id == f.kind }?.name ?? f.kind
        let who = ["github": "@maple-fox", "slack": "Maple Studio workspace"]
        list.append(
            ConnItem(
                id: nextID, kind: f.kind, name: "\(title) (\(nextID))",
                identity: site ?? who[f.kind] ?? "maple@example.test", status: .connected,
                isDefault: !list.contains { $0.kind == f.kind }, allowed: [], only: nil, users: 1))
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
                id: nextID, kind: kind, name: name, identity: fields["Site"] ?? "@maple-fox", status: .connected,
                isDefault: !list.contains { $0.kind == kind }, allowed: [], only: nil, users: 1, authMethod: "token")
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
            $0.signInNeeded = true
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
            $0.signInNeeded = false
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
