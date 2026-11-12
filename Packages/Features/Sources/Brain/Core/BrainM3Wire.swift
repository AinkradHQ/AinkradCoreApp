import Foundation

// Brain M3 routes on the Core's `brain` module (`modules/brain/api/openapi.core.json` on feat/brain-m3-core):
// a room's Inbox, its policy and its distillations. Runner history is a source, `runner-<id>`, on `/sources`.

struct SourceRefWire: Decodable {
    var itemID: String
    var sourceKind: String
    var title: String
    var quote: String
    var startedAt: String
    var room: String?
    enum CodingKeys: String, CodingKey {
        case title, quote, room
        case itemID = "item_id"
        case sourceKind = "source_kind"
        case startedAt = "started_at"
    }
}

struct DistilledByWire: Decodable {
    var provider: String
    var account: String
}

struct InboxRecordWire: Decodable {
    var id: String
    var type: String
    var body: String
    var tags: [String]
    var sources: [SourceRefWire]
    var distilledAt: String
    var distilledBy: DistilledByWire?
    var tool: String?
    enum CodingKeys: String, CodingKey {
        case id, type, body, tags, sources, tool
        case distilledAt = "distilled_at"
        case distilledBy = "distilled_by"
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
    var tags: [String]?
}

struct PolicyAccountWire: Decodable {
    var name: String
    var provider: String
    var state: String
}

struct PolicyWire: Decodable {
    var model: String
    var autoAccept: [String]
    var minSources: Int
    var accounts: [PolicyAccountWire]
    var localModels: [String]
    enum CodingKeys: String, CodingKey {
        case model, accounts
        case autoAccept = "auto_accept"
        case minSources = "min_sources"
        case localModels = "local_models"
    }
}

struct PolicyPatchBody: Encodable {
    var model: String?
    var autoAccept: [String]?
    var minSources: Int?
    enum CodingKeys: String, CodingKey {
        case model
        case autoAccept = "auto_accept"
        case minSources = "min_sources"
    }
}

struct DistilWire: Decodable {
    var state: String
    var sources: Int
}

/// A runner as `GET /api/v1/runners` lists it; only what the history switch needs.
struct RunnerWire: Decodable {
    var id: String
    var name: String
    var policy: RunnerPolicyWire?
}

/// `PUT /api/v1/runners/{id}/policy` takes the whole policy, so the history flag is set on top of what is there.
struct RunnerPolicyWire: Codable {
    var terminals: Bool
    var agents: Bool
    var agentCapacity: Int
    var shareHistory: Bool?
    enum CodingKeys: String, CodingKey {
        case terminals, agents
        case agentCapacity = "agent_capacity"
        case shareHistory = "share_history"
    }
}

struct RunnerPolicyResult: Decodable {
    var restarting: Bool?
    init() {}
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

    // The runner policy lives on the Core's own API, not under the Brain module.
    func runners() async throws -> [RunnerWire] {
        let data = try await transport.send("GET", "/api/v1/runners", body: nil)
        do { return try JSONDecoder().decode([RunnerWire].self, from: data) } catch {
            throw BrainHTTPError(status: 200, code: "bad_answer", message: "The Core's answer was not the runners'.")
        }
    }
    /// Step-up route: the caller asks for Touch ID around it.
    func setRunnerPolicy(_ id: String, _ body: RunnerPolicyWire) async throws -> RunnerPolicyResult {
        let data = try await transport.send(
            "PUT", "/api/v1/runners/\(Self.seg(id))/policy", body: try JSONEncoder().encode(body))
        return (try? JSONDecoder().decode(RunnerPolicyResult.self, from: data)) ?? RunnerPolicyResult()
    }
}
