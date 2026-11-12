import Foundation

// Brain M3: the Inbox candidates, a room's model policy and auto-accept rules, and the runners' history collection.
// Candidate text is memory content, so it lives only in `BrainCandidates` and is never logged or saved (BM-00 I-8).

/// What a distilled candidate is, in the words the screens use. The Core's seven types fold into these four.
public enum CandidateKind: String, Sendable, CaseIterable, Hashable {
    case fact, decision, landmine, openThread

    public var label: String {
        switch self {
        case .fact: "Fact"
        case .decision: "Decision"
        case .landmine: "Landmine"
        case .openThread: "Open thread"
        }
    }
    public var plural: String { self == .openThread ? "Open threads" : label + "s" }
    public var about: String {
        switch self {
        case .fact: "Plain statements with one source or more"
        case .decision: "Something was chosen"
        case .landmine: "A trap to avoid"
        case .openThread: "A question still open"
        }
    }
    public var symbol: String {
        switch self {
        case .fact: "info.square"
        case .decision: "tag"
        case .landmine: "exclamationmark.triangle"
        case .openThread: "questionmark"
        }
    }
    /// The Core's `type` for this kind, sent when a candidate is edited.
    var wire: String {
        switch self {
        case .fact: "fact"
        case .decision: "decision"
        case .landmine: "rule"
        case .openThread: "task"
        }
    }
    init(wire: String) {
        switch wire {
        case "decision": self = .decision
        case "rule": self = .landmine
        case "task": self = .openThread
        default: self = .fact
        }
    }
}

/// One place a candidate came from, with the line that supports it.
public struct CandidateSource: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    /// Where and when, e.g. "AinkradCore · 11 Nov, 14:20".
    public let place: String
    public let quote: String
    public init(id: String, title: String, place: String = "", quote: String = "") {
        self.id = id
        self.title = title
        self.place = place
        self.quote = quote
    }
}

/// A statement a distillation proposed for one room. Nothing is filed until you accept it.
public struct InboxCandidate: Sendable, Hashable, Identifiable {
    public let id: String
    public let room: String
    public let roomName: String
    public var kind: CandidateKind
    public var text: String
    /// The tool the sources came from, e.g. "Claude Code".
    public let app: String
    /// Short date for the list ("11 Nov") and the longer one for the detail ("today, 14:02").
    public let date: String
    public let distilled: String
    /// The account that distilled it, e.g. "Claude, Max account".
    public let account: String
    public var sources: [CandidateSource]
    /// You changed it before accepting, so the list says so.
    public var edited = false
    /// The Core's creation time, so the list reads newest first.
    public var sortKey = ""
    public init(
        id: String, room: String, roomName: String, kind: CandidateKind, text: String, app: String = "",
        date: String = "", distilled: String = "", account: String = "", sources: [CandidateSource] = [],
        edited: Bool = false, sortKey: String = ""
    ) {
        self.sortKey = sortKey
        self.id = id
        self.room = room
        self.roomName = roomName
        self.kind = kind
        self.text = text
        self.app = app
        self.date = date
        self.distilled = distilled
        self.account = account
        self.sources = sources
        self.edited = edited
    }
}

/// Items of one room waiting for a local model.
public struct QueuedRoom: Sendable, Hashable, Identifiable {
    public let room: String
    public let name: String
    public let items: Int
    public var id: String { room }
    public init(room: String, name: String, items: Int) {
        self.room = room
        self.name = name
        self.items = items
    }
}

/// The Inbox as one list across the open rooms, plus what waits for a local model.
public struct CandidateInbox: Sendable, Equatable {
    public var items: [InboxCandidate] = []
    public var queued: [QueuedRoom] = []
    public init(items: [InboxCandidate] = [], queued: [QueuedRoom] = []) {
        self.items = items
        self.queued = queued
    }
    public var queuedItems: Int { queued.reduce(0) { $0 + $1.items } }
}

public enum CandidateDecision: Sendable, Hashable {
    case accept
    case edit(kind: CandidateKind, text: String)
    case reject
}

/// Whether a room may send text to a cloud provider.
public enum ModelPolicy: String, Sendable, Hashable {
    case cloud
    case localOnly = "local_only"
}

/// A room's model policy and its auto-accept rules.
public struct RoomPolicy: Sendable, Equatable {
    public var model: ModelPolicy = .cloud
    public var provider = "Anthropic"
    public var account = ""
    public var localModel: String?
    public var providers: [String] = ["Anthropic"]
    public var accounts: [String] = []
    public var localModels: [String] = []
    public var autoAccept = false
    public var kinds: Set<CandidateKind> = []
    public var minSources = 2
    /// The kinds this Core can accept without a review, and whether it keeps a minimum of sources.
    public var autoKindsAllowed = Set(CandidateKind.allCases)
    public var minSourcesServed = true
    /// Items waiting because the room is local only and no runner has a local model.
    public var queued = 0
    public init() {}
    public var needsLocalModel: Bool { model == .localOnly && localModels.isEmpty && queued > 0 }
}

/// A change to a room's policy. A nil field keeps what the Core has.
public struct PolicyChange: Sendable, Equatable {
    public var model: ModelPolicy?
    public var autoAccept: Bool?
    public var kinds: Set<CandidateKind>?
    public var minSources: Int?
    public var provider: String?
    public var account: String?
    public var localModel: String?
    public init(
        model: ModelPolicy? = nil, autoAccept: Bool? = nil, kinds: Set<CandidateKind>? = nil, minSources: Int? = nil,
        provider: String? = nil, account: String? = nil, localModel: String? = nil
    ) {
        self.model = model
        self.autoAccept = autoAccept
        self.kinds = kinds
        self.minSources = minSources
        self.provider = provider
        self.account = account
        self.localModel = localModel
    }
}

/// One AI tool a runner can read history from.
public struct RunnerTool: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// Sessions found on the runner; nil when the tool is not installed there.
    public let found: Int?
    public var on: Bool
    public init(id: String, name: String, found: Int?, on: Bool = false) {
        self.id = id
        self.name = name
        self.found = found
        self.on = on
    }
}

/// A runner and whether it collects the AI tool history stored on its own machine. Off by default.
public struct RunnerHistory: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public var online: Bool
    public var enabled: Bool
    public var tools: [RunnerTool]
    public var items: Int
    public var lastRun: String?
    public init(
        id: String, name: String, online: Bool = true, enabled: Bool = false, tools: [RunnerTool] = [],
        items: Int = 0, lastRun: String? = nil
    ) {
        self.id = id
        self.name = name
        self.online = online
        self.enabled = enabled
        self.tools = tools
        self.items = items
        self.lastRun = lastRun
    }
    /// "Claude Code, Codex and OpenCode history".
    public var toolLine: String {
        let names = tools.map(\.name)
        guard let last = names.last else { return "AI tool history" }
        let list = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + last : last
        return list + " history"
    }
}
