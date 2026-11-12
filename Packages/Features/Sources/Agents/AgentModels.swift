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
    /// The name the Core holds (`title`, set by the first message or a PATCH); nil until it says one.
    public var title: String?
    /// The folder or repo it works in (the Core's `folder` / `repo`), for grouping by project. Nil until the Core says.
    public var project: String?
    /// The branch it works on, when it is a repo.
    public var branch: String?
    /// False when the runner is old and runs one answer, then ends (the Core's `live`); nil when it did not say.
    public var keepsOpen: Bool?
    /// While waiting: since when.
    public var idleSince: Date?
    /// Its row, for paging the list with `before`.
    public var index: Int64?
    /// Its chain, account, run and attempts (admins only; nil for any other device).
    public var route: SessionRoute?

    public init(
        id: String, runner: String, harness: String, model: String? = nil, state: SessionState,
        outcome: SessionOutcome? = nil, outcomeReason: String? = nil, createdAt: Date, updatedAt: Date,
        endedAt: Date? = nil, lastSeq: Int64 = 0, usage: AgentUsageInfo? = nil, resumes: Int? = nil,
        index: Int64? = nil,
        route: SessionRoute? = nil, title: String? = nil, project: String? = nil, branch: String? = nil,
        keepsOpen: Bool? = nil, idleSince: Date? = nil
    ) {
        self.keepsOpen = keepsOpen
        self.idleSince = idleSince
        self.title = title
        self.project = project
        self.branch = branch
        self.route = route
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
        case .starting, .running, .waiting, .interrupted: true
        default: false
        }
    }
    /// Ended because a budget ran out. Core reports it as `budget`, or as a cancel whose reason names the budget (KAN-474).
    public var stoppedByBudget: Bool {
        if outcome?.unknownRaw == "budget" { return true }
        if case .cancelled? = outcome { return outcomeReason?.lowercased().contains("budget") == true }
        return false
    }
    /// Live and idle: the process is up and the composer is the only thing it needs.
    /// Ended because nobody came back (`agents.idle_end_secs`): the next message resumes it.
    public var idleEnded: Bool { state == .ended && outcome == .succeeded && outcomeReason == "idle_timeout" }
    public var idle: Bool { if case .waiting = state { true } else { false } }
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

/// A chain a session can start from: its name and, in order, the pools and models it tries. Only admins are given any.
public struct ChainOption: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let isDefault: Bool
    /// One word per step, e.g. `claude-pool · sonnet`.
    public let steps: [String]
    public init(id: Int64, name: String, isDefault: Bool, steps: [String]) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.steps = steps
    }
}

public struct NewAgentSession: Equatable, Sendable {
    public var runner: String
    public var harness: String
    public var model: String?
    /// Empty opens a live session that waits for the first message, like typing `claude` in a terminal.
    public var prompt: String
    /// A folder or repo and branch the session works in; nil is a fresh folder.
    public var project: String?
    public var branch: String?
    /// `ask`, `accept_edits` or `sandboxed`.
    public var mode: String
    public var secrets: [String]
    /// A fallback chain's id, or an agent id whose bound (else default) chain serves the session. Both need `admin`, and
    /// with either the harness and model are left out: the account the Core picks sets them.
    public var chain: Int64?
    public var agent: String?
    public init(
        runner: String, harness: String, model: String? = nil, prompt: String, mode: String = "ask",
        secrets: [String] = [], chain: Int64? = nil, agent: String? = nil, project: String? = nil, branch: String? = nil
    ) {
        self.project = project
        self.branch = branch
        self.chain = chain
        self.agent = agent
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
    /// A file edit (Edit, MultiEdit, Write), kept with what it replaced so the row can draw a diff. `ok` is nil until it answers.
    case toolEdit(id: String, name: String, path: String, old: String, new: String, ok: Bool?, durationMs: Int?)
    /// The CLI's todo list (TodoWrite), drawn as a checklist.
    case toolTodos(id: String, items: [TodoItem])
    /// A turn is over: the harness is waiting for you. Carries what the turn cost, when the Core says.
    case turnEnded(costMicros: Int64?, tokens: Int64?)
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

public struct TodoItem: Equatable, Sendable {
    public enum Status: String, Sendable {
        case pending
        case inProgress = "in_progress"
        case completed
    }
    public var text: String
    public var status: Status
    public init(text: String, status: Status) {
        self.text = text
        self.status = status
    }
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
    /// When the answer was recorded.
    public var decidedAt: Date?

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
        n.formatted(.number.notation(.compactName))
    }

    /// Under one cent is "< $0.01", not "$0.00" (that reads as a missing price); `exactCost` has the real figure.
    public static func cost(_ micros: Int64?) -> String? {
        micros.map { $0 > 0 && $0 < 10_000 ? "< $0.01" : (Double($0) / 1e6).formatted(.currency(code: "USD")) }
    }

    /// The tooltip for a small cost, to four places: "$0.0020".
    public static func exactCost(_ micros: Int64?) -> String? {
        micros.map { (Double($0) / 1e6).formatted(.currency(code: "USD").precision(.fractionLength(4))) }
    }

    public static func clock(_ seconds: TimeInterval) -> String {
        coreClock(Int(seconds))
    }

    public static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 45 { return String(localized: "just now", bundle: .module) }
        if s < 3600 { return String(localized: "\(max(1, s / 60)) min ago", bundle: .module) }
        if s < 86400 { return String(localized: "\(s / 3600) h ago", bundle: .module) }
        return String(localized: "\(s / 86400) d ago", bundle: .module)
    }

