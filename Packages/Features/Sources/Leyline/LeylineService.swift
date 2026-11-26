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

    // The host page (Y9-03). Each has a default that answers "not yet", so a stand-in only names what it fakes.
    /// Opens an interactive ssh terminal on the host; returns the Core terminal's id (`POST /hosts/{h}/terminals`).
    func openTerminal(host: String, rows: Int, cols: Int) async throws -> String
    func health(host: String) async throws -> HostHealth
    func commands() async throws -> [PresetCommand]
    /// Saves a one-step command for every host (`POST /commands`; a read-only one may ask for Touch ID).
    func createCommand(name: String, step: String, readOnly: Bool, confirm: Bool) async throws -> PresetCommand
    /// Runs a pre-set command on the host through the gate; returns the run's id.
    func runCommand(_ command: String, host: String, confirmed: Bool) async throws -> String
    func run(_ id: String, host: String, name: String) async throws -> CommandRun
    func files(host: String, path: String) async throws -> [RemoteFile]
    func download(host: String, path: String) async throws -> Data
    func upload(host: String, path: String, data: Data) async throws
    func history(host: String) async throws -> [HostEvent]
    func recording(_ id: String) async throws -> Recording
    func startDirect(host: String) async throws -> DirectLease
    func stopDirect(host: String) async throws
    /// The terminal sessions of the host and whether the Core is recording each (`GET /hosts/{h}/sessions`).
    func sessions(host: String) async throws -> [HostSession]
    /// Pauses the recording of a session (`POST /sessions/{s}/recording/pause`); no step-up needed.
    func pauseRecording(session: String) async throws
    /// Makes the host a runner (`POST /hosts/{h}/runner`, a step-up route): opens a terminal with the installer typed in.
    func makeRunner(host: String, rows: Int, cols: Int) async throws -> RunnerInstall
    /// Whether an address answers like an SSH server from the Core, and how fast (`POST /hosts/check`, API minor 95).
    func checkHost(address: String, port: Int) async throws -> HostCheck
    /// The host keys the Core knows for a host: `trusted`, `seen` (offered, waiting for a person) or `replaced`.
    func hostKeys(host: String) async throws -> [HostKeyItem]
    /// A person trusts a key the host offered (`POST /hosts/{h}/host-keys/trust`).
    func trustHostKey(host: String, fingerprint: String) async throws
    /// A person makes the key the host offered since the pin its only pin (`POST /hosts/{h}/host-keys/replace`, step-up).
    func replaceHostKey(host: String, fingerprint: String) async throws
}

/// One host key the Core knows for a host.
struct HostKeyItem: Equatable, Sendable, Decodable {
    let fingerprint: String
    let state: String
    var trustedAt: String?
}

/// The Core's answer to "does this address answer SSH?".
struct HostCheck: Equatable, Sendable {
    var ok: Bool
    var ms: Int?
    var reason: String?
}

extension LeylineService {
    func openTerminal(host: String, rows: Int, cols: Int) async throws -> String { throw LeylineFailure.notYet }
    func health(host: String) async throws -> HostHealth { throw LeylineFailure.notYet }
    func commands() async throws -> [PresetCommand] { throw LeylineFailure.notYet }
    func createCommand(name: String, step: String, readOnly: Bool, confirm: Bool) async throws -> PresetCommand {
        throw LeylineFailure.notYet
    }
    func runCommand(_ command: String, host: String, confirmed: Bool) async throws -> String {
        throw LeylineFailure.notYet
    }
    func run(_ id: String, host: String, name: String) async throws -> CommandRun { throw LeylineFailure.notYet }
    func files(host: String, path: String) async throws -> [RemoteFile] { throw LeylineFailure.notYet }
    func download(host: String, path: String) async throws -> Data { throw LeylineFailure.notYet }
    func upload(host: String, path: String, data: Data) async throws { throw LeylineFailure.notYet }
    func history(host: String) async throws -> [HostEvent] { throw LeylineFailure.notYet }
    func recording(_ id: String) async throws -> Recording { throw LeylineFailure.notYet }
    func startDirect(host: String) async throws -> DirectLease { throw LeylineFailure.notYet }
    func stopDirect(host: String) async throws { throw LeylineFailure.notYet }
    func sessions(host: String) async throws -> [HostSession] { throw LeylineFailure.notYet }
    func pauseRecording(session: String) async throws { throw LeylineFailure.notYet }
    func makeRunner(host: String, rows: Int, cols: Int) async throws -> RunnerInstall { throw LeylineFailure.notYet }
    func checkHost(address: String, port: Int) async throws -> HostCheck { throw LeylineFailure.notYet }
    func hostKeys(host: String) async throws -> [HostKeyItem] { throw LeylineFailure.notYet }
    func trustHostKey(host: String, fingerprint: String) async throws { throw LeylineFailure.notYet }
    func replaceHostKey(host: String, fingerprint: String) async throws { throw LeylineFailure.notYet }
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

