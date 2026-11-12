import Foundation

// Brain M3 routes on the Core's `brain` module (`modules/brain/api/openapi.core.json` on feat/brain-m3-core):
// a room's Inbox, its policy and its distillations. Runner history has no route there yet (see the TODOs).

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

/// One runner as the history route lists it. TODO(brain-m3-core): confirm route and fields (plan section 5).
struct RunnerHistoryWire: Codable {
    struct Tool: Codable {
        var id: String
        var name: String
        var found: Int?
        var on: Bool
    }
    var id: String
    var name: String
    var online: Bool
    var enabled: Bool
    var tools: [Tool]
    var items: Int?
    var lastRun: String?
    enum CodingKeys: String, CodingKey {
        case id, name, online, enabled, tools, items
        case lastRun = "last_run"
    }
}

struct RunnerHistoryPutBody: Encodable {
    var enabled: Bool
    var tools: [String]
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

    // TODO(brain-m3-core): confirm route. Not on feat/brain-m3-core yet; this is the plan's section 5 shape.
    func runnerHistory() async throws -> [RunnerHistoryWire] { try await call("GET", "/runners/history") }
    // TODO(brain-m3-core): confirm route. Step-up on turn on, asked for by the caller every time.
    func putRunnerHistory(_ id: String, enabled: Bool, tools: [String]) async throws -> RunnerHistoryWire {
        try await call("PUT", "/runners/\(Self.seg(id))/history", RunnerHistoryPutBody(enabled: enabled, tools: tools))
    }
}
