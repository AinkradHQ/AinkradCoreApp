import Foundation

// Brain M3 routes on the Core's `brain` module (`modules/brain/api/openapi.core.json` on feat/brain-m3-core):
// a room's Inbox, its policy and its distillations. Runner history is a source, `runner-<id>`, on `/sources`.

struct InboxRecordWire: Decodable {
    var id: String
    var type: String
    var body: String
    var sources: [String]
    var createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, type, body, sources
        case createdAt = "created_at"
    }
}

struct InboxPageWire: Decodable {
    var items: [InboxRecordWire]
    var waiting: Int
}

struct DecisionBody: Encodable {
    var action: String
    var body: String?
    var type: String?
}

struct PolicyWire: Decodable {
    var model: String
    var allowedProviders: [String]
    var autoAccept: [String]
    enum CodingKeys: String, CodingKey {
        case model
        case allowedProviders = "allowed_providers"
        case autoAccept = "auto_accept"
    }
}

struct PolicyPatchBody: Encodable {
    var model: String?
    var autoAccept: [String]?
    enum CodingKeys: String, CodingKey {
        case model
        case autoAccept = "auto_accept"
    }
}

struct DistilWire: Decodable {
    var state: String
    var sources: Int
}

extension BrainRoutes {
    func inbox(room: String, limit: Int = 200) async throws -> InboxPageWire {
        try await call("GET", "/rooms/\(Self.seg(room))/inbox?status=candidate&limit=\(limit)")
    }
    func decide(room: String, id: String, _ body: DecisionBody) async throws -> InboxRecordWire {
        try await call("POST", "/rooms/\(Self.seg(room))/inbox/\(Self.seg(id))", body)
    }
    func policy(room: String) async throws -> PolicyWire { try await call("GET", "/rooms/\(Self.seg(room))/policy") }
    /// Step-up route: the caller asks for Touch ID around it.
    func patchPolicy(room: String, _ body: PolicyPatchBody) async throws -> PolicyWire {
        try await call("PATCH", "/rooms/\(Self.seg(room))/policy", body)
    }
    func distils(room: String) async throws -> [DistilWire] {
        try await call("GET", "/rooms/\(Self.seg(room))/distils")
    }
}
