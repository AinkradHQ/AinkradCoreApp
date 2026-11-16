import Foundation

/// Where a room's written overview stands (`GET /rooms/{room}/overview`, field `state`).
public enum OverviewState: String, Codable, Sendable, Equatable {
    case notWritten = "not_written"
    case writing
    case written
    case failed
    /// Nothing can write it yet: no AI account is set up.
    case needsAccount = "needs_account"
    /// The room is local only and the cloud is off for it.
    case cloudOff = "cloud_off"
}

/// How far the current write is: `total` rooms in it (one for a single room), how many are finished or failed.
public struct OverviewProgress: Codable, Sendable, Equatable {
    public var total: Int
    public var done: Int
    public var failed: Int
    public init(done: Int, total: Int, failed: Int = 0) {
        self.done = done
        self.total = total
        self.failed = failed
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        done = try c.decodeIfPresent(Int.self, forKey: .done) ?? 0
        failed = try c.decodeIfPresent(Int.self, forKey: .failed) ?? 0
    }
    enum CodingKeys: String, CodingKey { case total, done, failed }
}

/// One rule in a group, with the ids of the items it was read from.
public struct OverviewRule: Codable, Sendable, Equatable, Identifiable {
    public var text: String
    public var sources: [String]
    public var id: String { text }
    public init(_ text: String, sources: [String] = []) {
        self.text = text
        self.sources = sources
    }
}

public struct OverviewRules: Codable, Sendable, Equatable {
    public var workflow: [OverviewRule]
    public var code: [OverviewRule]
    public var design: [OverviewRule]
    public var never: [OverviewRule]

    public init(
        workflow: [OverviewRule] = [], code: [OverviewRule] = [], design: [OverviewRule] = [],
        never: [OverviewRule] = []
    ) {
        self.workflow = workflow
        self.code = code
        self.design = design
        self.never = never
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workflow = try c.decodeIfPresent([OverviewRule].self, forKey: .workflow) ?? []
        code = try c.decodeIfPresent([OverviewRule].self, forKey: .code) ?? []
        design = try c.decodeIfPresent([OverviewRule].self, forKey: .design) ?? []
        never = try c.decodeIfPresent([OverviewRule].self, forKey: .never) ?? []
    }

    /// The groups the screen shows, in order, without the empty ones.
    var groups: [(title: String, rules: [OverviewRule], never: Bool)] {
        [("Workflow", workflow, false), ("Code", code, false), ("Design", design, false), ("Never do", never, true)]
            .filter { !$0.1.isEmpty }.map { (title: $0.0, rules: $0.1, never: $0.2) }
    }
}

public struct OverviewFacts: Codable, Sendable, Equatable {
    public var stack: String?
    public var state: String?
    public var lastActivity: String?
    public init(stack: String? = nil, state: String? = nil, lastActivity: String? = nil) {
        self.stack = stack
        self.state = state
        self.lastActivity = lastActivity
    }
    enum CodingKeys: String, CodingKey {
        case stack, state
        case lastActivity = "last_activity"
    }
    /// The rows that have a value, labelled for the screen.
    var rows: [(label: String, value: String)] {
        [("Stack", stack), ("State", state), ("Last activity", lastActivity)].compactMap { l, v in
            v.flatMap { $0.isEmpty ? nil : (label: l, value: $0) }
        }
    }
}

public struct OverviewBody: Codable, Sendable, Equatable {
    /// Paragraphs separated by a blank line. The facts sit after the first one.
    public var summary: String
    public var facts: OverviewFacts
    public var rules: OverviewRules
    /// The instructions as first written (the room's own, possibly edited, text is `RoomOverview.instructions`).
    public var instructions: String

    public init(
        summary: String, facts: OverviewFacts = OverviewFacts(), rules: OverviewRules = OverviewRules(),
        instructions: String = ""
    ) {
        self.summary = summary
        self.facts = facts
        self.rules = rules
        self.instructions = instructions
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decode(String.self, forKey: .summary)
        facts = try c.decodeIfPresent(OverviewFacts.self, forKey: .facts) ?? OverviewFacts()
        rules = try c.decodeIfPresent(OverviewRules.self, forKey: .rules) ?? OverviewRules()
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions) ?? ""
    }
    enum CodingKeys: String, CodingKey { case summary, facts, rules, instructions }

    var paragraphs: [String] {
        summary.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// `OverviewView` of the Core: one room's overview and where its writing stands.
public struct RoomOverview: Codable, Sendable, Equatable {
    public var state: OverviewState
    /// Why it waits, failed or cannot be written ("queued", "waiting: no runner is online"); empty when there is nothing to say.
    public var detail: String
    public var writtenAt: String?
    /// "provider:account" of the account that wrote it.
    public var model: String?
    public var progress: OverviewProgress?
    public var overview: OverviewBody?
    /// The editable instructions, the ones AI sessions read once approved.
    public var instructions: String?
    public var instructionsApprovedAt: String?
    /// Item id to title, for every item a rule cites.
    public var sourceTitles: [String: String]

    public init(
        state: OverviewState, detail: String = "", writtenAt: String? = nil, model: String? = nil,
        progress: OverviewProgress? = nil, overview: OverviewBody? = nil, instructions: String? = nil,
        instructionsApprovedAt: String? = nil, sourceTitles: [String: String] = [:]
    ) {
        self.state = state
        self.detail = detail
        self.writtenAt = writtenAt
        self.model = model
        self.progress = progress
        self.overview = overview
        self.instructions = instructions
        self.instructionsApprovedAt = instructionsApprovedAt
        self.sourceTitles = sourceTitles
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(OverviewState.self, forKey: .state)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        writtenAt = try c.decodeIfPresent(String.self, forKey: .writtenAt)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        progress = try c.decodeIfPresent(OverviewProgress.self, forKey: .progress)
        overview = try c.decodeIfPresent(OverviewBody.self, forKey: .overview)
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions)
        instructionsApprovedAt = try c.decodeIfPresent(String.self, forKey: .instructionsApprovedAt)
        sourceTitles = try c.decodeIfPresent([String: String].self, forKey: .sourceTitles) ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case state, detail, model, progress, overview, instructions
        case writtenAt = "written_at"
        case instructionsApprovedAt = "instructions_approved_at"
        case sourceTitles = "source_titles"
    }

    var instructionsApproved: Bool { instructionsApprovedAt != nil }
    /// The text AI sessions get: the room's own, else the one first written.
    var instructionsText: String { instructions ?? overview?.instructions ?? "" }

    /// "Claude, work" for `claude:work`; anything without a colon as it is.
    var writer: String {
        guard let m = model, !m.isEmpty else { return "Core" }
        let parts = m.split(separator: ":", maxSplits: 1).map(String.init)
        return parts.count == 2 ? "\(parts[0].capitalized), \(parts[1])" : m
    }
}

/// What the room Overview asks of a service. Small on purpose: the sample implements it today, the Core client when its
/// routes are merged (`GET /rooms/{room}/overview`, `POST …/overview/write`, `PATCH …/overview/instructions`).
public protocol RoomOverviewService: Sendable {
    func roomOverview(room: String) async throws -> RoomOverview
    /// Queues the writing. The state then reads `writing` until the Core is done; a write already open is not an error.
    func writeOverview(room: String) async throws
    /// Edits the instructions (`text` nil keeps them) and approves or withdraws them.
    func setInstructions(room: String, text: String?, approved: Bool) async throws
}
