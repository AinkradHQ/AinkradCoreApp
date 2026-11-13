import Foundation

// The Brain module's JSON, by hand: the generated client does not cover module routes. These mirror
// `modules/brain/api/openapi.core.json` in AinkradCore (`/modules/brain/v1`). Names, counts and ids only; an item's text
// never comes back from these routes.

public struct BrainStatusWire: Codable, Sendable, Equatable {
    public var present: Bool
    /// `ok`, `locked_mode0`, `missing` or `unavailable`.
    public var key: String
    public var rooms: Int
    public var runs: Int
    public init(present: Bool, key: String, rooms: Int, runs: Int) {
        self.present = present
        self.key = key
        self.rooms = rooms
        self.runs = runs
    }
}

public struct RunCounts: Codable, Sendable, Equatable {
    public var found = 0
    public var stored = 0
    public var duplicate = 0
    public var refused = 0
    public var rejected = 0
    public var cleaned = 0
    public var pointers = 0
    /// Skipped items by reason code (`rule:<id>`), never any text.
    public var skipped: [String: Int] = [:]
    public init() {}
    /// Items the Core has answered for: stored, duplicate, refused by a rule or rejected.
    public var answered: Int { stored + duplicate + refused + rejected }
}

public struct RunView: Codable, Sendable, Equatable {
    public var run: String
    public var kind: String
    /// `collecting`, `discovering`, `review`, `committing`, `committed` or `abandoned`.
    public var state: String
    public var stage: String
    public var counts: RunCounts
    public var sources: [String]
    public var startedAt: String
    enum CodingKeys: String, CodingKey {
        case run, kind, state, stage, counts, sources
        case startedAt = "started_at"
    }
}

/// What a room may be read by and kept for. `nil` leaves a field as it is.
public struct RoomConfigWire: Codable, Sendable, Equatable {
    /// `approved_providers` (default) or `local_only`.
    public var allowedModels: String?
    public var readers: [String]?
    public var reviewDays: Int?
    public var grants: [String]?
    public init(
        allowedModels: String? = nil, readers: [String]? = nil, reviewDays: Int? = nil, grants: [String]? = nil
    ) {
        self.allowedModels = allowedModels
        self.readers = readers
        self.reviewDays = reviewDays
        self.grants = grants
    }
    enum CodingKeys: String, CodingKey {
        case allowedModels = "allowed_models"
        case readers
        case reviewDays = "review_days"
        case grants
    }
}

/// One proposed room.
public struct ProposalCard: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var kindGuess: String
    /// `proposed`, `accepted`, `refused`, `merged`, `committed` or `held`.
    public var state: String
    public var signals: [String]
    /// `mixed_employers` is the one the app acts on.
    public var warnings: [String]
    public var itemCount: Int
    public var sampleTitles: [String]
    public var first: String?
    public var last: String?
    public var room: String?
    public var config: RoomConfigWire
    /// A room this one looks like; the Core only hints, the user merges.
    public var suggestMerge: MergeSuggestion?
    /// The local model's step for this run: `pending`, `ready` or `off`; nil from a Core without it.
    public var semantic: String?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, state, signals, warnings, first, last, room, config, semantic
        case suggestMerge = "suggest_merge"
        case kindGuess = "kind_guess"
        case itemCount = "item_count"
        case sampleTitles = "sample_titles"
    }

    public static let unsortedID = "unsorted"
    public var isUnsorted: Bool { id == Self.unsortedID }
    public var isMixed: Bool { warnings.contains("mixed_employers") }
    public var isHeld: Bool { state == "held" }
    public var isAccepted: Bool { state == "accepted" || state == "held" }
    /// Employer and client rooms: kept apart, and held after commit until the room backup exists.
    public var isGuarded: Bool { kind == "employer" || kind == "client" }

    public init(
        id: String, name: String, kind: String = "product", kindGuess: String? = nil, state: String = "proposed",
        signals: [String] = [], warnings: [String] = [], itemCount: Int = 0, sampleTitles: [String] = [],
        first: String? = nil, last: String? = nil, room: String? = nil, config: RoomConfigWire = .init(),
        suggestMerge: MergeSuggestion? = nil, semantic: String? = nil
    ) {
        self.suggestMerge = suggestMerge
        self.semantic = semantic
        self.id = id
        self.name = name
        self.kind = kind
        self.kindGuess = kindGuess ?? kind
        self.state = state
        self.signals = signals
        self.warnings = warnings
        self.itemCount = itemCount
        self.sampleTitles = sampleTitles
        self.first = first
        self.last = last
        self.room = room
        self.config = config
    }
}

