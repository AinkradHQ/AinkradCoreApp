import Foundation

/// What turning retention on would do, from the Core's dry count (`GET /rooms/{room}/retention?days=N`).
public struct RetentionPreview: Sendable, Equatable {
    public var days: Int
    /// Sources that would lose their text now.
    public var wouldCompact: Int
    public var chars: Int
    public init(days: Int, wouldCompact: Int, chars: Int = 0) {
        self.days = days
        self.wouldCompact = wouldCompact
        self.chars = chars
    }
}

public enum RedistilState: Sendable, Equatable {
    case running, committing, done, failed, cancelled
    case other(String)

    init(_ s: String) {
        switch s {
        case "running": self = .running
        case "committing": self = .committing
        case "done": self = .done
        case "failed": self = .failed
        case "cancelled": self = .cancelled
        default: self = .other(s)
        }
    }
}

/// One clean-up run: a dry run counts, a real one writes new facts and archives the rest as one change set.
public struct RedistilRun: Sendable, Equatable {
    public var id: String
    public var dryRun: Bool
    public var state: RedistilState
    public var total: Int
    public var read: Int
    public var kept: Int?
    public var archived: Int?
    /// The Core's own line, "Kept 84 facts, archived 1,203 items". Set when done.
    public var summary: String?
    /// The change set the result's Undo puts back. None for a dry run.
    public var change: String?
    public var detail: String

    public init(
        id: String, dryRun: Bool, state: RedistilState, total: Int = 0, read: Int = 0, kept: Int? = nil,
        archived: Int? = nil, summary: String? = nil, change: String? = nil, detail: String = ""
    ) {
        self.id = id
        self.dryRun = dryRun
        self.state = state
        self.total = total
        self.read = read
        self.kept = kept
        self.archived = archived
        self.summary = summary
        self.change = change
        self.detail = detail
    }

    /// Still reading or writing: keep asking.
    public var isOpen: Bool { state == .running || state == .committing }
    public var fraction: Double { total > 0 ? min(1, Double(read) / Double(total)) : 0 }

    /// "Keep 84 facts, archive 1,203 items": what Apply would do, said before it does.
    public var plan: String {
        guard let kept, let archived else { return summary ?? "" }
        func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n.formatted()) \(n == 1 ? one : many)" }
        return "Keep \(count(kept, "fact", "facts")), archive \(count(archived, "item", "items"))"
    }
}

/// A room's card: the text an AI session is shown about the room when it starts, and how many records it is made of.
public struct RoomCard: Sendable, Equatable {
    public var text: String
    public var records: Int
    /// False when the size budget cut a record that would have made it.
    public var complete: Bool
    public init(text: String, records: Int, complete: Bool = true) {
        self.text = text
        self.records = records
        self.complete = complete
    }
}

extension RoomPolicy {
    /// The record types the room saves without a review, as the Core names them.
    public var savedTypes: Set<String> { Set(kinds.map(\.wireType)).union(otherAuto) }
    public func saves(_ kind: CandidateKind) -> Bool { savedTypes.contains(kind.wireType) }
}

extension CandidateKind {
    /// The kinds the Auto-save rows list: the Core's seven record types, a landmine being a rule and an open thread a task.
    public static let saveRows: [CandidateKind] = [.fact, .decision, .preference, .rule, .task, .projectState, .summary]
}
