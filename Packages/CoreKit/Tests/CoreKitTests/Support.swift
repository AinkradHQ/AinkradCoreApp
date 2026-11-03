import CryptoKit
import Foundation
import HTTPTypes
import OpenAPIRuntime

@testable import CoreKit

/// Virtual time: `sleep` advances the clock by the asked duration and records it, so refresh scheduling runs instantly.
// @unchecked Sendable: all state is under `lock`.
final class TestClock: CoreClock, @unchecked Sendable {
    private let lock = NSLock()
    private var t: Double
    private var asked: [Duration] = []
    init(unix: Int64 = 1_800_000_000) { t = Double(unix) }
    func now() -> Date { lock.withLock { Date(timeIntervalSince1970: t) } }
    var sleeps: [Duration] { lock.withLock { asked } }
    func advance(_ s: Double) { lock.withLock { t += s } }
    func sleep(for d: Duration) async throws {
        lock.withLock {
            asked.append(d)
            t += Double(d.components.seconds)
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}

func stamp(_ unix: Int64) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: Date(timeIntervalSince1970: TimeInterval(unix)))
}

func jsonBody(_ obj: Any) -> Data { try! JSONSerialization.data(withJSONObject: obj) }

/// A stand-in Core: it checks every signature as the real one does (§5.3, in the order that matters here), so the client's
/// signing, sessions and error handling run against something that refuses what the spec refuses.
// @unchecked Sendable: every request is handled under `lock`; the knobs are set by the test before or between calls.
final class FakeCore: CoreHTTP, @unchecked Sendable {
    struct Failure {
        var status: Int
        var code: String
        var headers: [String: String] = [:]
        var extra: [String: Any] = [:]
    }

    let clock: TestClock
    let host: String
    var coreKey = P256.Signing.PrivateKey()
    private let lock = NSLock()
    private var devices: [String: Data] = [:]  // device id -> routine spki
    private var challenges: Set<String> = []
    private var sessions: Set<String> = []
    private var nonces: Set<String> = []
    private(set) var log: [RawRequest] = []
    private(set) var sessionsIssued = 0
    /// Seconds the Core's clock is ahead of the client's.
    var serverOffset: Int64 = 0
    var handshakeStatus = 200
    var supportedMinors: [Int32]? = Array(0...33)
    /// A refusal to answer the next call to a path with.
    var failNext: [String: [Failure]] = [:]
    var latestSeq: Int64 = 0
    /// Successive retention floors: a replay from below the first is a 410 with it, and again until the client has caught up.
    var retentionFloors: [Int64] = []
    /// When set, `GET /api/v1/events` serves from this log by `after` and `limit`.
    var eventLog: [[String: Any]] = []
    var eventPages: [[String: Any]] = []
    var pairStatus = "active"
    var pairSASOverride: String?
    var stepupSPKI: Data?
    var elevatedUntil: Int64?
    private var lastStepUpChallenge: [String: String] = [:]  // session -> challenge

    var coreSPKI: Data { coreKey.publicKey.derRepresentation }
    var coreFP: String { Wire.fingerprint(spki: coreSPKI) }

    init(clock: TestClock, host: String = "127.0.0.1:7700") {
        self.clock = clock
        self.host = host
    }

    func register(device: String, spki: Data) { lock.withLock { devices[device] = spki } }
    func restart() {
        lock.withLock {
            sessions = []
            challenges = []
            nonces = []
        }
    }
    func signedRequests() -> Int { lock.withLock { log.filter { $0.headers["ainkrad-signature"] != nil }.count } }
    func requests(to path: String) -> [RawRequest] { lock.withLock { log.filter { $0.target.hasPrefix(path) } } }
    func fail(_ path: String, _ f: Failure) { lock.withLock { failNext[path, default: []].append(f) } }

    private var serverNow: Int64 { Int64(clock.now().timeIntervalSince1970) + serverOffset }

    private func respond(_ status: Int, _ obj: Any, headers: [String: String] = [:]) -> RawResponse {
        RawResponse(status: status, headers: headers, body: jsonBody(obj))
    }

    private func refuse(_ f: Failure) -> RawResponse {
        var body: [String: Any] = ["code": f.code, "message": "m", "error_id": "err_x"]
        for (k, v) in f.extra { body[k] = v }
        return respond(f.status, body, headers: f.headers)
    }