/// `into` is the proposal id to merge into; `reason` is `prefix` or `close`.
public struct MergeSuggestion: Codable, Sendable, Equatable {
    public var into: String
    public var name: String
    public var reason: String

    public init(into: String, name: String, reason: String = "prefix") {
        self.into = into
        self.name = name
        self.reason = reason
    }
}

public struct ItemRow: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var cursor: Int
    public var title: String
    public var startedAt: String
    public var sourceKind: String
    public var warnings: [String]
    /// `needed`, `refused` or none.
    public var mark: String?
    enum CodingKeys: String, CodingKey {
        case id, cursor, title, warnings, mark
        case startedAt = "started_at"
        case sourceKind = "source_kind"
    }
    public init(
        id: String, cursor: Int = 0, title: String, startedAt: String = "", sourceKind: String = "claude_code",
        warnings: [String] = [], mark: String? = nil
    ) {
        self.id = id
        self.cursor = cursor
        self.title = title
        self.startedAt = startedAt
        self.sourceKind = sourceKind
        self.warnings = warnings
        self.mark = mark
    }
}

public struct ItemPage: Codable, Sendable, Equatable {
    public var items: [ItemRow]
    public var next: Int?
}

public struct RoomMade: Codable, Sendable, Equatable, Identifiable {
    public var id: String { room }
    public var proposal: String
    public var room: String
    public var name: String
    public var kind: String
    public var sources: Int
    public var created: Bool
}

public struct CommitResult: Codable, Sendable, Equatable {
    public var rooms: [RoomMade]
    /// Accepted proposals that wait: employer and client rooms until `room_backup` exists.
    public var held: [String]
    public var rulesEnabled: Int
    public var state: String
    enum CodingKeys: String, CodingKey {
        case rooms, held, state
        case rulesEnabled = "rules_enabled"
    }
}

public struct RoomViewWire: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var kind: String
    public var state: String
    public var reviewDays: Int
    public var sources: Int
    public var open: Bool
    enum CodingKeys: String, CodingKey {
        case id, name, kind, state, sources, open
        case reviewDays = "review_days"
    }
}

public struct OpenedWire: Codable, Sendable, Equatable {
    public var room: String
    /// RFC 3339.
    public var openUntil: String
    enum CodingKeys: String, CodingKey {
        case room
        case openUntil = "open_until"
    }
}

// MARK: request bodies

struct StartRunBody: Encodable {
    var kind: String
    var sources: [String]
}
struct CollectedBody: Encodable { var source: String }
struct ProposalPatchBody: Encodable {
    var name: String?
    var kind: String?
    var state: String?
    var config: RoomConfigWire?
}
struct MergeBody: Encodable { var into: String }
public struct Regrouped: Codable, Sendable, Equatable {
    public var proposals: Int
    public var kept: Int
    public var dropped: Int
}
struct SplitBody: Encodable {
    var itemIds: [String]
    var name: String?
    enum CodingKeys: String, CodingKey {
        case itemIds = "item_ids"
        case name
    }
}
struct ItemsPatchBody: Encodable {
    var ids: [String]
    /// `needed`, `refused` or `clear`.
    var mark: String?
    var proposal: String?
}
struct RunIdWire: Decodable { var run: String }
