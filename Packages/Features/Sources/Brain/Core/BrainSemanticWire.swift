import Foundation

/// `GET /imports/{run}/semantic`: the local model's sorting suggestions. Nothing here applies by itself.
public struct SemanticView: Codable, Sendable, Equatable {
    /// `pending` (working now), `ready` or `off`.
    public var state: String
    public var duplicates: [DuplicateHint]
    public var rooms: [RoomHint]
    public var merges: [MergeHint]

    public init(
        state: String = "off", duplicates: [DuplicateHint] = [], rooms: [RoomHint] = [], merges: [MergeHint] = []
    ) {
        self.state = state
        self.duplicates = duplicates
        self.rooms = rooms
        self.merges = merges
    }

    public init(from d: any Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? "off"
        duplicates = try c.decodeIfPresent([DuplicateHint].self, forKey: .duplicates) ?? []
        rooms = try c.decodeIfPresent([RoomHint].self, forKey: .rooms) ?? []
        merges = try c.decodeIfPresent([MergeHint].self, forKey: .merges) ?? []
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
