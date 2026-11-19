import Foundation

/// `GET /activity` (API minor 95): what the Brain is doing, in counts. The top-bar Brain icon polls it.
public struct BrainActivityWire: Codable, Sendable, Equatable {
    /// `locked`, `needs_you`, `working` or `idle`.
    public var state: String
    /// `ok` or `attention`.
    public var health: String
    public var rooms: Int
    public var distilling: Int
    public var queued: Int
    public var overviews: Int
    public var failed: Int
    public var needs: [Need]
    public var lastDoneAt: String?

    public struct Need: Codable, Sendable, Equatable {
        /// `unlock`, `ai_account`, `runner` or `local_model`.
        public var kind: String
        public var rooms: Int
    }

    enum CodingKeys: String, CodingKey {
        case state, health, rooms, distilling, queued, overviews, failed, needs
        case lastDoneAt = "last_done_at"
    }
}

/// `GET /areas` (API minor 95): the counts of Me, Rules, Knowledge and Timeline, plus Places and Evidence.
public struct BrainAreasWire: Codable, Sendable, Equatable {
    public var areas: [Summary]
    public var places: Int
    public var evidence: Int
    public var lockedRooms: Int

    public struct Summary: Codable, Sendable, Equatable, Identifiable {
        public var area: String
        public var count: Int
        public var today: Int
        public var latest: String?
        public var id: String { area }
    }

    enum CodingKeys: String, CodingKey {
        case areas, places, evidence
        case lockedRooms = "locked_rooms"
    }
}

/// One current record of an area, from any open room.
public struct BrainAreaRecordWire: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var room: String
    public var roomName: String
    public var type: String
    public var body: String
    public var tags: [String]
    public var support: Int
    public var createdAt: String
    public var seenAt: String

    enum CodingKeys: String, CodingKey {
        case id, room, type, body, tags, support
        case roomName = "room_name"
        case createdAt = "created_at"
        case seenAt = "seen_at"
    }
}

public struct BrainAreaPageWire: Codable, Sendable, Equatable {
    public var records: [BrainAreaRecordWire]
    public var total: Int
    public var lockedRooms: Int
    enum CodingKeys: String, CodingKey {
        case records, total
        case lockedRooms = "locked_rooms"
    }
}

/// An import the Core accepted by itself (D-26), with its Undo.
public struct AutoImportWire: Codable, Sendable, Equatable, Identifiable {
    public var run: String
    public var at: String
    public var rooms: Int
    public var id: String { run }
}

/// `GET /imports/{run}/learning`: the Learn step, per place, with the running cost.
public struct LearningWire: Codable, Sendable, Equatable {
    public var run: String
    public var places: [Place]
    public var totalCostUsdMicros: Int
    public var unpriced: Int
    public var done: Bool

    public struct Place: Codable, Sendable, Equatable, Identifiable {
        public var room: String
        public var name: String
        public var sources: Int
        public var read: Int
        public var learned: Int
        /// `pending`, `learning`, `waiting` or `done`.
        public var state: String
        public var provider: String?
        public var costUsdMicros: Int
        public var id: String { room }
        enum CodingKeys: String, CodingKey {
            case room, name, sources, read, learned, state, provider
            case costUsdMicros = "cost_usd_micros"
        }
    }

    enum CodingKeys: String, CodingKey {
        case run, places, unpriced, done
        case totalCostUsdMicros = "total_cost_usd_micros"
    }
}

struct UndoneWire: Decodable {
    var rooms: Int
    var items: Int?
}

extension BrainRoutes {
    /// API minor 95.
    public func activity() async throws -> BrainActivityWire { try await call("GET", "/activity") }
    public func areas() async throws -> BrainAreasWire { try await call("GET", "/areas") }
    /// `area` is `me`, `rules`, `knowledge` or `timeline`; `type` narrows to one record type.
    public func area(_ area: String, type: String? = nil, limit: Int = 50) async throws -> BrainAreaPageWire {
        var q = "?limit=\(limit)"
        if let type { q += "&type=\(Self.seg(type))" }
        return try await call("GET", "/areas/\(Self.seg(area))" + q)
    }
    public func autoImports() async throws -> [AutoImportWire] { try await call("GET", "/auto-imports") }
    /// Puts the sort back to one pile: archives the rooms the Core made for `run` and returns the run's items to Unsorted,
    /// open for review. Nothing is deleted. Returns the rooms archived and the items back in Unsorted.
    public func undoAutoImport(run: String) async throws -> (rooms: Int, items: Int) {
        let u = try await call("POST", "/auto-imports/\(Self.seg(run))/undo", as: UndoneWire.self)
        return (u.rooms, u.items ?? 0)
    }
    public func learning(run: String) async throws -> LearningWire {
        try await call("GET", "/imports/\(Self.seg(run))/learning")
    }
}