    /// The word for a session in a list or head: a pending approval wins over the state.
    public static func status(_ s: AgentSessionInfo, waiting: Bool) -> (label: String, tone: Tone, symbol: String) {
        if waiting { return (String(localized: "Needs you", bundle: .module), .warn, "hand.raised") }
        if s.idleEnded { return (String(localized: "Ended (idle)", bundle: .module), .queue, "moon.zzz") }
        if case .ended = s.state, s.stoppedByBudget {
            return (endedWords("budget"), .warn, "gauge.with.dots.needle.100percent")
        }
        if case .ended = s.state, case .tokenCap? = s.outcome {
            return (endedWords("token_cap"), .warn, "gauge.with.dots.needle.100percent")
        }
        if case .ended = s.state, let o = s.outcome { return (o.label, o.tone, o.symbol) }
        return (s.state.label, s.state.tone, s.state.symbol)
    }

    /// How a session ended, in words, for the header, the tile and the transcript's last chip. The raw code goes in `.help` only.
    public static func endedWords(_ kind: String) -> String {
        switch kind {
        case "succeeded": String(localized: "Ended: finished", bundle: .module)
        case "failed": String(localized: "Ended: failed", bundle: .module)
        case "stalled": String(localized: "Ended: stopped making progress", bundle: .module)
        case "token_cap": String(localized: "Ended: token limit reached", bundle: .module)
        case "budget": String(localized: "Ended: budget reached", bundle: .module)
        case "cancelled": String(localized: "Ended: cancelled", bundle: .module)
        case "lost": String(localized: "Ended: the runner lost it", bundle: .module)
        case "ended", "": String(localized: "Ended", bundle: .module)
        default: "Ended: " + sentence(kind).lowercased()
        }
    }

    /// A reason the Core or runner gave: a known code becomes a sentence, a snake_case code is spaced, free text stays.
    public static func reasonWords(_ reason: String) -> String {
        switch reason {
        case "idle_timeout": return "Nobody came back, so it ended. Send a message to continue."
        case "host_lost": return "The runner's terminal process was lost"
        case "token_cap": return "It used all the tokens it was allowed"
        case "runner_lost": return "The runner went away"
        case "budget": return "A budget ran out"
        // The runner's own words for a cancelled run; the state word is "Cancelled".
        case "paused by admin": return "Cancelled"
        default:
            let code = reason.range(of: #"^[a-z0-9]+(_[a-z0-9]+)+$"#, options: .regularExpression) != nil
            return code ? sentence(reason) : reason
        }
    }

    /// `approval_escalated` becomes `Approval escalated`.
    static func sentence(_ code: String) -> String {
        let w = code.replacingOccurrences(of: "_", with: " ")
        return w.prefix(1).uppercased() + w.dropFirst()
    }

    /// The name people know a harness by: `claude-code` and `claude` are both Claude.
    public static func harnessName(_ h: String) -> String {
        switch h.lowercased() {
        case "claude", "claude-code", "claude_code": "Claude"
        case "codex": "Codex"
        case "opencode": "OpenCode"
        case "agy": "Antigravity"
        default: h.prefix(1).uppercased() + h.dropFirst()
        }
    }

    /// A session's name: the first line of its prompt, cut to fit. Nil when there is no prompt.
    public static func title(prompt: String?) -> String? {
        guard
            let line = prompt?.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { !$0.isEmpty })
        else { return nil }
        return line.count > 90 ? String(line.prefix(89)) + "…" : line
    }

    /// The prompt-less name: the harness and the id's tail, `Claude · K9R003`.
    /// A short word for the harness's tool in the AI session list ("Claude Code").
    public static func toolName(_ h: String) -> String {
        switch h.lowercased() {
        case "claude", "claude-code", "claude_code": "Claude Code"
        default: harnessName(h)
        }
    }

    public static func fallbackTitle(_ s: AgentSessionInfo) -> String {
        "\(harnessName(s.harness)) · \(s.id.count > 10 ? String(s.id.suffix(6)) : s.id)"
    }

    /// Prompt-size words: nothing until the prompt nears the Core's limit.
    public static func promptSizeWords(bytes: Int, limit: Int) -> String? {
        if bytes > limit {
            let pages = max(1, Int((Double(bytes - limit) / 3000).rounded(.up)))
            return "Too long: shorten it by about \(pages) page\(pages == 1 ? "" : "s")"
        }
        if Double(bytes) >= Double(limit) * 0.8 {
            let left = (limit - bytes) / 1024
            return left <= 0 ? "Almost at the limit" : "About \(left) KiB left"
        }
        return nil
    }
}

/// What a session was asked to do that has not finished yet.
public enum StopKind: Sendable { case cancelling, killing }

/// An agent and the chain its sessions draw accounts from.
public struct AgentBinding: Identifiable, Equatable, Sendable {
    public var id: String { agent }
    public let agent: String
    public let chain: Int64
    public init(agent: String, chain: Int64) {
        self.agent = agent
        self.chain = chain
    }
}
