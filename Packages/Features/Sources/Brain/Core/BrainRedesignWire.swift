import Foundation

// The Brain redesign's routes (Core API minor 101, Docs/Specs/2026-11-23-brain-redesign-contract.md). Every call here is
// gated on `coreMinorBrainRedesign`; an older Core never sees one, and the screens fall back to what it has.

/// The API minor that serves the redesign's routes and fields.
public let coreMinorBrainRedesign = 101
/// The API minor from which the Core writes and refreshes place overviews by itself (`card_at`, `card_pending`).
public let coreMinorAutoOverview = 102

/// `GET /places`: one row per place, the private About you place included.
public struct PlaceWire: Codable, Sendable, Equatable, Identifiable {
    public var room: String
    public var name: String
    public var knowledge: Int
    public var rules: Int
    public var timeline: Int
    public var lastLearnedAt: String?
    public var learning: Bool
    public var locked: Bool
    public var id: String { room }
    public var total: Int { knowledge + rules + timeline }
    enum CodingKeys: String, CodingKey {
        case room, name, knowledge, rules, timeline, learning, locked
        case lastLearnedAt = "last_learned_at"
    }
}

/// `GET /topics`: what Knowledge is most about, from the records' tags.
public struct TopicWire: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var count: Int
    public var example: String
    public var rooms: [String]
    public var id: String { name }
}

struct AskBody: Encodable {
    var q: String
    var room: String?
}

/// `POST /ask`: a written answer when an AI account and a runner are there (nil otherwise), and the records it rests on.
public struct AskWire: Codable, Sendable, Equatable {
    public var answer: String?
    public var sources: [Source]
    public struct Source: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var room: String
        public var roomName: String
        public var type: String
        public var body: String
        enum CodingKeys: String, CodingKey {
            case id, room, type, body
            case roomName = "room_name"
        }
    }
}

/// `GET /activity/days`: newest day first, what Brain learned and tidied, and what it did in counts.
public struct ActivityDaysWire: Codable, Sendable, Equatable {
    public var days: [Day]
    public struct Day: Codable, Sendable, Equatable, Identifiable {
        /// `YYYY-MM-DD`, the Core's local day.
        public var day: String
        public var learned: Int
        public var tidied: Int
        public var events: [Event]
        public var id: String { day }
    }
    public struct Event: Codable, Sendable, Equatable {
        /// `learned`, `tidied`, `merged`, `overview`, `asked` or `imported`.
        public var kind: String
        public var count: Int
        public var rooms: [String]
        public var tookS: Int?
        enum CodingKeys: String, CodingKey {
            case kind, count, rooms
            case tookS = "took_s"
        }
    }
}

struct FollowBody: Encodable { var on: Bool }
struct FollowWire: Decodable { var following: Bool? }

/// What `POST /areas/rules` wrote: one record per place, and how many places already had it.
struct WrittenWire: Decodable {
    var written: [Place]
    var skipped: Int
    struct Place: Decodable {
        var id: String
        var room: String
        var name: String
    }
}

/// `POST /areas/rules`: a rule written by the person. `rooms` is a list of room ids, or the word `everywhere`.
struct NewRuleBody: Encodable {
    var body: String
    var kind: String
    var rooms: [String]?

    func encode(to e: any Encoder) throws {
        var c = e.container(keyedBy: AnyKey.self)
        try c.encode(body, forKey: AnyKey("body"))
        try c.encode(kind, forKey: AnyKey("kind"))
        if let rooms {
            try c.encode(rooms, forKey: AnyKey("rooms"))
        } else {
            try c.encode("everywhere", forKey: AnyKey("rooms"))
        }
    }
}

extension BrainRoutes {
    public func places() async throws -> [PlaceWire] { try await call("GET", "/places") }
    public func topics(limit: Int = 8) async throws -> [TopicWire] { try await call("GET", "/topics?limit=\(limit)") }
    public func ask(_ q: String, room: String? = nil) async throws -> AskWire {
        try await call("POST", "/ask", AskBody(q: q, room: room))
    }
    public func activityDays(_ days: Int = 14) async throws -> ActivityDaysWire {
        try await call("GET", "/activity/days?days=\(days)")
    }
    /// An area's records narrowed by rule kind, Knowledge topic, place or words (the filters of API minor 101).
    public func area(
        _ area: String, kind: String? = nil, topic: String? = nil, room: String? = nil, q: String? = nil,
        type: String? = nil, limit: Int = 60
    ) async throws -> BrainAreaPageWire {
        var parts = ["limit=\(limit)"]
        for (k, v) in [("kind", kind), ("topic", topic), ("room", room), ("q", q), ("type", type)] {
            if let v, !v.isEmpty { parts.append("\(k)=\(Self.query(v))") }
        }
        return try await call("GET", "/areas/\(Self.seg(area))?" + parts.joined(separator: "&"))
    }
    public func follow(room: String, id: String, on: Bool) async throws {
        _ = try await call(
            "PUT", "/rooms/\(Self.seg(room))/records/\(Self.seg(id))/follow", FollowBody(on: on), as: FollowWire.self)
    }
    /// `rooms` nil writes it in every open place (one that has it already is skipped). Answers how many it wrote.
    @discardableResult
    public func newRule(_ body: String, kind: String, rooms: [String]?) async throws -> Int {
        try await call("POST", "/areas/rules", NewRuleBody(body: body, kind: kind, rooms: rooms), as: WrittenWire.self)
            .written.count
    }

    /// One query value, escaped so it can never add a parameter.
    static func query(_ s: String) -> String {
        s.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#?")))
            ?? s
    }
}