    func send(_ r: RawRequest) async throws -> RawResponse {
        await Task.yield()
        return lock.withLock { handle(r) }
    }

    /// Checks the signature, the clock, the replay cache and the session (§5.3). Nil when the request is good.
    private func authenticate(_ r: RawRequest, session required: Bool) -> (Failure?, String?, String?) {
        let h = r.headers
        guard h["authorization"] == nil, let device = h["ainkrad-device"], h["ainkrad-alg"] == "ES256",
            let ts = h["ainkrad-timestamp"].flatMap(Int64.init), let nonce = h["ainkrad-nonce"], nonce.count == 22,
            let sig = h["ainkrad-signature"].flatMap(Wire.unb64)
        else { return (Failure(status: 400, code: "bad_request"), nil, nil) }
        if required != (h["ainkrad-session"] != nil) { return (Failure(status: 400, code: "bad_request"), nil, nil) }
        if abs(serverNow - ts) > 60 {
            return (Failure(status: 401, code: "clock_skew", extra: ["server_time": serverNow]), nil, nil)
        }
        let parts = r.target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let canonical = Wire.canonicalRequest(
            coreFP: coreFP, deviceID: device, sessionID: h["ainkrad-session"], method: r.method, path: String(parts[0]),
            query: parts.count > 1 ? String(parts[1]) : "", timestamp: UInt64(ts), nonce: nonce, body: r.body)
        guard let spki = devices[device], Wire.verify(spki: spki, message: canonical, signature: sig),
            nonces.insert("\(device)|\(nonce)").inserted
        else { return (Failure(status: 401, code: "auth_failed"), nil, nil) }
        if required, !sessions.contains(h["ainkrad-session"] ?? "") {
            return (Failure(status: 401, code: "session_expired"), nil, nil)
        }
        return (nil, device, h["ainkrad-session"])
    }

    private func handle(_ r: RawRequest) -> RawResponse {
        log.append(r)
        let path = String(r.target.split(separator: "?")[0])
        if var q = failNext[path], !q.isEmpty {
            let f = q.removeFirst()
            failNext[path] = q
            return refuse(f)
        }
        let body = (try? JSONSerialization.jsonObject(with: r.body) as? [String: Any]) ?? [:]
        switch (r.method, path) {
        case ("POST", "/handshake"):
            guard handshakeStatus == 200 else { return respond(handshakeStatus, ["code": "not_found"]) }
            guard let nonce = body["nonce"] as? String else { return refuse(Failure(status: 400, code: "bad_request")) }
            let sig = try! coreKey.signature(for: Wire.coreProofMessage(host: host, nonce: nonce)).rawRepresentation
            var out: [String: Any] = [
                "core_spki": Wire.b64(coreSPKI), "core_sig": Wire.b64(sig), "server_version": "0.0.0", "api_minor": 33,
            ]
            if let m = supportedMinors { out["supported_minors"] = m }
            return respond(200, out)
        case ("POST", "/handshake/challenge"):
            let c = Wire.b64(Wire.randomBytes(32))
            challenges.insert(c)
            return respond(200, ["challenge": c, "expires_in": 60])
        case ("POST", "/handshake/session"):
            let (f, device, _) = authenticate(r, session: false)
            if let f { return refuse(f) }
            guard let c = body["challenge"] as? String, challenges.remove(c) != nil else {
                return refuse(Failure(status: 401, code: "auth_failed"))
            }
            let id = "s_" + Wire.b64(Wire.randomBytes(16)).prefix(26).lowercased()
            sessions.insert(String(id))
            sessionsIssued += 1
            _ = device
            return respond(
                200,
                [
                    "session_id": String(id), "expires_at": stamp(serverNow + 900), "scopes": ["read", "admin"],
                    "elevated_until": NSNull(),
                ])
        case ("POST", "/pair/claim"):
            return claim(body)
        case ("POST", "/pair/status"):
            let (f, _, _) = authenticate(r, session: false)
            if let f { return refuse(f) }
            return respond(200, ["status": pairStatus])
        case ("GET", "/api/v1/me"):
            let (f, device, _) = authenticate(r, session: true)
            if let f { return refuse(f) }
            let me: [String: Any] = [
                "device": ["id": device ?? "", "name": "Test Mac"],
                "versions": ["api": ["major": "v1", "minor": 33], "git_sha": "x", "server": "0.0.0"],
            ]
            return respond(200, me)
        case ("GET", "/api/v1/events/latest"):
            let (f, _, _) = authenticate(r, session: true)
            if let f { return refuse(f) }
            return respond(200, ["seq": latestSeq])
        case ("GET", "/api/v1/events"):
            let (f, _, _) = authenticate(r, session: true)
            if let f { return refuse(f) }
            if !eventLog.isEmpty || !retentionFloors.isEmpty {
                let after = r.target.split(separator: "?").last.flatMap { q in
                    q.split(separator: "&").first { $0.hasPrefix("after=") }.flatMap { Int64($0.dropFirst(6)) }
                }
                while let f = retentionFloors.first {
                    if (after ?? 0) < f {
                        return refuse(Failure(status: 410, code: "past_retention", extra: ["floor": f]))
                    }
                    retentionFloors.removeFirst()
                }
                return respond(200, ["items": eventLog.filter { ($0["seq"] as? Int64 ?? 0) > (after ?? 0) }])
            }
            return eventPages.isEmpty ? respond(200, ["items": []]) : respond(200, eventPages.removeFirst())
        case ("POST", "/api/v1/auth/step-up/challenge"):
            let (f, _, session) = authenticate(r, session: true)
            if let f { return refuse(f) }
            let c = Wire.b64(Wire.randomBytes(32))
            lastStepUpChallenge[session!] = c
            return respond(200, ["challenge": c])
        case ("POST", "/api/v1/auth/step-up"):
            let (f, device, session) = authenticate(r, session: true)
            if let f { return refuse(f) }
            guard let c = body["challenge"] as? String, lastStepUpChallenge[session!] == c,
                let sig = (body["stepup_sig"] as? String).flatMap(Wire.unb64), let spki = stepupSPKI,
                Wire.verify(
                    spki: spki,
                    message: Wire.stepUpMessage(coreFP: coreFP, deviceID: device!, sessionID: session!, challenge: c),
                    signature: sig)
            else { return refuse(Failure(status: 403, code: "step_up_failed")) }
            elevatedUntil = serverNow + 300
            return respond(200, ["elevated_until": stamp(elevatedUntil!)])
        default:
            return refuse(Failure(status: 404, code: "not_found"))
        }
    }

