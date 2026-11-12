#if DEBUG
import Foundation

/// Debug only: the Brain M3 mockup's world (brain-m3.html), invented. Rooms, candidates, policies and runners.
struct SampleM3: Sendable {
    var items: [InboxCandidate]
    var policies: [String: RoomPolicy]
    var runners: [RunnerHistory]
    let queued: [QueuedRoom]

    static let model = "Qwen3 14B on MacBook Air"

    static var rooms: [RoomSummary] {
        func room(_ id: String, _ name: String, _ kind: RoomKind, _ p: ProviderClass, _ n: Int, _ by: [TypeShare])
            -> RoomSummary
        {
            RoomSummary(
                id: id, name: name, kind: kind, mode: .synced, provider: p, mounted: true,
                lease: Lease(left: "19 h", fraction: 0.8), counts: RoomCounts(records: n, byType: by))
        }
        let cc = TypeShare("Claude Code", 842)
        return [
            room("core", "AinkradCore", .product, .approvedCloud, 1412, [cc, .init("Codex", 301), .init("Docs", 269)]),
            room(
                "app", "AinkradCoreApp", .product, .approvedCloud, 688, [.init("Claude Code", 512), .init("Docs", 176)]),
            room("workan-space", "workan-space", .product, .local, 204, [.init("Claude Code", 204)]),
            room("personal", "Personal notes", .personal, .local, 1032, [.init("Vault", 1032)]),
        ]
    }

    static let sources: [SourceWire] = {
        let mac: [(String, Int, Bool)] = [
            ("claude_code", 1210, true), ("codex", 640, true), ("opencode", 90, true), ("doc", 700, true),
            ("vault", 345, true), ("agents_md", 0, true), ("cursor", 0, false), ("chat", 0, false),
            ("antigravity", 0, false),
        ]
        let hour = "2026-11-12T10:00:00Z"
        var out = [SourceWire(id: "core_transcript", device: "core", kind: "core_transcript", enabled: false)]
        for (kind, n, on) in mac {
            out.append(
                SourceWire(id: "mac_\(kind)", device: "MacBook Air", kind: kind, enabled: on, lastRun: hour, items: n))
        }
        out.append(
            SourceWire(
                id: "jira", device: "core", kind: "jira", roots: ["KAN", "AUT", "OPT"], lastRun: "2026-11-12T11:00:00Z",
                items: 1204))
        out.append(
            SourceWire(
                id: "github", device: "core", kind: "github", enabled: false, roots: ["14 repositories"], items: 0))
        return out
    }()

    /// One candidate of the mockup's list.
    private static func cand(
        _ id: String, _ room: String, _ name: String, _ k: CandidateKind, _ text: String, _ app: String, _ date: String,
        _ src: [CandidateSource]
    ) -> InboxCandidate {
        InboxCandidate(
            id: id, room: room, roomName: name, kind: k, text: text, app: app, date: date, distilled: "today, 14:02",
            account: "Claude, Max account", sources: src)
    }

    private static func src(_ id: String, _ title: String, _ place: String, _ quote: String) -> CandidateSource {
        CandidateSource(id: id, title: title, place: place, quote: quote)
    }

    private static var mockupItems: [InboxCandidate] {
        let core = "AinkradCore"
        let app = "AinkradCoreApp"
        return [
            cand(
                "c1", "core", core, .decision,
                "Run the queue migration before the runner rewrite, so the old queue drains first.", "Claude Code",
                "11 Nov",
                [
                    src(
                        "s1", "Claude Code session", "AinkradCore · 11 Nov, 14:20",
                        "…agreed to run the migration before the runner rewrite, not after, so the old queue drains first…"
                    ),
                    src(
                        "s2", "2026-11-10-queue-plan.md", "Docs/Plans · 10 Nov",
                        "Step 2 is the queue migration, step 3 the runner rewrite. Do not swap them."),
                ]),
            cand(
                "c2", "core", core, .landmine,
                "The first migration on the jobs table takes a write lock for about a minute.",
                "Codex", "9 Nov",
                [
                    src(
                        "s3", "Codex session", "AinkradCore · 9 Nov, 09:41",
                        "…it locks writes on jobs while it backfills, so run it while no AI session is working…")
                ]),
            cand(
                "c3", "core", core, .fact, "Core stores everything encrypted with one brain key.", "Docs", "6 Nov",
                [
                    src(
                        "s4", "brain-security.md", "Docs/Specs · 6 Nov",
                        "All room files and staging files use the one brain key.")
                ]),
            cand(
                "c4", "core", core, .openThread, "Which providers may read the Brain rooms is not decided.",
                "Claude Code", "5 Nov",
                [
                    src(
                        "s5", "Claude Code session", "AinkradCore · 5 Nov, 17:02",
                        "…we still have to decide which providers may read the rooms…")
                ]),
            cand(
                "c5", "app", app, .decision, "The Mac app stays in native full screen with no windowed mode.",
                "Claude Code", "4 Nov",
                [
                    src(
                        "s6", "Claude Code session", "AinkradCoreApp · 4 Nov, 11:15",
                        "…full screen only, no resize, no exit…")
                ]),
            cand(
                "c6", "workan-space", "workan-space", .fact,
                "Tenant dashboards read from the API, never from the database.",
                "Claude Code", "2 Nov",
                [
                    src(
                        "s7", "Claude Code session", "workan-space · 2 Nov, 15:30",
                        "…the dashboard only talks to the API…")
                ]),
            cand(
                "c7", "app", app, .openThread, "Should Antigravity history be read through its export?", "Cursor",
                "1 Nov",
                [src("s8", "Cursor chat", "AinkradCoreApp · 1 Nov, 10:08", "…not sure the export keeps tool calls…")]),
        ]
    }

