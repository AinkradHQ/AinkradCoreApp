import Foundation

/// The Core's connection routes (C5) as these screens use them. A credential only ever goes in on the Core's side: nothing
/// here returns one. Until C5 lands the app has no live service: Debug builds use `SampleConnections`, Release says
/// the Core doesn't serve connections yet.
protocol ConnectionsService: Sendable {
    func kinds() async throws -> [ConnKind]
    func connections() async throws -> [ConnItem]
    func activity(connection: Int64?) async throws -> [ConnActivity]
    /// The repositories or projects a connection can reach, for the "Only these" picker.
    func resources(_ id: Int64) async throws -> [String]
    func start(kind: String) async throws -> ConnFlow
    func flow(_ id: String) async throws -> ConnFlow
    /// GitHub: done choosing repositories (or skipped). Jira: the site picked.
    func choose(_ id: String, site: String?) async throws -> ConnFlow
    /// The Atlassian redirect the Mac caught on its loopback address (CN7).
    func deliver(_ id: String, code: String, state: String) async throws -> ConnFlow
    func cancel(_ id: String) async throws
    /// Advanced: a token pasted by the person, sent once and never read back.
    func addToken(kind: String, name: String, fields: [String: String], token: String) async throws -> ConnItem
    /// One cheap call with the sign-in: a sentence, never a body.
    func test(_ id: Int64) async throws -> String
    func rename(_ id: Int64, to name: String) async throws
    func setDefault(_ id: Int64) async throws
    func setAccess(_ id: Int64, allowed: Set<String>, only: [String]?) async throws
    func delete(_ id: Int64) async throws
}

#if DEBUG
/// Stand-in data for Debug builds, screenshots and tests, labelled as such on screen. Made-up names, no credentials.
final class SampleConnections: ConnectionsService, @unchecked Sendable {
    // ponytail: one lock around plain vars; this is sample data, not a store.
    private let lock = NSLock()
    private var list: [ConnItem]
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

    func start(kind: String) async throws -> ConnFlow {
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
                        ? .chooseResources(login: "@sample-dev")
                        : .pickSite(["sample.atlassian.net", "other.atlassian.net"])
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
            nextID += 1
            let gh = f.kind == "github"
            list.append(
                ConnItem(
                    id: nextID, kind: f.kind, name: gh ? "GitHub (\(nextID))" : "Jira (\(nextID))",
                    identity: gh ? "@sample-dev" : (site ?? "sample.atlassian.net"), status: .connected,
                    isDefault: !list.contains { $0.kind == f.kind }, allowed: ["read"], only: nil, users: 1))
            f.step = .connected(nextID)
            flows[id] = (f, n)
            return f
        }
    }

    func deliver(_ id: String, code: String, state: String) async throws -> ConnFlow { try await flow(id) }
    func cancel(_ id: String) async throws { _ = lock.withLock { flows.removeValue(forKey: id) } }

    func addToken(kind: String, name: String, fields: [String: String], token: String) async throws -> ConnItem {
        lock.withLock {
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
    private func edit(_ id: Int64, _ f: (inout ConnItem) -> Void) {
        lock.withLock { if let i = list.firstIndex(where: { $0.id == id }) { f(&list[i]) } }
    }
}
#endif
