import Foundation

/// `GET /imports/{run}/semantic`: the local model's sorting suggestions. Nothing here applies by itself.
public struct SemanticView: Codable, Sendable, Equatable {
    /// `pending` (working now), `ready` or `off`.
    public var state: String
    public var duplicates: [DuplicateHint]
    public var rooms: [RoomHint]
    public var merges: [MergeHint]
    /// For an item no rule placed: the room it looks closest to. Absent on a Core before API minor 66.
    public var closest: [ClosestHint]
    /// While `pending`: how many items the local model has read. Absent otherwise, and on a Core before API minor 70.
    public var progress: SemanticProgress?
    /// What the Core tidied by itself once the step finished. Absent while pending, when there was nothing to tidy, and
    /// on a Core before API minor 71.
    public var aiTidy: AiTidy?
    enum CodingKeys: String, CodingKey {
        case state, duplicates, rooms, merges, closest, progress
        case aiTidy = "ai_tidy"
    }

    public init(
        state: String = "off", duplicates: [DuplicateHint] = [], rooms: [RoomHint] = [], merges: [MergeHint] = [],
        closest: [ClosestHint] = [], progress: SemanticProgress? = nil, aiTidy: AiTidy? = nil
    ) {
        self.state = state
        self.duplicates = duplicates
        self.rooms = rooms
        self.merges = merges
        self.closest = closest
        self.progress = progress
        self.aiTidy = aiTidy
    }

    public init(from d: any Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "off"
        duplicates = try c.decodeIfPresent([DuplicateHint].self, forKey: .duplicates) ?? []
        rooms = try c.decodeIfPresent([RoomHint].self, forKey: .rooms) ?? []
        merges = try c.decodeIfPresent([MergeHint].self, forKey: .merges) ?? []
        closest = try c.decodeIfPresent([ClosestHint].self, forKey: .closest) ?? []
        progress = try c.decodeIfPresent(SemanticProgress.self, forKey: .progress)
        aiTidy = try c.decodeIfPresent(AiTidy.self, forKey: .aiTidy)
    }
}

/// `done` of `total` items read by the local model ("Local AI: 1,240 of 2,980 items").
public struct SemanticProgress: Codable, Sendable, Equatable {
    public var done: Int
    public var total: Int
    public init(done: Int, total: Int) {
        self.done = done
        self.total = total
    }
}

/// `SemanticView.ai_tidy` (AinkradCore #248): the Core's own tidy of the proposal, `applied` or `undone`.
public struct AiTidy: Codable, Sendable, Equatable {
    public var state: String?
    public var summary: TidySummary?
    enum CodingKeys: String, CodingKey { case state, summary }
    public init(state: String? = "applied", summary: TidySummary? = nil) {
        self.state = state
        self.summary = summary
    }
}

/// The counts of the tidy. Rooms do not count Unsorted.
public struct TidySummary: Codable, Sendable, Equatable {
    public var duplicatesMerged: Int?
    public var roomsMerged: Int?
    public var roomsFolded: Int?
    public var itemsMoved: Int?
    public var roomsBefore: Int?
    public var roomsAfter: Int?
    enum CodingKeys: String, CodingKey {
        case duplicatesMerged = "duplicates_merged"
        case roomsMerged = "rooms_merged"
        case roomsFolded = "rooms_folded"
        case itemsMoved = "items_moved"
        case roomsBefore = "rooms_before"
        case roomsAfter = "rooms_after"
    }
    public init(
        duplicatesMerged: Int? = nil, roomsMerged: Int? = nil, roomsFolded: Int? = nil, itemsMoved: Int? = nil,
        roomsBefore: Int? = nil, roomsAfter: Int? = nil
    ) {
        self.duplicatesMerged = duplicatesMerged
        self.roomsMerged = roomsMerged
        self.roomsFolded = roomsFolded
        self.itemsMoved = itemsMoved
        self.roomsBefore = roomsBefore
        self.roomsAfter = roomsAfter
    }
}

/// `GET /imports/{run}/semantic/changes`.
public struct TidyChanges: Codable, Sendable, Equatable {
    public var changes: [TidyChange]
    public init(changes: [TidyChange]) { self.changes = changes }
    public init(from d: any Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        changes = try c.decodeIfPresent([TidyChange].self, forKey: .changes) ?? []
    }
}

