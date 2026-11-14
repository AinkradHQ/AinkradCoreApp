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
    /// What the Core tidied by itself once the step finished. Absent on an older Core.
    public var tidy: TidyView?

    public init(
        state: String = "off", duplicates: [DuplicateHint] = [], rooms: [RoomHint] = [], merges: [MergeHint] = [],
        closest: [ClosestHint] = [], progress: SemanticProgress? = nil, tidy: TidyView? = nil
    ) {
        self.state = state
        self.duplicates = duplicates
        self.rooms = rooms
        self.merges = merges
        self.closest = closest
        self.progress = progress
        self.tidy = tidy
    }

    public init(from d: any Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "off"
        duplicates = try c.decodeIfPresent([DuplicateHint].self, forKey: .duplicates) ?? []
        rooms = try c.decodeIfPresent([RoomHint].self, forKey: .rooms) ?? []
        merges = try c.decodeIfPresent([MergeHint].self, forKey: .merges) ?? []
        closest = try c.decodeIfPresent([ClosestHint].self, forKey: .closest) ?? []
        progress = try c.decodeIfPresent(SemanticProgress.self, forKey: .progress)
        tidy = try c.decodeIfPresent(TidyView.self, forKey: .tidy)
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

/// What the Core changed by itself: the room count before and after, and every change by name.
public struct TidyView: Codable, Sendable, Equatable {
    public var before: Int
    public var after: Int
    public var changes: [TidyChange]
    public init(before: Int, after: Int, changes: [TidyChange]) {
        self.before = before
        self.after = after
        self.changes = changes
    }
}

/// One change. `kind` is `duplicate` (copies of `title` were left out), `fold` (the small room `title` went into
/// `into`) or `merge` (the room `title` joined `into`).
public struct TidyChange: Codable, Sendable, Equatable, Identifiable {
    public var kind: String
    public var title: String
    public var into: String?
    public var count: Int?
    public var id: String { "\(kind):\(title):\(into ?? "")" }
    public init(kind: String, title: String, into: String? = nil, count: Int? = nil) {
        self.kind = kind
        self.title = title
        self.into = into
        self.count = count
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