    private func claim(_ body: [String: Any]) -> RawResponse {
        guard let spki = (body["routine_spki"] as? String).flatMap(Wire.unb64),
            let pop = (body["pop"] as? String).flatMap(Wire.unb64)
        else { return refuse(Failure(status: 400, code: "bad_request")) }
        let hash: Data
        if let code = body["code"] as? String {
            hash = Wire.sha256(Data(code.utf8))
        } else if let secret = (body["secret"] as? String).flatMap(Wire.unb64) {
            hash = Wire.sha256(secret)
        } else {
            return refuse(Failure(status: 400, code: "bad_request"))
        }
        let stepupFP = (body["stepup_spki"] as? String).flatMap(Wire.unb64).map { Wire.fingerprint(spki: $0) }
        let message = Wire.popMessage(
            coreFP: coreFP, credentialHash: hash, routineFP: Wire.fingerprint(spki: spki), stepupFP: stepupFP)
        guard Wire.verify(spki: spki, message: message, signature: pop) else {
            return refuse(Failure(status: 401, code: "pairing_failed"))
        }
        if let s = (body["stepup_spki"] as? String).flatMap(Wire.unb64) {
            guard let ps = (body["pop_stepup"] as? String).flatMap(Wire.unb64),
                Wire.verify(spki: s, message: message, signature: ps)
            else { return refuse(Failure(status: 401, code: "pairing_failed")) }
            stepupSPKI = s
        }
        let device = "d_" + Wire.b64(Wire.randomBytes(16)).prefix(26).lowercased()
        devices[String(device)] = spki
        let pairing = "p_" + Wire.b64(Wire.randomBytes(16)).prefix(26).lowercased()
        let sas = pairSASOverride ?? Wire.sas(coreSPKI: coreSPKI, deviceSPKI: spki, pairingID: String(pairing))
        return respond(
            202,
            ["device_id": String(device), "core_spki": Wire.b64(coreSPKI), "pairing_id": String(pairing), "sas": sas])
    }
}