    /// The Core has no route for this yet (404 or 501): the page says so instead of failing.
    var isMissing: Bool { status == 404 || status == 501 }
    static let notYet = LeylineFailure(
        sentence: "This Core cannot do that yet.", code: "not_yet", status: 501)
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

    /// The answer's bytes, as the Core sent them (a recording is a text file, not JSON).
    func raw(_ method: String, _ path: String, _ body: (any Encodable)? = nil) async throws -> Data {
        do {
            return try await connection.signedRequest(
                method: method, target: Self.base + path, body: try body.map { try JSONEncoder().encode($0) } ?? Data())
        } catch CoreError.http(let status, let code, let message) {
            throw Self.failure(status: status, code: code, message: message)
        } catch CoreError.badRequest(let message) {
            throw Self.failure(status: 400, code: "bad_request", message: message)
        }
    }

    func call<T: Decodable>(_ method: String, _ path: String, _ body: (any Encodable)? = nil, as: T.Type)
        async throws -> T
    {
        let data = try await raw(method, path, body)
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
        case 403 where code == "gate_refused":
            LeylineFailure(
                sentence: "Leyline refused that here. Check the host key and the AI rule on Access.", code: code,
                status: status)
        case 404, 501: LeylineFailure(sentence: "This Core does not have Leyline yet.", code: code, status: status)
        case 409 where code == "no_runner":
            LeylineFailure(sentence: "No runner can reach this host. Pick one on Access.", code: code, status: status)
        case 409 where code == "already_runner":
            LeylineFailure(sentence: "This host is already a runner.", code: code, status: status)
        case 409 where code == "host_not_trusted":
            LeylineFailure(
                sentence: "Trust the host key of every host on the way first (Access).", code: code, status: status)
        case 409 where code == "runner_cannot_ssh" || code == "runner_cannot_sftp":
            LeylineFailure(
                sentence: "This runner can’t open SSH. It’s offline, or it wasn’t started with --enable-exec.",
                code: code,
                status: status)
        case 409 where code == "out_of_order":
            LeylineFailure(sentence: "The upload got out of order. Try again.", code: code, status: status)
        case 413:
            LeylineFailure(sentence: "That file is larger than 64 MB.", code: code, status: status)
        case 502 where code == "host_unavailable" || code == "sftp_failed":
            LeylineFailure(sentence: "The host could not do that. Check it is reachable.", code: code, status: status)
        case 409 where code == "host_needs_key":
            LeylineFailure(sentence: "Give this host an ssh key first (Access).", code: code, status: status)
        case 409 where code.hasPrefix("host_key"):
            LeylineFailure(sentence: "The host key is not trusted yet. Check it on Access.", code: code, status: status)
        case 409 where code == "real_secret_refused":
            LeylineFailure(
                sentence:
                    "Your Core takes test keys only. To keep a real key, set Keys and secrets to Real in Settings → "
                    + "Feature switches.", code: code, status: status)
        case 409 where code == "secrets_disabled":
            LeylineFailure(
                sentence: "Keys and secrets is Off. Turn it on in Settings → Feature switches.", code: code,
                status: status)
        // Only the Core's own name clash is a taken name; any other refusal keeps its own words.
        case 409 where code == "conflict":
            LeylineFailure(sentence: "That name is already taken. Pick another.", code: code, status: status)
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
    let runnerDevice: String?
    struct Reach: Decodable {
        let up: Bool
        let latencyMs: Int?
        let checkedAt: String
        let seenAt: String?
    }
    struct Install: Decodable {
        let state: String
        let mode: String?
        let reason: String?
    }
    let reach: Reach?
    let runnerInstall: Install?

    var item: HostItem {
        var h = HostItem(
            id: id, name: name, address: address, port: port, username: username, keyID: keyId,
            jumpChain: jumpChain, viaRunner: viaRunner, group: group, tags: tags, aiRule: AIRule(wire: aiRule),
            os: os, createdAt: Self.date(createdAt), runnerDevice: runnerDevice)
        h.reach = reach.map {
            HostReach(
                up: $0.up, latencyMS: $0.latencyMs, checkedAt: Self.date($0.checkedAt),
                seenAt: $0.seenAt.flatMap(Self.date))
        }
        h.runnerInstall = runnerInstall.map { HostRunnerInstall(state: $0.state, mode: $0.mode, reason: $0.reason) }
        return h
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
    let bits: Int?
    let publicKey: String
    let fingerprint: String
    let origin: String
    let createdAt: String

    var item: KeyItem {
        KeyItem(
            id: id, name: name, algo: algo, publicKey: publicKey, fingerprint: fingerprint,
            imported: origin == "imported", createdAt: HostWire.date(createdAt), bits: bits)
    }
}