/// One change. `duplicate`: `itemIds` merged into the kept item `to`. `merge`: room `from` into room `to`. `fold`: tiny
/// room `from` into room `to` or `unsorted`. `move`: the Unsorted item `itemIds[0]` into room `to`.
public struct TidyChange: Codable, Sendable, Equatable {
    public var kind: String
    public var itemIds: [String]
    public var from: String?
    public var fromName: String?
    public var to: String
    public var toName: String?
    /// Titles of `itemIds`, same order; `toTitle` is the kept copy's (duplicate only). Absent on an older #248.
    public var itemTitles: [String]?
    public var toTitle: String?
    enum CodingKeys: String, CodingKey {
        case kind, from, to
        case itemIds = "item_ids"
        case fromName = "from_name"
        case toName = "to_name"
        case itemTitles = "item_titles"
        case toTitle = "to_title"
    }
    public init(
        kind: String, itemIds: [String] = [], from: String? = nil, fromName: String? = nil, to: String,
        toName: String? = nil, itemTitles: [String]? = nil, toTitle: String? = nil
    ) {
        self.kind = kind
        self.itemIds = itemIds
        self.from = from
        self.fromName = fromName
        self.to = to
        self.toName = toName
        self.itemTitles = itemTitles
        self.toTitle = toTitle
    }
    public init(from d: any Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        itemIds = try c.decodeIfPresent([String].self, forKey: .itemIds) ?? []
        from = try c.decodeIfPresent(String.self, forKey: .from)
        fromName = try c.decodeIfPresent(String.self, forKey: .fromName)
        to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
        toName = try c.decodeIfPresent(String.self, forKey: .toName)
        itemTitles = try c.decodeIfPresent([String].self, forKey: .itemTitles)
        toTitle = try c.decodeIfPresent(String.self, forKey: .toTitle)
    }

    /// The title the Core sent for the item this change is about (the kept copy, or the moved item), if any.
    public var sentTitle: String? {
        let t = kind == "duplicate" ? toTitle : kind == "move" ? itemTitles?.first : nil
        return t.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Items with nearly the same text. Accepting refuses `itemIds` except `keep` (the newest).
public struct DuplicateHint: Codable, Sendable, Equatable {
    public var keep: String
    public var itemIds: [String]
    public var score: Double
    public var reason: String
    enum CodingKeys: String, CodingKey {
        case keep, score, reason
        case itemIds = "item_ids"
    }
    public init(keep: String, itemIds: [String], score: Double, reason: String = "") {
        self.keep = keep
        self.itemIds = itemIds
        self.score = score
        self.reason = reason
    }
}

/// A topic among the Unsorted items. Accepting splits Unsorted into a room called `name`.
public struct RoomHint: Codable, Sendable, Equatable {
    public var name: String
    public var keywords: [String]
    public var itemIds: [String]
    public var score: Double
    enum CodingKeys: String, CodingKey {
        case name, keywords, score
        case itemIds = "item_ids"
    }
    public init(name: String, keywords: [String], itemIds: [String], score: Double) {
        self.name = name
        self.keywords = keywords
        self.itemIds = itemIds
        self.score = score
    }
}

/// Two rooms that look like one topic; `from` is the smaller. `fromName` or `toName` is nil when that side is a
/// suggested room, not a proposal yet, so there is nothing to merge.
public struct MergeHint: Codable, Sendable, Equatable {
    public var from: String
    public var to: String
    public var fromName: String?
    public var toName: String?
    public var score: Double
    public var reason: String
    enum CodingKeys: String, CodingKey {
        case from, to, score, reason
        case fromName = "from_name"
        case toName = "to_name"
    }
    public init(
        from: String, to: String, fromName: String?, toName: String?, score: Double, reason: String = ""
    ) {
        self.from = from
        self.to = to
        self.fromName = fromName
        self.toName = toName
        self.score = score
        self.reason = reason
    }
}

/// The room one item looks closest to. `roomId` is a proposal of this run when `inReview`, else a room already filed.
/// Matches AinkradCore `ClosestHint` (feat/brain-closest-room, 5ef2ca88): scores are 0 to 1, `runner_up` may be absent.
public struct ClosestHint: Codable, Sendable, Equatable {
    public var itemId: String
    public var roomId: String
    public var roomName: String
    public var inReview: Bool
    public var score: Double
    public var runnerUp: ClosestRunnerUp?
    enum CodingKeys: String, CodingKey {
        case score
        case itemId = "item_id"
        case roomId = "room_id"
        case roomName = "room_name"
        case inReview = "in_review"
        case runnerUp = "runner_up"
    }
    public init(
        itemId: String, roomId: String, roomName: String, inReview: Bool, score: Double,
        runnerUp: ClosestRunnerUp? = nil
    ) {
        self.itemId = itemId
        self.roomId = roomId
        self.roomName = roomName
        self.inReview = inReview
        self.score = score
        self.runnerUp = runnerUp
    }
}

public struct ClosestRunnerUp: Codable, Sendable, Equatable {
    public var roomId: String
    public var roomName: String
    public var score: Double
    enum CodingKeys: String, CodingKey {
        case score
        case roomId = "room_id"
        case roomName = "room_name"
    }
    public init(roomId: String, roomName: String, score: Double) {
        self.roomId = roomId
        self.roomName = roomName
        self.score = score
    }
}

/// One Brain tunable (`GET /settings`).
public struct BrainSettingWire: Codable, Sendable, Equatable {
    public var name: String
    public var value: Int
    public var `default`: Int
    public var min: Int
    public var max: Int
    public var description: String
}

struct SettingBody: Encodable { var value: Int }