/// Routes the generated client's requests into a `FakeCore`.
struct FakeTransport: ClientTransport {
    let core: FakeCore
    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (
        HTTPResponse, HTTPBody?
    ) {
        var data = Data()
        if let body { data = try await Data(collecting: body, upTo: 1 << 20) }
        var headers: [String: String] = [:]
        for f in request.headerFields { headers[f.name.rawName.lowercased()] = f.value }
        let raw = RawRequest(method: request.method.rawValue, target: request.path ?? "", headers: headers, body: data)
        let res = try await core.send(raw)
        var out = HTTPResponse(status: .init(code: res.status))
        out.headerFields[.contentType] = "application/json"
        for (k, v) in res.headers { if let n = HTTPField.Name(k) { out.headerFields[n] = v } }
        return (out, HTTPBody(res.body))
    }
}

/// A paired device against a `FakeCore`: keys, identity registered, ready to connect.
struct Harness {
    let core: FakeCore
    let clock: TestClock
    let store: any KeyStore
    let key: any DeviceKey
    let identity: PairedIdentity

    init(host: String = "127.0.0.1:7700", pinned: String? = nil) throws {
        clock = TestClock()
        core = FakeCore(clock: clock, host: host)
        store = makeMemoryKeyStore()
        key = try store.generateKey(.routine)!
        identity = PairedIdentity(
            deviceID: "d_testdevice0000000000000000", coreFingerprint: pinned ?? core.coreFP,
            endpoint: URL(string: "http://\(host)")!)
        core.register(device: identity.deviceID, spki: key.spki)
        try store.saveIdentity(identity)
    }

    func sessions() throws -> SessionManager {
        SessionManager(
            endpoint: try CoreEndpoint(identity.endpoint), identity: identity, key: key, http: core, clock: clock)
    }

    func connection(sockets: SocketFactory = SocketFactory([.failPing])) throws -> CoreConnection {
        CoreConnection(
            identity: identity, endpoint: try CoreEndpoint(identity.endpoint), key: key, keyStore: store, http: core,
            transport: FakeTransport(core: core), makeSocket: { sockets.make($0) }, clock: clock)
    }
}

enum HTTPRequestShim {
    static func make() -> HTTPRequest { HTTPRequest(method: .post, scheme: nil, authority: nil, path: "/") }
}

/// A scripted WebSocket.
// @unchecked Sendable: state is under `lock`.
final class FakeSocket: EventSocket, @unchecked Sendable {
    enum Behavior {
        case failPing
        case closeWith(Int)
        case wait
    }
    let behavior: Behavior
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Data, any Error>?
    private var cancelledFlag = false
    init(_ b: Behavior) { behavior = b }
    var cancelled: Bool { lock.withLock { cancelledFlag } }
    func start() {}
    func ping() async throws { if case .failPing = behavior { throw URLError(.cannotConnectToHost) } }
    func receive() async throws -> Data {
        if case .closeWith = behavior { throw URLError(.networkConnectionLost) }
        return try await withCheckedThrowingContinuation { c in
            let done = lock.withLock { () -> Bool in
                if cancelledFlag { return true }
                waiter = c
                return false
            }
            if done { c.resume(throwing: URLError(.cancelled)) }
        }
    }
    func cancel() {
        let w = lock.withLock { () -> CheckedContinuation<Data, any Error>? in
            cancelledFlag = true
            defer { waiter = nil }
            return waiter
        }
        w?.resume(throwing: URLError(.cancelled))
    }
    var closeCode: Int { if case .closeWith(let c) = behavior { c } else { 0 } }
    var closeReason: String { "" }
    var responseStatus: Int? { nil }
}

/// Hands out scripted sockets in order; the last behaviour repeats.
// @unchecked Sendable: state is under `lock`.
final class SocketFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var script: [FakeSocket.Behavior]
    private(set) var made: [FakeSocket] = []
    init(_ script: [FakeSocket.Behavior]) { self.script = script }
    func make(_ request: URLRequest) -> any EventSocket {
        lock.withLock {
            let s = FakeSocket(script.count > 1 ? script.removeFirst() : script[0])
            made.append(s)
            return s
        }
    }
    var sockets: [FakeSocket] { lock.withLock { made } }
}
