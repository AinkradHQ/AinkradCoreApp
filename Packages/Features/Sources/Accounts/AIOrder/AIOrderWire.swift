import CoreKit
import Foundation

// HAND-WRITTEN WIRE for Core 0.10 (E7-1, E7-2). The generated client does not know these routes yet; the coordinator runs
// `make clients` at integration and this file then shrinks to the mapping. Every call is gated by API minor 95.

/// One account of an order (`GET /api/v1/ai-order`).
struct AIOrderEntry: Codable, Equatable, Sendable {
    let account: Int64
    var provider: String?
    var harness: String?
    var model: String?
}

/// An agent's own order, the Advanced part.
struct AIOrderOverride: Codable, Equatable, Sendable {
    let agent: String
    var items: [AIOrderEntry]
}

struct AIOrderDoc: Codable, Equatable, Sendable {
    var items: [AIOrderEntry]
    var overrides: [AIOrderOverride] = []

    init(items: [AIOrderEntry], overrides: [AIOrderOverride] = []) {
        self.items = items
        self.overrides = overrides
    }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        items = try c.decode([AIOrderEntry].self, forKey: .items)
        overrides = try c.decodeIfPresent([AIOrderOverride].self, forKey: .overrides) ?? []
    }
    private enum Keys: String, CodingKey { case items, overrides }
}

/// `PUT /api/v1/ai-order` and `PUT /api/v1/ai-order/agents/{agent}`: the whole list, 1 to 16 accounts.
struct AIOrderPut: Codable, Equatable, Sendable {
    static let maxItems = 16
    struct Item: Codable, Equatable, Sendable {
        let account: Int64
        var model: String?
    }
    var items: [Item]
}

/// `GET /api/v1/accounts/{id}/models`, read leniently: a list, or an object with `models`.
struct ModelListProbe: Decodable, Sendable {
    let count: Int
    private struct Row: Decodable {}
    private enum Keys: String, CodingKey { case models }
    init(from decoder: any Decoder) throws {
        if let rows = try? [Row](from: decoder) {
            count = rows.count
        } else {
            let c = try decoder.container(keyedBy: Keys.self)
            count = try c.decode([Row].self, forKey: .models).count
        }
    }
}

/// `GET /api/v1/accounts/logins/{id}` read for what the generated client does not know yet: the optional device `code`
/// (E7-4), and where the sign-in stands in plain terms, `stage` (`starting|open_url|enter_code|finishing|done|failed`)
/// with an optional `message`. Every field is optional: an older Core says none of them.
struct LoginExtra: Decodable, Equatable, Sendable {
    var code: String?
    var stage: String?
    var message: String?
    init(code: String? = nil, stage: String? = nil, message: String? = nil) {
        (self.code, self.stage, self.message) = (code, stage, message)
    }
    private enum Keys: String, CodingKey { case code, stage, message }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        code = try? c.decodeIfPresent(String.self, forKey: .code)
        stage = try? c.decodeIfPresent(String.self, forKey: .stage)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
    }
}

extension AccountsService {
    func aiOrderSupported() async -> Bool { false }
    func aiOrder() async throws -> AIOrderDoc { throw CoreError.invalidInput("The AI order needs a newer Core.") }
    func setAIOrder(agent: String?, items: [AIOrderPut.Item]) async throws -> AIOrderDoc {
        throw CoreError.invalidInput("The AI order needs a newer Core.")
    }
    func clearAIOrder(agent: String) async throws {
        throw CoreError.invalidInput("The AI order needs a newer Core.")
    }
    func modelCount(account: Int64) async -> Int? { nil }
    func loginExtra(_ id: String) async -> LoginExtra { LoginExtra() }
}

extension LiveAccountsService {
    func aiOrderSupported() async -> Bool { await connection.serverSupports(minor: coreMinorV010) }

    func aiOrder() async throws -> AIOrderDoc {
        try JSONDecoder().decode(
            AIOrderDoc.self, from: try await connection.signedRequest(method: "GET", target: "/api/v1/ai-order"))
    }

    func setAIOrder(agent: String?, items: [AIOrderPut.Item]) async throws -> AIOrderDoc {
        let path = agent.map { "/api/v1/ai-order/agents/\(Self.segment($0))" } ?? "/api/v1/ai-order"
        let body = try JSONEncoder().encode(AIOrderPut(items: items))
        return try JSONDecoder().decode(
            AIOrderDoc.self, from: try await connection.signedRequest(method: "PUT", target: path, body: body))
    }

    func clearAIOrder(agent: String) async throws {
        _ = try await connection.signedRequest(
            method: "DELETE", target: "/api/v1/ai-order/agents/\(Self.segment(agent))")
    }

    func modelCount(account: Int64) async -> Int? {
        guard await aiOrderSupported(),
            let data = try? await connection.signedRequest(
                method: "GET", target: "/api/v1/accounts/\(account)/models")
        else { return nil }
        return (try? JSONDecoder().decode(ModelListProbe.self, from: data))?.count
    }

    func loginExtra(_ id: String) async -> LoginExtra {
        guard await aiOrderSupported(),
            let data = try? await connection.signedRequest(
                method: "GET", target: "/api/v1/accounts/logins/\(Self.segment(id))")
        else { return LoginExtra() }
        return (try? JSONDecoder().decode(LoginExtra.self, from: data)) ?? LoginExtra()
    }

    /// One path segment, percent-encoded (an agent id may hold `:`).
    static func segment(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/")))
            ?? s
    }
}
