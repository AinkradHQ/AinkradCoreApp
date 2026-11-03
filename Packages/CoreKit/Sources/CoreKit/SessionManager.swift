import AinkradClient
import Foundation

/// The API minor this build was made for (`info.version` of the vendored contract is `1.<minor>.0`).
public let builtForAPIMinor: Int32 = 33

/// A session (§6): a non-secret 15-minute handle, useless without a signature.
public struct CoreSession: Sendable, Equatable {
    public let id: String
    /// Unix seconds on the Core's clock.
    public let createdAt: Int64
    public let expiresAt: Int64
    public let scopes: [String]
    public var elevatedUntil: Int64?
}

/// Signs requests and keeps one live session: opens it (identity proof, challenge, session), refreshes it at 80 % of its life
/// with no user interaction, and reopens it after `session_expired` or a Core restart. It learns nothing from `clock_skew`
/// (the user is told, never silently re-signed). One refresh at a time; concurrent callers share it.
actor SessionManager {
    /// Refresh when this fraction of the session's life is gone.
    static let refreshFraction = 0.8

    let endpoint: CoreEndpoint
    let identity: PairedIdentity
    private let http: any CoreHTTP
    private let key: any DeviceKey
    private let clock: any CoreClock
    private(set) var session: CoreSession?
    private(set) var negotiatedMinor: Int32?
    private(set) var lastProof: CoreProof?
    private(set) var lastRefreshError: CoreError?
    /// No refresh attempt before this time (Core clock, unix seconds) after one failed: honours `Retry-After`, else backs off.
    private(set) var refreshNotBefore: Int64?
    private var failures = 0
    private var refreshing: Task<CoreSession, any Error>?
    private var autoRefresh: Task<Void, Never>?

    init(
        endpoint: CoreEndpoint, identity: PairedIdentity, key: any DeviceKey, http: any CoreHTTP, clock: any CoreClock
    ) {
        self.endpoint = endpoint
        self.identity = identity
        self.key = key
        self.http = http
        self.clock = clock
    }

    func now() -> Int64 { Int64(clock.now().timeIntervalSince1970) }

    // MARK: sessions

    func needsRefresh(_ s: CoreSession, at t: Int64) -> Bool {
        let life = Double(s.expiresAt - s.createdAt)
        return Double(t - s.createdAt) >= life * Self.refreshFraction
    }

    private func isLive(_ s: CoreSession) -> Bool { s.expiresAt - now() > 5 }

    /// A live session, refreshed when it is past 80 % of its life. After a failed refresh nothing is tried before the backoff
    /// deadline: a live session is kept, and with none the last error is thrown without touching the Core.
    func currentSession() async throws -> CoreSession {
        let t = now()
        if let s = session, !needsRefresh(s, at: t) { return s }
        if let until = refreshNotBefore, t < until {
            if let s = session, isLive(s) { return s }
            if let e = lastRefreshError { throw e }
        }
        return try await openSession()
    }

    /// Runs the identity proof, challenge and session exchange (once, however many callers ask; all of them get the same
    /// outcome, including the live old session when the refresh failed for a transient reason).
    func openSession() async throws -> CoreSession {
        let task: Task<CoreSession, any Error>
        let owner: Bool
        if let running = refreshing {
            task = running
            owner = false
        } else {
            task = Task { try await self.performOpen() }
            refreshing = task
            owner = true
        }
        defer { if owner { refreshing = nil } }
        do {
            let s = try await task.value
            if owner {
                lastRefreshError = nil
                refreshNotBefore = nil
                failures = 0
            }
            return s
        } catch let e as CoreError {
            if owner { recordFailure(e) }
            // A failed early refresh is not an outage while the old session still has time to run.
            if let old = session, isLive(old), Self.isTransient(e) { return old }
            throw e
        }
    }

    static func isTransient(_ e: CoreError) -> Bool {
        switch e {
        case .offline, .rateLimited, .coreUnproven: true
        default: false
        }
    }

    private func recordFailure(_ e: CoreError) {
        lastRefreshError = e
        failures += 1
        let backoff: Int64
        if case .rateLimited(let after?) = e {
            backoff = Int64(min(max(after, 1), 300))
        } else {
            backoff = min(60, Int64(5 << min(failures - 1, 3)))
        }
        refreshNotBefore = now() + backoff
    }

    /// Forget the session (it was refused), unless a newer one replaced it already.
    func invalidate(_ id: String?) {
        if let id, session?.id == id { session = nil }
    }

    func noteElevation(until: Int64, sessionID: String) {
        if var s = session, s.id == sessionID {
            s.elevatedUntil = until
            session = s
        }
    }

    private func performOpen() async throws -> CoreSession {
        let proof = try await CoreHandshake.prove(
            http: http, host: endpoint.host, pinned: identity.coreFingerprint)
        lastProof = proof
        do {
            negotiatedMinor = try negotiateMinor(builtFor: builtForAPIMinor, serverSupported: proof.supportedMinors)
        } catch let e as NoSharedMinor {
            throw CoreError.noSharedMinor(builtFor: e.builtFor, serverSupported: e.serverSupported)
        }
        let ask = try await post("/handshake/challenge", ["device_id": identity.deviceID], signed: false)
        guard
            let challenge = (try? JSONSerialization.jsonObject(with: ask.body) as? [String: Any])?["challenge"]
                as? String, challenge.count == 43, Wire.unb64(challenge) != nil
        else { throw CoreError.protocolViolation("a challenge that is not 32 bytes") }
        let granted = try await post("/handshake/session", ["challenge": challenge], signed: true)
        struct Grant: Decodable {
            var session_id: String?
            var expires_at: String?
            var scopes: [String]?
            var elevated_until: String?
        }
        guard let g = try? JSONDecoder().decode(Grant.self, from: granted.body), let id = g.session_id,
            id.hasPrefix("s_"), let exp = g.expires_at.flatMap(Wire.parseTimestamp)
        else { throw CoreError.protocolViolation("a session grant without an id or expiry") }
        let opened = CoreSession(
            id: id, createdAt: now(), expiresAt: exp, scopes: g.scopes ?? [],
            elevatedUntil: g.elevated_until.flatMap(Wire.parseTimestamp))
        session = opened
        return opened
    }

    /// A JSON `POST` to a pre-auth route; `signed` adds the signature with session `-` (`/handshake/session`, `/pair/status`).
    private func post(_ path: String, _ json: [String: String], signed: Bool) async throws -> RawResponse {
        try await perform(
            method: "POST", target: path, body: try JSONEncoder().encode(json), session: .none, signed: signed)
    }

    // MARK: signing

    enum Scope { case none, current }

    /// The `Ainkrad-*` headers for one request (§5.1). `sessionID` nil signs `-` and sends no `Ainkrad-Session`.
    func headers(method: String, target: String, body: Data, sessionID: String?) throws -> [String: String] {
        let (path, query) = Self.split(target)
        let ts = UInt64(max(0, now()))
        let nonce = Wire.nonce()
        let canonical = Wire.canonicalRequest(
            coreFP: identity.coreFingerprint, deviceID: identity.deviceID, sessionID: sessionID, method: method,
            path: path, query: query, timestamp: ts, nonce: nonce, body: body)
        let signature: Data
        do { signature = try key.sign(canonical) } catch { throw CoreError.keyStore("the routine key could not sign") }
        var h = [
            "ainkrad-device": identity.deviceID, "ainkrad-alg": Wire.alg, "ainkrad-timestamp": String(ts),
            "ainkrad-nonce": nonce, "ainkrad-signature": Wire.b64(signature),
        ]
        if let sessionID { h["ainkrad-session"] = sessionID }
        return h
    }

    /// The path and the raw query after `?`, as they are signed.
    static func split(_ target: String) -> (String, String) {
        guard let i = target.firstIndex(of: "?") else { return (target, "") }
        return (String(target[..<i]), String(target[target.index(after: i)...]))
    }

    /// What a refusal allows: one retry after `session_expired`. A `clock_skew` is never retried and never adopted: its
    /// `server_time` comes from an unauthenticated answer, so it is only shown to the user (as ctl does).
    struct Retried: OptionSet {
        let rawValue: Int
        static let session = Retried(rawValue: 2)
    }

    /// The retried set to continue with when the request should be sent again after `error`, else nil.
    func retry(after error: CoreError, sessionID: String?, retried: Retried) -> Retried? {
        guard case .sessionExpired = error, !retried.contains(.session) else { return nil }
        invalidate(sessionID)
        return retried.union(.session)
    }

    /// One signed request in exactly `sessionID`, no retries: for exchanges bound to one session (step-up).
    func perform(method: String, target: String, body: Data = Data(), inSession sessionID: String) async throws
        -> RawResponse
    {
        var request = RawRequest(method: method, target: target, body: body)
        if !body.isEmpty { request.headers["content-type"] = "application/json" }
        request.headers.merge(try headers(method: method, target: target, body: body, sessionID: sessionID)) { $1 }
        let res = try await http.send(request)
        if (200..<300).contains(res.status) { return res }
        throw CoreError.from(status: res.status, headers: res.headers, body: res.body)
    }

    /// One signed request through the retry rules. `signed: false` sends it bare (pre-auth routes).
    func perform(
        method: String, target: String, body: Data = Data(), session scope: Scope = .current, signed: Bool = true
    ) async throws -> RawResponse {
        var retried: Retried = []
        while true {
            var request = RawRequest(method: method, target: target, body: body)
            if !body.isEmpty { request.headers["content-type"] = "application/json" }
            var sessionID: String?
            if signed {
                sessionID = scope == .current ? try await currentSession().id : nil
                request.headers.merge(try headers(method: method, target: target, body: body, sessionID: sessionID)) {
                    $1
                }
            }
            let res = try await http.send(request)
            if (200..<300).contains(res.status) { return res }
            let error = CoreError.from(status: res.status, headers: res.headers, body: res.body)
            if signed, let next = retry(after: error, sessionID: sessionID, retried: retried) {
                retried = next
                continue
            }
            throw error
        }
    }

    // MARK: background refresh

    /// Refreshes the session at 80 % of its life, for as long as the app runs, with no user interaction. A revoked device or
    /// a Core that is not the pinned one stops it (`lastRefreshError` says why); anything else is retried with a pause.
    func startAutoRefresh() {
        guard autoRefresh == nil else { return }
        autoRefresh = Task { await self.autoRefreshLoop() }
    }

    func stopAutoRefresh() {
        autoRefresh?.cancel()
        autoRefresh = nil
    }

    private func autoRefreshLoop() async {
        while !Task.isCancelled {
            let t = now()
            var wait: Int64 = 15
            if let s = session {
                wait = max(1, s.createdAt + Int64(Double(s.expiresAt - s.createdAt) * Self.refreshFraction) - t)
            } else if lastRefreshError == nil {
                wait = 15
            }
            if let until = refreshNotBefore { wait = max(wait, until - t) }
            do { try await clock.sleep(for: .seconds(wait)) } catch { return }
            if Task.isCancelled { return }
            guard session != nil || lastRefreshError != nil else { continue }
            do {
                _ = try await openSession()
            } catch CoreError.coreIdentityMismatch, CoreError.authFailed, CoreError.noSharedMinor {
                return
            } catch is CancellationError {
                return
            } catch {
                continue  // the failure set the backoff deadline the next wait honours
            }
        }
    }
}
