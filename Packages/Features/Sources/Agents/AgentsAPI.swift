import CoreKit
import Foundation

/// What the Core says moved, reduced to what the agent stores act on.
public struct AgentEvent: Equatable, Sendable {
    public var kind: String
    public var session: String?
    public var request: String?
    public var tool: String?
    public var from: Int64?
    public var to: Int64?
    public init(
        kind: String, session: String? = nil, request: String? = nil, tool: String? = nil, from: Int64? = nil,
        to: Int64? = nil
    ) {
        self.kind = kind
        self.session = session
        self.request = request
        self.tool = tool
        self.from = from
        self.to = to
    }
}

public enum AgentFeed: Sendable, Equatable {
    case live
    case reconnecting
    /// Events were trimmed: everything held is suspect, refetch it.
    case gap
    case ended(String)
    case event(AgentEvent)
}

/// The Core as the agent screens use it. `LiveAgentsAPI` is the only real one; tests and the demo bring their own.
public protocol AgentsAPI: Sendable {
    func runners() async throws -> [RunnerInfo]
    /// Newest first. `before` is the `index` of the last one held.
    func sessions(before: Int64?, limit: Int) async throws -> [AgentSessionInfo]
    func session(_ id: String) async throws -> AgentSessionInfo
    /// Entries with `seq` above `after`, oldest first.
    func transcript(_ id: String, after: Int64, limit: Int) async throws -> TranscriptPage
    func create(_ new: NewAgentSession) async throws -> AgentSessionInfo
    func send(_ id: String, text: String) async throws -> AgentSessionInfo
    func cancel(_ id: String) async throws -> AgentSessionInfo
    func kill(_ id: String) async throws -> AgentSessionInfo
    func resume(_ id: String) async throws -> AgentSessionInfo
    /// `text` is the next turn; nil continues with no new message.
    func wake(_ id: String, key: String, text: String?) async throws
    func decide(_ id: String, request: String, approved: Bool) async throws -> AgentSessionInfo
    /// The Code Mode writes the Core holds for a person now. They are not transcript entries, so this is the only way to see them.
    func approvals(_ id: String) async throws -> [CoreApproval]
    func events() -> AsyncStream<AgentFeed>
    /// What Core's ledger holds for a session (`admin`), or nil when this device can't read it.
    func ledger(_ session: String) async throws -> SessionLedger?
    /// The chains a session can start from (`admin`). A device without it gets none, not an error.
    func chains() async throws -> [ChainOption]
    /// The agents that have a chain bound (`admin`); none for a device without it.
    func agents() async throws -> [String]
    /// Which chain each agent is bound to (`admin`); none for a device without it.
    func bindings() async throws -> [AgentBinding]
    /// Binds an agent to a chain (`admin`, Touch ID). Binding it again moves it.
    func bind(agent: String, chain: Int64) async throws
    /// Unbinds an agent: its sessions fall back to the default chain (`admin`, Touch ID).
    func unbind(agent: String) async throws
    /// Every session of a run (its attempts), `?run=`.
    func attempts(run: String) async throws -> [AgentSessionInfo]
    /// An account's label, for a route; nil when the device may not read it.
    func accountName(_ id: Int64) async throws -> String?
    /// Interrupts the turn in flight (the CLI's Esc); the session stays open and goes back to waiting.
    func stopTurn(_ id: String) async throws -> AgentSessionInfo
    /// Ends the session for good (the CLI exits).
    func end(_ id: String) async throws -> AgentSessionInfo
    /// Names a session (`PATCH title`).
    func rename(_ id: String, title: String) async throws -> AgentSessionInfo
}

extension AgentsAPI {
    public func chains() async throws -> [ChainOption] { [] }
    public func agents() async throws -> [String] { [] }
    public func bindings() async throws -> [AgentBinding] { [] }
    public func bind(agent: String, chain: Int64) async throws { throw CoreError.forbiddenScope }
    public func unbind(agent: String) async throws { throw CoreError.forbiddenScope }
    public func ledger(_ session: String) async throws -> SessionLedger? { nil }
    public func attempts(run: String) async throws -> [AgentSessionInfo] { [] }
    public func accountName(_ id: Int64) async throws -> String? { nil }
    /// Ending a session is the Core's cancel until a dedicated route exists.
    public func end(_ id: String) async throws -> AgentSessionInfo { try await cancel(id) }
}

