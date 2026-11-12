import BrainImport
import Foundation

// Sync, sources, search and rules (`modules/brain/api/openapi.core.json`, M2). Counts, ids and titles only.

public struct RoutedWire: Codable, Sendable, Equatable {
    public var room: String
    public var sources: Int
}

/// What `POST /sync` answered. `idle` says why nothing ran: `nothing_new`, `disabled` or `running`.
public struct SyncResultWire: Codable, Sendable, Equatable {
    public var run: String?
    public var state: String?
    public var found = 0
    public var stored = 0
    public var duplicate = 0
    public var refused = 0
    public var rejected = 0
    public var routed: [RoutedWire] = []
    public var unsorted = 0
    public var newRooms = 0
    public var notice = false
    public var idle: String?
    enum CodingKeys: String, CodingKey {
        case run, state, found, stored, duplicate, refused, rejected, routed, unsorted, notice, idle
        case newRooms = "new_rooms"
    }
    public init() {}
    public init(from d: any Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        run = try c.decodeIfPresent(String.self, forKey: .run)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        found = try c.decodeIfPresent(Int.self, forKey: .found) ?? 0
        stored = try c.decodeIfPresent(Int.self, forKey: .stored) ?? 0
        duplicate = try c.decodeIfPresent(Int.self, forKey: .duplicate) ?? 0
        refused = try c.decodeIfPresent(Int.self, forKey: .refused) ?? 0
        rejected = try c.decodeIfPresent(Int.self, forKey: .rejected) ?? 0
        routed = try c.decodeIfPresent([RoutedWire].self, forKey: .routed) ?? []
        unsorted = try c.decodeIfPresent(Int.self, forKey: .unsorted) ?? 0
        newRooms = try c.decodeIfPresent(Int.self, forKey: .newRooms) ?? 0
        notice = try c.decodeIfPresent(Bool.self, forKey: .notice) ?? false
        idle = try c.decodeIfPresent(String.self, forKey: .idle)
    }

    /// The result in plain words, for the line under Sync now. `names` maps a room id to its name.
    public func summary(roomName names: (String) -> String? = { _ in nil }) -> String {
        switch idle {
        case "nothing_new": return "Nothing new."
        case "disabled": return "The Core's own AI sessions are switched off. Nothing was collected."
        case "running": return "A sync is already running."
        default: break
        }
        var s = "\(BrainWords.plural(found, "item", "items")) found, \(stored) kept, \(duplicate) already known"
        if refused + rejected > 0 { s += ", \(refused + rejected) skipped" }
        s += "."
        if !routed.isEmpty {
            let rooms = routed.map { names($0.room) ?? "a room" }
            s += " Added to \(rooms.joined(separator: ", "))."
        }
        if unsorted > 0 || newRooms > 0 {
            s += " Waiting for review: \(unsorted) unsorted, \(BrainWords.plural(newRooms, "new room", "new rooms"))."
        }
        return s
    }
}

/// One collector as `GET /sync` lists it.
public struct SyncSourceWire: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: String
    public var enabled: Bool
    public var lastRun: String?
    enum CodingKeys: String, CodingKey {
        case id, kind, enabled
        case lastRun = "last_run"
    }
}

public struct SyncStatusWire: Codable, Sendable, Equatable {
    public var everySecs: Int
    public var sources: [SyncSourceWire]
    /// Run ids waiting for review.
    public var review: [String]
    enum CodingKeys: String, CodingKey {
        case sources, review
        case everySecs = "every_secs"
    }
    public init(everySecs: Int = 3600, sources: [SyncSourceWire] = [], review: [String] = []) {
        self.everySecs = everySecs
        self.sources = sources
        self.review = review
    }
}

/// One collector with its switch, roots and cursor (`GET /sources`).
public struct SourceWire: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var device: String
    public var kind: String
    public var enabled: Bool
    public var roots: [String]
    public var cursor: SourceCursor
    public var lastRun: String?
    /// Items this source has stored. TODO(brain-m3-core): confirm the Core sends it on `/sources`; blank until then.
    public var items: Int?
    enum CodingKeys: String, CodingKey {
        case id, device, kind, enabled, roots, cursor, items
        case lastRun = "last_run"
    }
    public init(
        id: String, device: String, kind: String, enabled: Bool = true, roots: [String] = [],
        cursor: SourceCursor = .init(), lastRun: String? = nil, items: Int? = nil
    ) {
        self.items = items
        self.id = id
        self.device = device
        self.kind = kind
        self.enabled = enabled
        self.roots = roots
        self.cursor = cursor
        self.lastRun = lastRun
    }
    public init(from d: any Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        device = try c.decode(String.self, forKey: .device)
        kind = try c.decode(String.self, forKey: .kind)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        roots = try c.decodeIfPresent([String].self, forKey: .roots) ?? []
        // The cursor is the collector's own JSON; anything this build cannot read counts as "from the start".
        cursor = (try? c.decodeIfPresent(SourceCursor.self, forKey: .cursor)) ?? .init()
        lastRun = try c.decodeIfPresent(String.self, forKey: .lastRun)
        items = try c.decodeIfPresent(Int.self, forKey: .items)
    }

    /// The Core's own AI-session collector.
    public var isCore: Bool { id == "core_transcript" }
    /// Jira and GitHub, read by the Core through the accounts in Connections.
    public var isConnection: Bool { id == "jira" || id == "github" }
}

