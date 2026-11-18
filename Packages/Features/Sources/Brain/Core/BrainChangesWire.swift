import Foundation

// Change-set routes (B2-02) in `modules/brain/module/src/change_routes.rs` on AinkradCore `epic/brain`. Hand-written until
// the generated client is regenerated at the epic build.
// TODO(client-regen): replace these wire types and routes with the generated `brainChangeSets`, `brainChangeSet` and
// `brainUndoChange` calls at the epic build (CORE_COMMIT), then delete this file.

struct ChangeWire: Decodable {
    var id: String
    var kind: String
    var summary: String
    var at: String
    var undoneAt: String?
    var rows: Int
    enum CodingKeys: String, CodingKey {
        case id, kind, summary, at, rows
        case undoneAt = "undone_at"
    }
}

/// A record image: the `records` columns and `_sources`. Every field is optional so a later column cannot break the read.
struct ChangeImageWire: Decodable {
    var type: String?
    var body: String?
    var tags: [String]
    var sources: [String]
    enum CodingKeys: String, CodingKey {
        case type, body, tags
        case sources = "_sources"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try? c.decode(String.self, forKey: .type)
        body = try? c.decode(String.self, forKey: .body)
        // The Core stores tags as JSON text; accept the text or a real array.
        if let list = try? c.decode([String].self, forKey: .tags) {
            tags = list
        } else if let text = try? c.decode(String.self, forKey: .tags), let d = text.data(using: .utf8) {
            tags = (try? JSONDecoder().decode([String].self, from: d)) ?? []
        } else {
            tags = []
        }
        sources = (try? c.decode([String].self, forKey: .sources)) ?? []
    }
}

struct ChangeRowWire: Decodable {
    var seq: Int
    var record: String
    var before: ChangeImageWire?
    var after: ChangeImageWire?
}

struct ChangeDetailWire: Decodable {
    var rows: [ChangeRowWire]
    var more: Bool
}

struct UndoWire: Decodable {
    var restored: [String]
    var skipped: [String]
    var alreadyUndone: Bool
    enum CodingKeys: String, CodingKey {
        case restored, skipped
        case alreadyUndone = "already_undone"
    }
}

extension BrainRoutes {
    /// Newest first. `after` is the last change id of the page before.
    func changes(room: String, after: String?, limit: Int) async throws -> [ChangeWire] {
        let tail = after.map { "&after=\(Self.seg($0))" } ?? ""
        return try await call("GET", "/rooms/\(Self.seg(room))/changes?limit=\(limit)\(tail)")
    }
    func change(room: String, id: String, after: Int?, limit: Int) async throws -> ChangeDetailWire {
        let tail = after.map { "&after=\($0)" } ?? ""
        return try await call("GET", "/rooms/\(Self.seg(room))/changes/\(Self.seg(id))?limit=\(limit)\(tail)")
    }
    func undo(room: String, id: String) async throws -> UndoWire {
        try await call("POST", "/rooms/\(Self.seg(room))/changes/\(Self.seg(id))/undo")
    }
}
