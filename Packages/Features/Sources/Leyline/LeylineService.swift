import CoreKit
import Foundation

/// What the Leyline screens ask of the Core. The real one calls the module's routes under `/modules/leyline/v1` through the
/// paired connection (`CoreConnection.signedRequest`: the same signing, session and retries as every other call), the way the
/// Brain does; the Debug demo and the tests bring their own. Reads need `read`; every write is `admin`, and key import is a
/// step-up route, so the model runs the writes through the host's Touch ID.
protocol LeylineService: Sendable {
    func hosts() async throws -> [HostItem]
    func keys() async throws -> [KeyItem]
    /// Host keys pinned so far. TODO(Y2-02): no route yet, the live service answers none.
    func knownHosts() async throws -> [KnownHostItem]
    func createHost(_ draft: HostDraft) async throws -> HostItem
    func patchHost(_ id: String, _ patch: HostPatch) async throws -> HostItem
    func generateKey(name: String) async throws -> KeyItem
    func importKey(name: String, privateKey: String, passphrase: String?) async throws -> KeyItem
}

/// A new host, as the Add Host sheets fill it. Nothing optional is sent as null: the Core takes its defaults.
struct HostDraft: Equatable, Sendable, Encodable {
    var name: String
    var address: String
    var username: String
    var port: Int = 22
    var keyID: String?
    var jumpChain: [String] = []
    var viaRunner: String?
    var group: String?
    var tags: [String] = []
    var aiRule: AIRule = .ask

    enum CodingKeys: String, CodingKey {
        case name, address, username, port, tags, group
        case keyID = "key_id"
        case jumpChain = "jump_chain"
        case viaRunner = "via_runner"
        case aiRule = "ai_rule"
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(address, forKey: .address)
        try c.encode(username, forKey: .username)
        try c.encode(port, forKey: .port)
        try c.encodeIfPresent(keyID, forKey: .keyID)
        try c.encode(jumpChain, forKey: .jumpChain)
        try c.encodeIfPresent(viaRunner, forKey: .viaRunner)
        try c.encodeIfPresent(group, forKey: .group)
        try c.encode(tags, forKey: .tags)
        try c.encode(aiRule.wire, forKey: .aiRule)
    }
}

/// A change to a host: only the fields named here are sent, and `.null` clears a nullable one (key, group, runner).
struct HostPatch: Equatable, Sendable, Encodable {
    enum Value: Equatable, Sendable, Encodable {
        case string(String)
        case int(Int)
        case strings([String])
        case null
        func encode(to encoder: any Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .string(let s): try c.encode(s)
            case .int(let n): try c.encode(n)
            case .strings(let a): try c.encode(a)
            case .null: try c.encodeNil()
            }
        }
    }
    var fields: [String: Value] = [:]

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        for (k, v) in fields.sorted(by: { $0.key < $1.key }) { try c.encode(v, forKey: AnyKey(k)) }
    }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    static func rule(_ r: AIRule) -> HostPatch { HostPatch(fields: ["ai_rule": .string(r.wire)]) }

    /// Everything the edit sheet owns, so a field cleared in the sheet is cleared on the Core.
    static func edit(_ d: HostDraft) -> HostPatch {
        HostPatch(fields: [
            "name": .string(d.name), "address": .string(d.address), "username": .string(d.username),
            "port": .int(d.port), "key_id": d.keyID.map { .string($0) } ?? .null,
            "jump_chain": .strings(d.jumpChain), "via_runner": d.viaRunner.map { .string($0) } ?? .null,
            "group": d.group.map { .string($0) } ?? .null, "tags": .strings(d.tags),
        ])
    }
}

/// A failure the screens can word. `code` is for hover help only.
struct LeylineFailure: Error, Equatable, Sendable {
    let sentence: String
    let code: String
    var status = 0
}

struct LiveLeylineService: LeylineService {
    let connection: CoreConnection
    static let base = "/modules/leyline/v1"

    func hosts() async throws -> [HostItem] { try await call("GET", "/hosts", as: [HostWire].self).map(\.item) }
    func keys() async throws -> [KeyItem] { try await call("GET", "/keys", as: [KeyWire].self).map(\.item) }
    func knownHosts() async throws -> [KnownHostItem] { [] }
    func createHost(_ draft: HostDraft) async throws -> HostItem {
        try await call("POST", "/hosts", draft, as: HostWire.self).item
    }
    func patchHost(_ id: String, _ patch: HostPatch) async throws -> HostItem {
        try await call("PATCH", "/hosts/\(Self.seg(id))", patch, as: HostWire.self).item
    }
    func generateKey(name: String) async throws -> KeyItem {
        try await call("POST", "/keys", ["name": name], as: KeyWire.self).item
    }
    func importKey(name: String, privateKey: String, passphrase: String?) async throws -> KeyItem {
        struct Body: Encodable {
            let name: String
            let privateKey: String
            let passphrase: String?
            enum CodingKeys: String, CodingKey {
                case name, passphrase
                case privateKey = "private_key"
            }
        }
        return try await call(
            "POST", "/keys/import", Body(name: name, privateKey: privateKey, passphrase: passphrase),
            as: KeyWire.self
        ).item
    }

    private func call<T: Decodable>(_ method: String, _ path: String, _ body: (any Encodable)? = nil, as: T.Type)
        async throws -> T
    {
        let data: Data
        do {
            data = try await connection.signedRequest(
                method: method, target: Self.base + path, body: try body.map { try JSONEncoder().encode($0) } ?? Data())
        } catch CoreError.http(let status, let code, let message) {
            throw Self.failure(status: status, code: code, message: message)
        } catch CoreError.badRequest(let message) {
            throw Self.failure(status: 400, code: "bad_request", message: message)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) } catch {
            throw LeylineFailure(sentence: "The Core answered something this app does not know.", code: "bad_answer")
        }
    }

    /// One path segment, escaped so an id can never add a slash or a query.
    static func seg(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#")))
            ?? s
    }

    /// The Core says only "invalid" for a field it refuses, so the words come from the status.
    static func failure(status: Int, code: String, message: String) -> LeylineFailure {
        switch status {
        case 400:
            LeylineFailure(
                sentence: "The Core refused one of the fields. Check them and try again.", code: code, status: status)
        case 404, 501: LeylineFailure(sentence: "This Core does not have Leyline yet.", code: code, status: status)
        case 409: LeylineFailure(sentence: "That name is already taken. Pick another.", code: code, status: status)
        default:
            LeylineFailure(sentence: message.isEmpty ? "The Core refused that." : message, code: code, status: status)
        }
    }
}

// MARK: wire

struct HostWire: Decodable {
    let id: String
    let name: String
    let address: String
    let port: Int
    let username: String
    let keyId: String?
    let jumpChain: [String]
    let viaRunner: String?
    let group: String?
    let tags: [String]
    let aiRule: String
    let os: String?
    let createdAt: String

    var item: HostItem {
        HostItem(
            id: id, name: name, address: address, port: port, username: username, keyID: keyId,
            jumpChain: jumpChain, viaRunner: viaRunner, group: group, tags: tags, aiRule: AIRule(wire: aiRule),
            os: os, createdAt: Self.date(createdAt))
    }

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

struct KeyWire: Decodable {
    let id: String
    let name: String
    let algo: String
    let publicKey: String
    let fingerprint: String
    let origin: String
    let createdAt: String

    var item: KeyItem {
        KeyItem(
            id: id, name: name, algo: algo, publicKey: publicKey, fingerprint: fingerprint,
            imported: origin == "imported", createdAt: HostWire.date(createdAt))
    }
}