struct SourcePutBody: Encodable {
    var device: String
    var kind: String
    var enabled: Bool?
    var cursor: SourceCursor?
}

struct SyncBody: Encodable { var run: String? }

/// One hit of a room search. `snippet` marks matches with « ».
public struct SearchHit: Codable, Sendable, Equatable, Identifiable {
    public var itemID: String
    public var sourceKind: String
    public var title: String
    public var snippet: String
    public var startedAt: String
    public var id: String { itemID }
    enum CodingKeys: String, CodingKey {
        case title, snippet
        case itemID = "item_id"
        case sourceKind = "source_kind"
        case startedAt = "started_at"
    }
    public init(itemID: String, sourceKind: String, title: String, snippet: String, startedAt: String = "") {
        self.itemID = itemID
        self.sourceKind = sourceKind
        self.title = title
        self.snippet = snippet
        self.startedAt = startedAt
    }

    /// The snippet cut into runs: plain text and matched text, in order. An unclosed « matches to the end.
    public var pieces: [SnippetPiece] { Self.pieces(of: snippet) }

    public static func pieces(of s: String) -> [SnippetPiece] {
        var out: [SnippetPiece] = []
        var cur = ""
        var match = false
        for ch in s {
            if ch == "«" || ch == "»" {
                if !cur.isEmpty { out.append(SnippetPiece(text: cur, match: match)) }
                cur = ""
                match = ch == "«"
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { out.append(SnippetPiece(text: cur, match: match)) }
        return out
    }
}

public struct SnippetPiece: Sendable, Equatable {
    public var text: String
    public var match: Bool
}

struct SearchWire: Codable { var hits: [SearchHit] }

/// A rule as `GET /rules` lists it. Locked rules (the refused projects) cannot be switched.
public struct RuleWire: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var kind: String
    public var pattern: String
    public var action: String
    public var origin: String
    public var locked: Bool
    public var enabled: Bool
    public var reason: String
    public var room: String?
    public init(
        id: Int, kind: String = "path", pattern: String, action: String = "refuse", origin: String = "user",
        locked: Bool = false, enabled: Bool = true, reason: String = "", room: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.pattern = pattern
        self.action = action
        self.origin = origin
        self.locked = locked
        self.enabled = enabled
        self.reason = reason
        self.room = room
    }
}
struct RulePatchBody: Encodable { var enabled: Bool }

extension BrainRoutes {
    public func syncStatus() async throws -> SyncStatusWire { try await call("GET", "/sync") }
    public func sync(run: String? = nil) async throws -> SyncResultWire {
        try await call("POST", "/sync", SyncBody(run: run))
    }
    public func sources() async throws -> [SourceWire] { try await call("GET", "/sources") }
    /// Changes a source's switch and/or cursor; a nil field keeps the Core's value.
    public func putSource(_ s: SourceWire, enabled: Bool? = nil, cursor: SourceCursor? = nil) async throws
        -> SourceWire
    {
        try await call(
            "PUT", "/sources/\(Self.seg(s.id))",
            SourcePutBody(device: s.device, kind: s.kind, enabled: enabled, cursor: cursor))
    }
    public func search(room: String, query: String, limit: Int = 20) async throws -> [SearchHit] {
        let safe = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#"))
        let q = query.addingPercentEncoding(withAllowedCharacters: safe) ?? ""
        return try await call("GET", "/rooms/\(Self.seg(room))/search?q=\(q)&limit=\(limit)", as: SearchWire.self).hits
    }
    public func rules() async throws -> [RuleWire] { try await call("GET", "/rules") }
    /// Step-up route: the caller asks for Touch ID around it.
    public func setRule(_ id: Int, enabled: Bool) async throws -> RuleWire {
        try await call("PATCH", "/rules/\(id)", RulePatchBody(enabled: enabled))
    }
}
