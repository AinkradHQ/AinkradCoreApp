import CoreUI
import Foundation

/// Tokens and cost as the harness reported them.
public struct AgentUsageInfo: Equatable, Sendable {
    public var input: Int64
    public var output: Int64
    public var cacheRead: Int64
    public var cacheWrite: Int64
    /// Millionths of a US dollar, when the harness says.
    public var costMicros: Int64?
    public init(input: Int64, output: Int64, cacheRead: Int64 = 0, cacheWrite: Int64 = 0, costMicros: Int64? = nil) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.costMicros = costMicros
    }
    public var tokens: Int64 { input + output }
}

/// One agent session as the API has it. There is no title yet (KAN-455): a session is its harness, runner and id.
public struct AgentSessionInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public var runner: String
    public var harness: String
    public var model: String?
    public var state: SessionState
    public var outcome: SessionOutcome?
    public var outcomeReason: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var endedAt: Date?
    public var lastSeq: Int64
    public var usage: AgentUsageInfo?
    public var resumes: Int?
    /// Its row, for paging the list with `before`.
    public var index: Int64?

    public init(
        id: String, runner: String, harness: String, model: String? = nil, state: SessionState,
        outcome: SessionOutcome? = nil, outcomeReason: String? = nil, createdAt: Date, updatedAt: Date,
        endedAt: Date? = nil, lastSeq: Int64 = 0, usage: AgentUsageInfo? = nil, resumes: Int? = nil, index: Int64? = nil
    ) {
        self.id = id
        self.runner = runner
        self.harness = harness
        self.model = model
        self.state = state
        self.outcome = outcome
        self.outcomeReason = outcomeReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.endedAt = endedAt
        self.lastSeq = lastSeq
        self.usage = usage
        self.resumes = resumes
        self.index = index
    }

    /// Doing something now (or about to, or being resumed). A state this build does not know counts as not live.
    public var live: Bool {
        switch state {
        case .starting, .running, .interrupted: true
        default: false
        }
    }
    public var over: Bool {
        switch state {
        case .ended, .lost: true
        default: false
        }
    }
    /// `as_01JC…` is long: the tail is what tells two sessions apart.
    public var shortID: String { id.count > 10 ? "…" + id.suffix(6) : id }
}

public struct RunnerInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var online: Bool
    public var degraded: Bool
    public var load: Int
    public var capacity: Int?
    /// Driver names it advertised; empty until it first connected since the Core started.
    public var drivers: [String]
    public init(
        id: String, name: String, online: Bool, degraded: Bool = false, load: Int = 0, capacity: Int? = nil,
        drivers: [String] = []
    ) {
        self.id = id
        self.name = name
        self.online = online
        self.degraded = degraded
        self.load = load
        self.capacity = capacity
        self.drivers = drivers
    }
    /// Whether it said it runs agents. Unknown (never connected) counts as no: the Core refuses it with the reason.
    public var runsAgents: Bool { drivers.contains("agent") }
}

public struct NewAgentSession: Equatable, Sendable {
    public var runner: String
    public var harness: String
    public var model: String?
    public var prompt: String
    /// `ask`, `accept_edits` or `sandboxed`.
    public var mode: String
    public var secrets: [String]
    public init(
        runner: String, harness: String, model: String? = nil, prompt: String, mode: String = "ask",
        secrets: [String] = []
    ) {
        self.runner = runner
        self.harness = harness
        self.model = model
        self.prompt = prompt
        self.mode = mode
        self.secrets = secrets
    }
}

/// What one transcript entry says. Entry types this build does not know are kept as `.note` with their raw word.
public enum EntryKind: Equatable, Sendable {
    case started(harness: String?, resumed: Bool)
    /// What a person (or the Citadel) told the agent.
    case user(String)
    case assistant(String)
    case toolUse(id: String, name: String, summary: String)
    case toolResult(
        id: String, name: String?, ok: Bool, exitCode: Int?, output: String, durationMs: Int?)
    /// A tool call and its result as one row: the store folds a `toolResult` into the `toolUse` it answers.
    case toolDone(
        id: String, name: String, summary: String, ok: Bool, exitCode: Int?, output: String, durationMs: Int?)
    case approvalRequest(id: String, tool: String, input: String, timeoutSecs: Int?)
    case approvalDecided(id: String, approved: Bool)
    case interrupted(reason: String)
    case gap(from: Int64, to: Int64)
    case ended(kind: String, reason: String?)
    case note(type: String, detail: String)
    /// Bookkeeping that is not for reading (session id, usage, turn end).
    case hidden
}

public struct TranscriptEntry: Identifiable, Equatable, Sendable {
    public let seq: Int64
    public let at: Date
    public let kind: EntryKind
    public var id: Int64 { seq }
    public init(seq: Int64, at: Date, kind: EntryKind) {
        self.seq = seq
        self.at = at
        self.kind = kind
    }
    public var visible: Bool { kind != .hidden }
}

public struct TranscriptPage: Equatable, Sendable {
    public var entries: [TranscriptEntry]
    public var lastSeq: Int64
    public init(entries: [TranscriptEntry], lastSeq: Int64) {
        self.entries = entries
        self.lastSeq = lastSeq
    }
}

/// A tool call the agent waits on you for, read from its transcript. The Core has no list of approvals: they are entries.
public struct ApprovalRequest: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable { case pending, approved, denied, expired }
    /// The request's id, what `decide` takes.
    public let id: String
    public let session: String
    public let tool: String
    public let input: String
    public let requestedAt: Date
    public let timeoutSecs: Int?
    public var decision: Bool?

    /// One approval, everywhere it is keyed (bell, macOS notification, "already announced"). The request id is only unique within
    /// its session (a stand-in agent always says `req1`), so the session is part of it.
    public var key: String { "agents.ap.\(session).\(id)" }

    public var expiresAt: Date? { timeoutSecs.map { requestedAt.addingTimeInterval(TimeInterval($0)) } }

    /// `sessionOver`: an agent that ended is no longer waiting. Expiry follows the runner's clock, as reported.
    public func status(now: Date, sessionOver: Bool) -> Status {
        if let decision { return decision ? .approved : .denied }
        if sessionOver { return .expired }
        if let expiresAt, now >= expiresAt { return .expired }
        return .pending
    }

    public func remaining(now: Date) -> TimeInterval? { expiresAt.map { max(0, $0.timeIntervalSince(now)) } }
}

/// Words and numbers for sessions: one place, so the list, the pane and the bell agree.
public enum AgentWords {
    public static func tokens(_ n: Int64) -> String {
        n >= 1_000_000
            ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? "\(Int((Double(n) / 1e3).rounded()))k" : "\(n)"
    }

    public static func cost(_ micros: Int64?) -> String? { micros.map { String(format: "$%.2f", Double($0) / 1e6) } }

    public static func clock(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds))
        let (h, m, s) = (t / 3600, (t % 3600) / 60, t % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    public static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 45 { return "just now" }
        if s < 3600 { return "\(max(1, s / 60)) min ago" }
        if s < 86400 { return "\(s / 3600) h ago" }
        return "\(s / 86400) d ago"
    }

    /// The word for a session in a list or head: a pending approval wins over the state.
    public static func status(_ s: AgentSessionInfo, waiting: Bool) -> (label: String, tone: Tone, symbol: String) {
        if waiting { return ("Waiting on you", .warn, "hand.raised") }
        if case .ended = s.state, let o = s.outcome { return (o.label, o.tone, o.symbol) }
        return (s.state.label, s.state.tone, s.state.symbol)
    }
}

/// What a session was asked to do that has not finished yet.
public enum StopKind: Sendable { case cancelling, killing }
