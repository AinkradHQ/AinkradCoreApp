import Foundation

// Room care routes (B6-01 re-distil, B6-02 retention) in `modules/brain/module/src/{redistil_routes,retention}.rs` on
// AinkradCore `epic/brain`, and the room card. Hand-written until the generated client is regenerated at the epic build.
// TODO(client-regen): replace these wire types and routes with the generated `brainRetentionPreview`, `brainRedistil`,
// `brainRedistilDryRun`, `brainRedistilCancel` and `brainRedistils` calls at the epic build (CORE_COMMIT), then delete
// this file. The card route does not exist yet: see the Core proposal in the B10-02 PR.

struct RetentionPreviewWire: Decodable {
    var days: Int
    var wouldCompact: Int
    var chars: Int
    enum CodingKeys: String, CodingKey {
        case days, chars
        case wouldCompact = "would_compact"
    }
}

struct RedistilWire: Decodable {
    var id: String
    var dryRun: Bool
    var state: String
    var total: Int
    var read: Int
    var kept: Int?
    var newFacts: Int?
    var archived: Int?
    var summary: String?
    var change: String?
    var detail: String?
    enum CodingKeys: String, CodingKey {
        case id, state, total, read, kept, archived, summary, change, detail
        case dryRun = "dry_run"
        case newFacts = "new_facts"
    }
}

/// `GET /rooms/{room}/card` (proposed): what a session is told about the room, and how many records it holds.
struct CardWire: Decodable {
    var text: String
    var ids: [String]
    var complete: Bool
}

extension BrainRoutes {
    func retentionPreview(room: String, days: Int) async throws -> RetentionPreviewWire {
        try await call("GET", "/rooms/\(Self.seg(room))/retention?days=\(days)")
    }
    /// Step-up for the real run; the dry run needs none. Both answer the run.
    func redistil(room: String, dryRun: Bool) async throws -> RedistilWire {
        try await call("POST", "/rooms/\(Self.seg(room))/redistil" + (dryRun ? "/dry-run" : ""))
    }
    func cancelRedistil(room: String) async throws -> RedistilWire {
        try await call("POST", "/rooms/\(Self.seg(room))/redistil/cancel")
    }
    /// The room's last ten runs, newest first.
    func redistils(room: String) async throws -> [RedistilWire] {
        try await call("GET", "/rooms/\(Self.seg(room))/redistil")
    }
    func card(room: String) async throws -> CardWire {
        try await call("GET", "/rooms/\(Self.seg(room))/card")
    }
}