/// Reading a transcript entry body (the runner's JSON) into words. Pure, so it is tested without a Core.
enum EntryParser {
    static func kind(_ b: [String: Any]) -> EntryKind {
        let type = b["type"] as? String ?? ""
        func str(_ k: String) -> String? { b[k] as? String }
        func int(_ k: String) -> Int? { (b[k] as? NSNumber)?.intValue }
        switch type {
        case "started": return .started(harness: str("harness"), resumed: b["resumed"] as? Bool ?? false)
        case "message": return .user(str("text") ?? "")
        // The runner's `user_message` says it took a message the Core already recorded as `message` (same text, `id` = that
        // entry's seq - 1), so drawing both showed one message twice.
        case "user_message": return .hidden
        // The harness's `rate_limit` is its usage report after every turn (`allowed`, `allowed_warning`): only a refusal is news.
        case "rate_limit":
            let status = str("status") ?? "allowed"
            return status.hasPrefix("allowed")
                ? .hidden : .note(type: type, detail: "this account has hit its usage limit for now")
        case "assistant_text": return .assistant(str("text") ?? "")
        case "tool_use":
            let name = str("name") ?? "tool"
            if let e = edit(id: str("id") ?? "", name: name, input: b["input"]) { return e }
            if name.lowercased() == "todowrite", let t = todos(id: str("id") ?? "", input: b["input"]) { return t }
            return .toolUse(id: str("id") ?? "", name: name, summary: summary(b["input"]))
        case "tool_result":
            return .toolResult(
                id: str("id") ?? "", name: str("name"), ok: str("status") != "error", exitCode: int("exit_code"),
                output: str("output") ?? "", durationMs: int("duration_ms"))
        case "approval_request":
            let tool = str("tool") ?? "tool"
            return .approvalRequest(
                id: str("id") ?? "", tool: tool,
                // A Code Mode ask keeps its JSON whole (summary, args, reason) for the card; any other input is one cut line.
                input: tool.hasPrefix("ainkrad.") ? wholeJSON(b["input"]) : summary(b["input"]),
                timeoutSecs: int("timeout_secs"))
        case "approval_decided":
            return .approvalDecided(id: str("id") ?? "", approved: b["approved"] as? Bool ?? false)
        case "interrupted": return .interrupted(reason: str("reason") ?? "")
        case "gap": return .gap(from: Int64(int("from") ?? 0), to: Int64(int("to") ?? 0))
        case "ended":
            let o = b["outcome"] as? [String: Any]
            return .ended(kind: o?["kind"] as? String ?? "ended", reason: o?["reason"] as? String)
        // `approval_requested` is the harness asking; the Core's own `approval_request` entry that follows is the one shown.
        // One answer's usage closes its turn: the divider carries what that turn cost. `turn_ended` and `waiting` are the Core's
        // own bookkeeping (the state says it), so they are not drawn.
        // The runner's `usage` entry is the harness event as it is: `input`, `output`, `cache_read`, `cache_write` are THIS turn's
        // tokens; `cost_usd` (US dollars, a float, null when the harness does not price) is the SESSION's cost so far, not the turn's.
        // So the cost here is cumulative; the transcript store turns it into a per-turn cost (`TranscriptStore.perTurn`).
        case "usage":
            func n(_ k: String) -> Int64 { (b[k] as? NSNumber)?.int64Value ?? 0 }
            let tokens = n("input") + n("output")
            let cost = (b["cost_usd"] as? NSNumber).map { Int64(($0.doubleValue * 1_000_000).rounded()) }
            return .turnEnded(costMicros: cost, tokens: tokens > 0 ? tokens : nil)
        case "session_started", "usage_so_far", "turn_ended", "waiting", "exited", "approval_requested": return .hidden
        default: return .note(type: type.isEmpty ? "unknown" : type, detail: str("reason") ?? str("text") ?? "")
        }
    }

    /// Edit, MultiEdit and Write as a diff: what was cut out and what went in.
    static func edit(id: String, name: String, input: Any?) -> EntryKind? {
        guard let o = input as? [String: Any], let path = (o["file_path"] ?? o["path"]) as? String else { return nil }
        switch name.lowercased() {
        case "edit":
            return .toolEdit(
                id: id, name: name, path: path, old: o["old_string"] as? String ?? "",
                new: o["new_string"] as? String ?? "", ok: nil, durationMs: nil)
        case "multiedit":
            let es = (o["edits"] as? [[String: Any]]) ?? []
            return .toolEdit(
                id: id, name: name, path: path,
                old: es.compactMap { $0["old_string"] as? String }.joined(separator: "\n"),
                new: es.compactMap { $0["new_string"] as? String }.joined(separator: "\n"), ok: nil, durationMs: nil)
        case "write":
            return .toolEdit(
                id: id, name: name, path: path, old: "", new: o["content"] as? String ?? "", ok: nil, durationMs: nil)
        default: return nil
        }
    }

    static func todos(id: String, input: Any?) -> EntryKind? {
        guard let o = input as? [String: Any], let list = o["todos"] as? [[String: Any]] else { return nil }
        let items = list.compactMap { t -> TodoItem? in
            guard let text = (t["content"] ?? t["text"]) as? String else { return nil }
            return TodoItem(text: text, status: TodoItem.Status(rawValue: t["status"] as? String ?? "") ?? .pending)
        }
        return .toolTodos(id: id, items: items)
    }

    /// A tool's input in one line: its command or path, else the JSON, cut.
    static func summary(_ input: Any?) -> String {
        if let s = input as? String { return cut(s) }
        guard let o = input as? [String: Any] else { return "" }
        // A Code Mode script is kept long: its row folds it away until you open it.
        if let s = o["code"] as? String { return cut(s, 6_000) }
        for k in ["command", "file_path", "path", "pattern", "url", "query"] {
            if let s = o[k] as? String { return cut(s) }
        }
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]),
            let s = String(data: d, encoding: .utf8)
        else { return "" }
        return cut(s)
    }

    static func wholeJSON(_ input: Any?) -> String {
        if let s = input as? String { return cut(s, 8_000) }
        guard let o = input as? [String: Any],
            let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]),
            let s = String(data: d, encoding: .utf8)
        else { return "" }
        return cut(s, 8_000)
    }

    private static func cut(_ s: String, _ n: Int = 400) -> String { s.count > n ? String(s.prefix(n)) + "…" : s }
}