    private static func policy(_ s: SampleBrainService.Scenario, local: Bool, auto: Bool = false) -> RoomPolicy {
        var p = RoomPolicy()
        p.model = local ? .localOnly : .cloud
        p.accounts = ["Claude Max, personal"]
        p.account = "Claude Max, personal"
        p.localModels = s.noLocalModel ? [] : [model]
        p.localModel = s.noLocalModel ? nil : model
        p.autoAccept = auto
        p.kinds = auto ? [.fact, .openThread] : []
        return p
    }

    private static func runnerList() -> [RunnerHistory] {
        func tools(_ a: Int?, _ b: Int?, _ c: Int?, on: Bool = false) -> [RunnerTool] {
            [("claude_code", "Claude Code", a), ("codex", "Codex", b), ("opencode", "OpenCode", c)].map {
                RunnerTool(id: $0.0, name: $0.1, found: $0.2, on: on && $0.2 != nil)
            }
        }
        return [
            RunnerHistory(
                id: "air", name: "MacBook Air", enabled: true, tools: tools(300, 80, 12, on: true), items: 148,
                lastRun: "1 hour ago"),
            RunnerHistory(id: "vps-1", name: "vps-1 (Azure)", tools: tools(412, 87, nil)),
            RunnerHistory(id: "studio", name: "Mac Studio", online: false, tools: tools(nil, nil, nil)),
        ]
    }

    init(_ s: SampleBrainService.Scenario) {
        items = s.m3 ? Self.mockupItems : []
        queued =
            s.m3 && s.noLocalModel
            ? [
                QueuedRoom(room: "personal", name: "Personal notes", items: 14),
                QueuedRoom(room: "workan-space", name: "workan-space", items: 9),
            ]
            : []
        policies =
            s.m3
            ? [
                "core": Self.policy(s, local: false), "app": Self.policy(s, local: false),
                "workan-space": Self.policy(s, local: true, auto: !s.noLocalModel),
                "personal": Self.policy(s, local: true),
            ] : [:]
        for q in queued { policies[q.room]?.queued = q.items }
        runners = s.m3 ? Self.runnerList() : []
    }
}

extension SampleBrainService {
    public nonisolated var servesCandidates: Bool { true }

    public func candidates() async throws -> CandidateInbox {
        if scenario.error {
            throw BrainFailure("Core did not answer. Nothing was changed.", code: "sample_unreachable")
        }
        return CandidateInbox(items: m3.items, queued: m3.queued)
    }

    public func decide(_ id: String, room: String, _ decision: CandidateDecision) async throws {
        guard m3.items.contains(where: { $0.id == id }) else {
            throw BrainFailure("That candidate was decided already.", code: "already_decided")
        }
        m3.items.removeAll { $0.id == id }
    }

    public func policy(room: String) async throws -> RoomPolicy { m3.policies[room] ?? RoomPolicy() }

    public func setPolicy(room: String, _ change: PolicyChange) async throws -> RoomPolicy {
        var p = m3.policies[room] ?? RoomPolicy()
        if let m = change.model { p.model = m }
        if let a = change.autoAccept { p.autoAccept = a }
        if let k = change.kinds { p.kinds = k }
        if let n = change.minSources { p.minSources = n }
        if let l = change.localModel { p.localModel = l }
        if p.model == .cloud { p.queued = 0 }
        m3.policies[room] = p
        return p
    }

    public func runners() async throws -> [RunnerHistory] { m3.runners }

    public func setRunnerHistory(_ id: String, enabled: Bool, tools: [String]) async throws -> RunnerHistory {
        guard let i = m3.runners.firstIndex(where: { $0.id == id }) else {
            throw BrainFailure("That runner is gone.", code: "not_found")
        }
        m3.runners[i].enabled = enabled
        for j in m3.runners[i].tools.indices {
            let t = m3.runners[i].tools[j]
            m3.runners[i].tools[j].on = enabled && tools.contains(t.id)
        }
        return m3.runners[i]
    }
}
#endif
