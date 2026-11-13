import AinkradClient
import CryptoKit
import Foundation
import LocalAuthentication
import OpenAPIRuntime
import OpenAPIURLSession

/// A paired device's connection to its Core: the generated `Client` with every request signed, the session kept alive, the
/// step-up exchange and the event stream. `open` makes no network call; the first request (or `connect`) runs the identity
/// proof, so a Core that is not the pinned one is refused before anything signed is sent.
public actor CoreConnection {
    /// The generated API client. Its requests are signed by the middleware. Errors the Core answers with (401, 403, 429) are
    /// thrown as `CoreError`, possibly wrapped by the client: use `CoreError.unwrapping`.
    public nonisolated let client: Client
    public nonisolated let identity: PairedIdentity
    public nonisolated let endpoint: CoreEndpoint
    let sessions: SessionManager
    let keyStore: any KeyStore
    let http: any CoreHTTP
    let makeSocket: @Sendable (URLRequest) -> any EventSocket
    let clock: any CoreClock
    /// The events socket's ping timing (tests make it fast).
    nonisolated let eventPing: EventPing

    /// A connection for the identity this device paired with. Throws `notPaired` before pairing.
    public static func open(keyStore: any KeyStore, clock: any CoreClock = SystemCoreClock()) throws -> CoreConnection {
        guard let identity = try keyStore.loadIdentity(), let key = try keyStore.key(.routine, reason: "") else {
            throw CoreError.notPaired
        }
        let endpoint = try CoreEndpoint(identity.endpoint)
        // Always CoreKit's own session: no redirects, no cookies, no cache.
        let session = makeCoreSession()
        let http = URLSessionHTTP(endpoint: endpoint, session: session)
        let transport = URLSessionTransport(configuration: .init(session: session))
        return CoreConnection(
            identity: identity, endpoint: endpoint, key: key, keyStore: keyStore, http: http, transport: transport,
            makeSocket: { URLSessionEventSocket(session.webSocketTask(with: $0)) }, clock: clock)
    }

    init(
        identity: PairedIdentity, endpoint: CoreEndpoint, key: any DeviceKey, keyStore: any KeyStore,
        http: any CoreHTTP, transport: any ClientTransport,
        makeSocket: @escaping @Sendable (URLRequest) -> any EventSocket,
        clock: any CoreClock, eventPing: EventPing = EventPing()
    ) {
        self.eventPing = eventPing
        let sessions = SessionManager(endpoint: endpoint, identity: identity, key: key, http: http, clock: clock)
        self.sessions = sessions
        self.identity = identity
        self.endpoint = endpoint
        self.keyStore = keyStore
        self.http = http
        self.makeSocket = makeSocket
        self.clock = clock
        self.client = Client(
            serverURL: endpoint.url, configuration: .init(dateTranscoder: .iso8601WithFractionalSeconds),
            transport: transport, middlewares: [SigningMiddleware(sessions: sessions)])
    }

    /// One signed request to a route the generated client does not cover (a module's, under `/modules/...`): the same
    /// signing, session and retry rules as every generated call, no new crypto. `target` is the path and raw query exactly
    /// as sent. Any non-2xx answer is thrown as `CoreError`. A body is JSON and at most 1 MiB (§4).
    public func signedRequest(method: String, target: String, body: Data = Data()) async throws -> Data {
        guard target.hasPrefix("/"), !target.hasPrefix("/handshake"), !target.hasPrefix("/pair") else {
            throw CoreError.invalidInput("\(target) is not a signed route")
        }
        guard body.count <= SigningMiddleware.maxBody else { throw CoreError.bodyTooLarge }
        return try await sessions.perform(method: method, target: target, body: body).body
    }

    /// Proves the Core, opens a session and keeps it fresh in the background.
    @discardableResult
    public func connect() async throws -> CoreSession {
        let s = try await sessions.currentSession()
        await sessions.startAutoRefresh()
        return s
    }

    /// The live session, refreshed past 80 % of its life.
    public func session() async throws -> CoreSession { try await sessions.currentSession() }

    /// Stops the background refresh. Event streams end with their consumers.
    public func close() async { await sessions.stopAutoRefresh() }

    /// Signs `message` with this device's routine key (the local terminal path's proof of possession).
    public func signWithRoutineKey(_ message: Data) async throws -> Data {
        try await sessions.signWithRoutineKey(message)
    }

    /// The API minor both sides speak (§14a), after the first handshake.
    public var negotiatedMinor: Int32? { get async { await sessions.negotiatedMinor } }

    /// Whether the Core serves `minor`: use only what the negotiated minor has.
    public func serverSupports(minor: Int32) async -> Bool {
        await sessions.lastProof?.supportedMinors?.contains(minor) ?? false
    }

    /// What the last handshake proved (the Core's version and minors).
    public var coreProof: CoreProof? { get async { await sessions.lastProof } }

    /// When the current session's elevation ends (§8), nil when it is not elevated.
    public var elevatedUntil: Date? {
        get async {
            guard let s = await sessions.session, let t = s.elevatedUntil, t > (await sessions.now()) else {
                return nil
            }
            return Date(timeIntervalSince1970: TimeInterval(t))
        }
    }

    /// Step-up (§8): a challenge for this session, signed by the `stepup` key (the OS asks for Touch ID or the passcode, with
    /// `reason` in the prompt), then the exchange. Returns when the elevation ends.
    @discardableResult
    public func stepUp(reason: String) async throws -> Date {
        guard let key = try keyStore.key(.stepup, reason: reason) else {
            throw CoreError.stepUpUnavailable("This device has no step-up key, so it cannot elevate.")
        }
        // One session for the whole exchange: the challenge is bound to it, and a refresh during the Touch ID prompt must not move
        // the proof to another session (the Core would refuse it and count the failure against the step-up budget).
        let sessionID = try await sessions.currentSession().id
        let ask = try await sessions.perform(
            method: "POST", target: "/api/v1/auth/step-up/challenge", inSession: sessionID)
        guard
            let challenge = (try? JSONSerialization.jsonObject(with: ask.body) as? [String: Any])?["challenge"]
                as? String, challenge.count == 43, Wire.unb64(challenge) != nil
        else { throw CoreError.protocolViolation("a step-up challenge that is not 32 bytes") }
        let message = Wire.stepUpMessage(
            coreFP: identity.coreFingerprint, deviceID: identity.deviceID, sessionID: sessionID, challenge: challenge)
        let signature: Data
        do { signature = try await offloaded { try key.sign(message) } } catch {
            throw Self.stepUpFailure(error)
        }
        let body = try JSONEncoder().encode(["challenge": challenge, "stepup_sig": Wire.b64(signature)])
        let done = try await sessions.perform(
            method: "POST", target: "/api/v1/auth/step-up", body: body, inSession: sessionID)
        guard
            let until = (try? JSONSerialization.jsonObject(with: done.body) as? [String: Any])?["elevated_until"]
                as? String, let t = Wire.parseTimestamp(until)
        else { throw CoreError.protocolViolation("a step-up answer without elevated_until") }
        await sessions.noteElevation(until: t, sessionID: sessionID)
        return Date(timeIntervalSince1970: TimeInterval(t))
    }

    /// A cancelled prompt is the user's choice; anything else is the Keychain or Secure Enclave failing.
    static func stepUpFailure(_ error: any Error) -> CoreError {
        isUserCancel(error)
            ? .stepUpCancelled
            : .keyStore("The Secure Enclave could not sign the step-up.")
    }

    /// `errSecUserCanceled`, `LAError.userCancel/appCancel/systemCancel`, or either wrapped by CryptoKit or as an underlying error.
    static func isUserCancel(_ error: any Error) -> Bool {
        let laCancels = [LAError.userCancel, .appCancel, .systemCancel].map(\.rawValue)
        if let ck = error as? CryptoKitError, case .underlyingCoreCryptoError(let code) = ck {
            return Int(code) == Int(errSecUserCanceled) || laCancels.contains(Int(code))
        }
        let ns = error as NSError
        if (ns.domain == LAError.errorDomain && laCancels.contains(ns.code))
            || (ns.domain == NSOSStatusErrorDomain && ns.code == Int(errSecUserCanceled))
        {
            return true
        }
        if let inner = ns.userInfo[NSUnderlyingErrorKey] as? any Error { return isUserCancel(inner) }
        return false
    }

    /// The events, as an `AsyncStream` (see `EventUpdate`): HTTP replay after `after` (default: from now), then the WebSocket,
    /// reconnecting with backoff and resuming from the last seq seen. It ends on revocation, on an identity mismatch, or when
    /// the consumer stops. A consumer that reads slowly gets backpressure: when the buffer is full the stream closes the socket,
    /// backs off and replays from the last seq it delivered, so no event is lost or repeated.
    public nonisolated func events(after: Int64? = nil) -> AsyncStream<EventUpdate> {
        events(after: after, bufferSize: 4096)
    }

    nonisolated func events(after: Int64?, bufferSize: Int) -> AsyncStream<EventUpdate> {
        let runner = EventRunner(
            sessions: sessions, endpoint: endpoint, clock: clock, makeSocket: makeSocket, timing: eventPing)
        return AsyncStream(bufferingPolicy: .bufferingOldest(bufferSize)) { continuation in
            let task = Task { await runner.run(after: after, into: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Runs a blocking call (a Touch ID prompt) off the cooperative pool.
func offloaded<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(with: Result { try work() })
        }
    }
}
