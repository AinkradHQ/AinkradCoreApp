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
    func wake(_ id: String, key: String) async throws
    func decide(_ id: String, request: String, approved: Bool) async throws -> AgentSessionInfo
    func events() -> AsyncStream<AgentFeed>
    /// What Core's ledger holds for a session (`admin`), or nil when this device can't read it.
    func ledger(_ session: String) async throws -> SessionLedger?
}

extension AgentsAPI {
    public func ledger(_ session: String) async throws -> SessionLedger? { nil }
}

/// Reading a transcript entry body (the runner's JSON) into words. Pure, so it is tested without a Core.
enum EntryParser {
    static func kind(_ b: [String: Any]) -> EntryKind {
        let type = b["type"] as? String ?? ""
        func str(_ k: String) -> String? { b[k] as? String }
        func int(_ k: String) -> Int? { (b[k] as? NSNumber)?.intValue }
        switch type {
        case "started": return .started(harness: str("harness"), resumed: b["resumed"] as? Bool ?? false)
        case "message", "user_message": return .user(str("text") ?? "")
        case "assistant_text": return .assistant(str("text") ?? "")
        case "tool_use":
            return .toolUse(id: str("id") ?? "", name: str("name") ?? "tool", summary: summary(b["input"]))
        case "tool_result":
            return .toolResult(
                id: str("id") ?? "", name: str("name"), ok: str("status") != "error", exitCode: int("exit_code"),
                output: str("output") ?? "", durationMs: int("duration_ms"))
        case "approval_request":
            return .approvalRequest(
                id: str("id") ?? "", tool: str("tool") ?? "tool", input: summary(b["input"]),
                timeoutSecs: int("timeout_secs"))
        case "approval_decided":
            return .approvalDecided(id: str("id") ?? "", approved: b["approved"] as? Bool ?? false)
        case "interrupted": return .interrupted(reason: str("reason") ?? "")
        case "gap": return .gap(from: Int64(int("from") ?? 0), to: Int64(int("to") ?? 0))
        case "ended":
            let o = b["outcome"] as? [String: Any]
            return .ended(kind: o?["kind"] as? String ?? "ended", reason: o?["reason"] as? String)
        // `approval_requested` is the harness asking; the Core's own `approval_request` entry that follows is the one shown.
        case "session_started", "usage", "usage_so_far", "turn_ended", "exited", "approval_requested": return .hidden
        default: return .note(type: type.isEmpty ? "unknown" : type, detail: str("reason") ?? str("text") ?? "")
        }
    }

    /// A tool's input in one line: its command or path, else the JSON, cut.
    static func summary(_ input: Any?) -> String {
        if let s = input as? String { return cut(s) }
        guard let o = input as? [String: Any] else { return "" }
        for k in ["command", "file_path", "path", "pattern", "url", "query"] {
            if let s = o[k] as? String { return cut(s) }
        }
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]),
            let s = String(data: d, encoding: .utf8)
        else { return "" }
        return cut(s)
    }

    private static func cut(_ s: String, _ n: Int = 400) -> String { s.count > n ? String(s.prefix(n)) + "…" : s }
}
