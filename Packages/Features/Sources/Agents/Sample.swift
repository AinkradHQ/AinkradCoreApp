#if DEBUG
import CoreKit
import CoreUI
import Foundation

/// A scripted Core for tests and the demo (`CORE_DEMO=1`): the prototype's world (`agents-data.js`) in this module's types.
/// Actions change it the way the Core would and say so on the event feed, so a model driven by it behaves as against a real one.
public final class FakeAgentsAPI: AgentsAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var sessionsByID: [String: AgentSessionInfo] = [:]
    private var order: [String] = []
    private var entries: [String: [TranscriptEntry]] = [:]
    private var feed: AsyncStream<AgentFeed>.Continuation?
    public var runnerList: [RunnerInfo] = []
    public var chainList: [ChainOption] = []
    /// What the next action throws, once.
    public var failNext: (any Error)?
    public private(set) var calls: [String] = []
    private var counter = 100

    public init() {}

    // MARK: scripting

    /// Entries one second apart, the last at `endsAt` (default: when the session was last updated).
    public func add(_ s: AgentSessionInfo, entries list: [EntryKind] = [], endsAt: Date? = nil) {
        lock.withLock {
            sessionsByID[s.id] = s
            order.insert(s.id, at: 0)
            let end = endsAt ?? s.updatedAt
            entries[s.id] = list.enumerated().map {
                TranscriptEntry(seq: Int64($0 + 1), at: end.addingTimeInterval(-Double(list.count - 1 - $0)), kind: $1)
            }
            sessionsByID[s.id]?.lastSeq = Int64(list.count)
        }
    }

    public func append(_ id: String, _ kinds: [EntryKind], at: Date = Date()) {
        lock.withLock {
            var list = entries[id] ?? []
            for k in kinds { list.append(TranscriptEntry(seq: Int64(list.count + 1), at: at, kind: k)) }
            entries[id] = list
            sessionsByID[id]?.lastSeq = Int64(list.count)
        }
    }

    public func update(_ id: String, _ change: (inout AgentSessionInfo) -> Void) {
        lock.withLock {
            if var s = sessionsByID[id] {
                change(&s)
                sessionsByID[id] = s
            }
        }
    }

    public func emit(_ f: AgentFeed) { lock.withLock { feed }?.yield(f) }

    private func record(_ name: String) throws {
        let e: (any Error)? = lock.withLock {
            calls.append(name)
            defer { failNext = nil }
            return failNext
        }
        if let e { throw e }
    }

    // MARK: AgentsAPI

    public func runners() async throws -> [RunnerInfo] { runnerList }
    public func chains() async throws -> [ChainOption] { chainList }
    public var agentList: [String] = []
    public func agents() async throws -> [String] { agentList }
    public var bindingList: [AgentBinding] = []
    public func bindings() async throws -> [AgentBinding] {
        try record("bindings")
        return lock.withLock { bindingList }
    }
    public func bind(agent: String, chain: Int64) async throws {
        try record("bind \(agent) \(chain)")
        lock.withLock {
            bindingList.removeAll { $0.agent == agent }
            bindingList.append(AgentBinding(agent: agent, chain: chain))
            if !agentList.contains(agent) { agentList.append(agent) }
        }
    }
    public func unbind(agent: String) async throws {
        try record("unbind \(agent)")
        lock.withLock {
            bindingList.removeAll { $0.agent == agent }
            agentList.removeAll { $0 == agent }
        }
    }
    public func attempts(run: String) async throws -> [AgentSessionInfo] {
        lock.withLock {
            runAttempts[run] ?? order.compactMap { sessionsByID[$0] }.filter { $0.route?.run == run }
        }
    }
    /// A run's attempts as the demo wants them listed (the walk's stand-in for `?run=`).
    public var runAttempts: [String: [AgentSessionInfo]] = [:]
    public var accountNames: [Int64: String] = [:]
    public func accountName(_ id: Int64) async throws -> String? { accountNames[id] }

    public func sessions(before: Int64?, limit: Int) async throws -> [AgentSessionInfo] {
        try record("sessions")
        return lock.withLock {
            let all = order.compactMap { sessionsByID[$0] }
            let older = before.map { b in all.filter { ($0.index ?? 0) < b } } ?? all
            return Array(older.prefix(limit))
        }
    }

    public func session(_ id: String) async throws -> AgentSessionInfo {
        try record("session")
        guard let s = lock.withLock({ sessionsByID[id] }) else {
            throw CoreError.http(status: 404, code: "not_found", message: "no such session")
        }
        return s
    }

    public func transcript(_ id: String, after: Int64, limit: Int) async throws -> TranscriptPage {
        try record("transcript")
        let all = lock.withLock { entries[id] ?? [] }
        return TranscriptPage(entries: Array(all.filter { $0.seq > after }.prefix(limit)), lastSeq: Int64(all.count))
    }

    public func create(_ new: NewAgentSession) async throws -> AgentSessionInfo {
        try record("create")
        let id: String = lock.withLock {
            counter += 1
            return "as_new\(counter)"
        }
        let s = AgentSessionInfo(
            id: id, runner: new.runner, harness: new.chain == nil && new.agent == nil ? new.harness : "claude",
            state: new.prompt.isEmpty ? .waiting : .starting, createdAt: Date(), updatedAt: Date(),
            index: Int64(counter), project: new.project, branch: new.branch)
        add(
            s,
            entries: [.started(harness: new.harness, resumed: false)] + (new.prompt.isEmpty ? [] : [.user(new.prompt)]))
        return s
    }

    public func send(_ id: String, text: String) async throws -> AgentSessionInfo {
        try record("send")
        append(id, [.user(text)])
        emit(.event(AgentEvent(kind: "agent.transcript", session: id)))
        return try await session(id)
    }

    /// The real Core answers a cancel at once and ends the session later (after the tool call in flight); false does the same.
    public var cancelEndsSession = true

    public func cancel(_ id: String) async throws -> AgentSessionInfo {
        if !cancelEndsSession {
            calls.append("cancel")
            guard let s = lock.withLock({ sessionsByID[id] }) else {
                throw CoreError.http(status: 404, code: "not_found", message: "no such session")
            }
            return s
        }
        return try await finish(id, "cancel", .cancelled, "cancelled")
    }
    public func kill(_ id: String) async throws -> AgentSessionInfo { try await finish(id, "kill", .failed, "failed") }

    private func finish(_ id: String, _ call: String, _ o: SessionOutcome, _ kind: String) async throws
        -> AgentSessionInfo
    {
        try record(call)
        update(id) {
            $0.state = .ended
            $0.outcome = o
            $0.endedAt = Date()
        }
        append(id, [.ended(kind: kind, reason: nil)])
        emit(.event(AgentEvent(kind: "agent.ended", session: id)))
        return try await session(id)
    }

    public func stopTurn(_ id: String) async throws -> AgentSessionInfo {
        try record("stopTurn")
        update(id) { $0.state = .waiting }
        append(id, [.turnEnded(costMicros: nil, tokens: nil)])
        emit(.event(AgentEvent(kind: "agent.turn_ended", session: id)))
        return try await session(id)
    }

    public func end(_ id: String) async throws -> AgentSessionInfo {
        try await finish(id, "end", .succeeded, "succeeded")
    }

    public func rename(_ id: String, title: String) async throws -> AgentSessionInfo {
        try record("rename")
        update(id) { $0.title = title }
        return try await session(id)
    }

    public func resume(_ id: String) async throws -> AgentSessionInfo {
        try record("resume")
        update(id) {
            $0.state = .starting
            $0.outcome = nil
            $0.endedAt = nil
        }
        emit(.event(AgentEvent(kind: "agent.state", session: id)))
        return try await session(id)
    }

    public func wake(_ id: String, key: String, text: String?) async throws {
        try record("wake")
        if let text { append(id, [.user(text)]) }
    }

    public func decide(_ id: String, request: String, approved: Bool) async throws -> AgentSessionInfo {
        try record("decide:\(approved)")
        append(id, [.approvalDecided(id: request, approved: approved)])
        emit(.event(AgentEvent(kind: "agent.approval_decided", session: id, request: request)))
        return try await session(id)
    }

    public var ledgerList: [String: SessionLedger] = [:]
    public func ledger(_ session: String) async throws -> SessionLedger? { ledgerList[session] }

    public func events() -> AsyncStream<AgentFeed> {
        AsyncStream { c in
            lock.withLock { feed = c }
            c.yield(.live)
        }
    }

    // MARK: the prototype's world

    /// The sessions of `agents-data.js`, with transcripts, approvals and four runners.
    public static func prototypeWorld(now: Date = Date()) -> FakeAgentsAPI {
        let api = FakeAgentsAPI()
        api.runnerList = [
            RunnerInfo(
                id: "d_mac", name: "mac-studio", online: true, load: 2, capacity: 4, drivers: ["agent", "process"]),
            RunnerInfo(
                id: "d_lin", name: "linux-01", online: true, load: 2, capacity: 2, drivers: ["agent", "process"]),
            RunnerInfo(id: "d_ora", name: "oracle-arm", online: true, load: 1, capacity: 2, drivers: ["agent"]),
            RunnerInfo(id: "d_old", name: "build-box", online: false, load: 0, capacity: 2, drivers: []),
        ]
        func ago(_ s: Double) -> Date { now.addingTimeInterval(-s) }
        func session(
            _ n: Int, _ h: String, _ r: String, _ st: SessionState, _ o: SessionOutcome? = nil, age: Double, tin: Int64,
            tout: Int64, cost: Int64
        ) -> AgentSessionInfo {
            AgentSessionInfo(
                id: "as_01JC4X7Q3MZ8N5V2K9R\(String(format: "%03d", n))", runner: r, harness: h, state: st, outcome: o,
                createdAt: ago(age), updatedAt: ago(30), endedAt: st == .ended || st == .lost ? ago(30) : nil,
                lastSeq: 0,
                usage: AgentUsageInfo(input: tin, output: tout, costMicros: cost), index: Int64(n))
        }
        let files = [
            "crates/citadel/src/routes.rs", "crates/citadel/src/store.rs", "migrations/0024_citadel.sql", "Cargo.toml",
        ]
        func work(_ n: Int) -> [EntryKind] {
            var out: [EntryKind] = []
            for i in 0..<n {
                let f = files[i % 4]
                switch i % 4 {
                case 0:
                    out += [
                        .assistant("Reading how the module mounts its routes before I change anything."),
                        .toolUse(id: "t\(i)", name: "Read", summary: f),
                        .toolResult(
                            id: "t\(i)", name: "Read", ok: true, exitCode: nil, output: "\(180 + i * 7) lines",
                            durationMs: 120),
                    ]
                case 1:
                    out += [
                        .assistant("The store needs a v24 migration for the approvals table. Adding it now."),
                        .toolUse(id: "t\(i)", name: "Edit", summary: f),
                        .toolResult(
                            id: "t\(i)", name: "Edit", ok: true, exitCode: nil, output: "+\(40 + i * 3) -\(6 + i)",
                            durationMs: 80),
                    ]
                case 2:
                    out += [
                        .assistant("Running the module tests to see where the routes fail."),
                        .toolUse(id: "t\(i)", name: "Bash", summary: "cargo test -p citadel"),
                        .toolResult(
                            id: "t\(i)", name: "Bash", ok: true, exitCode: 0,
                            output:
                                "running \(300 + i * 4) tests\ntest routes::approvals::decide_conflict ... ok\ntest result: ok. \(300 + i * 4) passed; 0 failed",
                            durationMs: 20_700),
                    ]
                default:
                    out += [.assistant("Two handlers still return 500 instead of 409 on a conflict. Fixing them.")]
                }
            }
            return out
        }
        let prompt = EntryKind.user("Bootstrap Citadel on the new Core and open the PR against development.")
        func ask(_ id: String, _ tool: String, _ input: String, secs: Int = 300) -> EntryKind {
            .approvalRequest(id: id, tool: tool, input: input, timeoutSecs: secs)
        }
        func head(_ h: String, _ p: String) -> [EntryKind] { [.started(harness: h, resumed: false), .user(p)] }

        // Waiting on you (three, with 292 s, 130 s and 241 s left).
        let a1 = session(1, "claude", "d_mac", .running, age: 38 * 60, tin: 312_400, tout: 101_300, cost: 3_420_000)
        api.add(
            a1,
            entries: head(
                "claude", "Bootstrap Citadel on the new Core and open the PR against development.\nUse the e2-14 plan.")
                + work(12) + [
                    .toolUse(id: "g0", name: "github.get_issue", summary: "#142"),
                    .toolResult(
                        id: "g0", name: "github.get_issue", ok: true, exitCode: nil, output: "", durationMs: 300),
                    .toolUse(id: "g1", name: "github.create_pull_request", summary: ""),
                    .toolResult(
                        id: "g1", name: "github.create_pull_request", ok: false, exitCode: nil,
                        output: "Personal GitHub may only read.", durationMs: 200),
                    .assistant("Ready to push the branch. That leaves this machine, so I need your approval."),
                    ask("req_push", "Bash", "git push -u origin feat/e2-14-citadel-bootstrap"),
                ], endsAt: ago(8))
        api.ledgerList[a1.id] = SessionLedger(
            costMicros: 3_910_000, tokens: 413_700, unpriced: false, account: "claude-api-metered",
            maxUSDMicros: 5_000_000, maxTokens: 2_000_000)
        let a2 = session(2, "claude", "d_ora", .running, age: 27 * 60, tin: 121_800, tout: 30_200, cost: 870_000)
        api.add(
            a2,
            entries: head("claude", "Read the plan comments on the PR and fix every blocking one") + work(4) + [
                .assistant("I need the GitHub token to read the plan comments on the PR."),
                ask("req_token", "Secrets", "read GH_TOKEN, once", secs: 300),
            ], endsAt: ago(170))
        let a11 = session(3, "codex", "d_lin", .running, age: 12 * 60, tin: 64_200, tout: 18_900, cost: 410_000)
        api.add(
            a11,
            entries: head("codex", "Add the heartbeat exporter to the runner and wire its metrics") + work(3) + [
                .assistant("The heartbeat exporter needs one crate that is not in the lockfile yet."),
                ask("req_crate", "Bash", "cargo add prometheus-client"),
            ], endsAt: ago(59))
        // Not waiting.
        api.add(
            session(4, "claude", "d_mac", .starting, age: 4, tin: 0, tout: 0, cost: 0),
            entries: [.started(harness: "claude", resumed: false), prompt])
        api.add(
            session(5, "codex", "d_lin", .interrupted, age: 19 * 60, tin: 88_700, tout: 22_100, cost: 520_000),
            entries: head("codex", "Run the runner soak test until it passes") + work(3) + [
                .toolUse(id: "tz", name: "Bash", summary: "cargo test -p runner soak"),
                .toolResult(id: "tz", name: "Bash", ok: false, exitCode: 1, output: "1 failed", durationMs: 61_000),
                .interrupted(reason: "the runner restarted"),
            ])
        api.add(
            session(6, "codex", "d_lin", .ended, .succeeded, age: 55 * 60, tin: 402_100, tout: 97_800, cost: 1_210_000),
            entries: head("codex", "Wire notifications through the push policy") + work(8) + [
                .assistant("Notifications are wired through the push policy and the PR is open."),
                .ended(kind: "succeeded", reason: nil),
            ])
        api.add(
            session(7, "claude", "d_ora", .ended, .stalled, age: 72 * 60, tin: 233_900, tout: 41_200, cost: 1_640_000),
            entries: head("claude", "Find out why the nightly build stalls after the cache step") + work(5) + [
                .ended(kind: "stalled", reason: "no progress for a long while")
            ])
        api.add(
            session(8, "codex", "d_lin", .ended, .tokenCap, age: 123 * 60, tin: 480_000, tout: 20_000, cost: 2_300_000),
            entries: head(
                "codex",
                "Migrate the audit log to the new schema, keeping every row, and write the rollback so it can be run twice without losing anything"
            ) + work(5) + [.ended(kind: "token_cap", reason: nil)])
        api.add(
            session(9, "claude", "d_mac", .ended, .failed, age: 180 * 60, tin: 144_600, tout: 38_400, cost: 960_000),
            entries: head("claude", "Fix the failing policy tests") + work(5) + [
                .toolUse(id: "tf", name: "Bash", summary: "cargo test -p policy"),
                .toolResult(
                    id: "tf", name: "Bash", ok: false, exitCode: 101,
                    output:
                        "test policy::push::deny_unknown_branch ... FAILED\ntest result: FAILED. 18 passed; 3 failed",
                    durationMs: 12_400), .ended(kind: "failed", reason: "The AI session exited with an error."),
            ])
        api.add(
            session(10, "claude", "d_mac", .ended, .cancelled, age: 300 * 60, tin: 40_100, tout: 9_000, cost: 210_000),
            entries: head("claude", "アカウントの予算が尽きた理由を調べて、上限の引き上げ案をまとめてください") + work(2) + [
                .ended(kind: "cancelled", reason: nil)
            ])
        api.add(
            session(11, "claude", "d_ora", .lost, age: 360 * 60, tin: 77_000, tout: 15_100, cost: 480_000),
            entries: head("claude", "Dry-run the migration on a copy of the Home Core") + work(4) + [
                .toolUse(id: "tl", name: "Bash", summary: "ainkrad migrate --dry-run")
            ]
        )
        return api
    }
}
#endif
