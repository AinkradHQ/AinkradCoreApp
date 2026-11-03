import Foundation

/// Every way talking to the Core fails (spec §14), as one type. Nothing in here carries key material or a session secret.
public enum CoreError: Error, Equatable, Sendable {
    /// 401 `auth_failed`: unknown, pending, revoked or locked device, bad signature, replay, bad or used challenge.
    case authFailed
    /// 401 `clock_skew`, with the server's clock in unix seconds when it sent one.
    case clockSkew(serverTime: Int64?)
    /// 401 `session_expired`.
    case sessionExpired
    /// 403 `step_up_required`: the UI must elevate (§8) and retry.
    case stepUpRequired
    /// 403 `forbidden_scope`.
    case forbiddenScope
    /// 429 `rate_limited`, with `Retry-After` in seconds.
    case rateLimited(retryAfter: TimeInterval?)
    /// The Core did not prove the pinned identity (§13). Nothing signed was sent.
    case coreIdentityMismatch(pinned: String, served: String)
    /// The Core did not answer `POST /handshake` with a usable proof (non-200, malformed): this attempt fails closed and nothing
    /// signed is sent, but it is not evidence of a different Core, so callers retry with backoff.
    case coreUnproven(String)
    /// The client and the Core share no API minor (§14a).
    case noSharedMinor(builtFor: Int32, serverSupported: [Int32])
    /// The Core cannot be reached: no network, refused, TLS failure, timeout.
    case offline(String)
    /// 401 `pairing_failed`: wrong, used, expired or burned code or secret.
    case pairingFailed
    /// 409 `sas_mismatch` or the SAS the Core sent is not the one our keys make.
    case sasMismatch
    /// 409 `pairing_expired`, or the QR is past its expiry.
    case pairingExpired
    /// The approver rejected the pairing, or it lapsed (`rejected`, `expired`).
    case notApproved(String)
    /// The device was revoked (WebSocket close 4001).
    case revoked
    /// 410 `past_retention`: events up to `floor` were trimmed; re-sync.
    case pastRetention(floor: Int64)
    /// Any other 4xx/5xx in the standard error shape.
    case http(status: Int, code: String, message: String)
    /// 400 `bad_request` (kept apart: it is always a client bug).
    case badRequest(message: String)
    /// The Keychain or Secure Enclave refused. The text names the operation, never the key.
    case keyStore(String)
    /// This device has not paired (no keys or identity).
    case notPaired
    /// The user cancelled the Touch ID prompt, or the device has no step-up key.
    case stepUpUnavailable(String)
    /// A request body above 1 MiB (§4): the Core would count it as a forgery.
    case bodyTooLarge
    /// The Core said something that is not the contract's.
    case protocolViolation(String)
    /// Bad input from the caller: an endpoint, a code, a QR payload.
    case invalidInput(String)
}

extension CoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authFailed: "The Core did not accept this device."
        case .clockSkew: "This Mac's clock is too far from the Core's."
        case .sessionExpired: "The session ended."
        case .stepUpRequired: "This needs Touch ID."
        case .forbiddenScope: "This device is not allowed to do that."
        case .rateLimited(let s): s.map { "Too many requests. Try again in \(Int($0)) s." } ?? "Too many requests."
        case .coreIdentityMismatch: "This is not the Core this device was paired with."
        case .coreUnproven: "The Core could not prove who it is. Trying again shortly."
        case .noSharedMinor: "This app and the Core do not speak a common API version."
        case .offline(let m): "The Core cannot be reached: \(m)"
        case .pairingFailed: "The pairing code is wrong, used or expired."
        case .sasMismatch: "The check codes do not match."
        case .pairingExpired: "The pairing expired."
        case .notApproved(let s): "The pairing was not approved (\(s))."
        case .revoked: "This device was revoked."
        case .pastRetention: "Some events were trimmed; the list was re-synced."
        case .http(_, _, let m): m
        case .badRequest(let m): m
        case .keyStore(let m): m
        case .notPaired: "This device is not paired."
        case .stepUpUnavailable(let m): m
        case .bodyTooLarge: "That is too large to send."
        case .protocolViolation(let m): m
        case .invalidInput(let m): m
        }
    }
}

extension CoreError {
    /// The error for a non-2xx answer (§14). `body` is the JSON error shape; an unreadable body keeps the status.
    static func from(status: Int, headers: [String: String], body: Data) -> CoreError {
        struct Body: Decodable {
            var code: String?
            var message: String?
            var server_time: Int64?
            var floor: Int64?
        }
        let b = (try? JSONDecoder().decode(Body.self, from: body)) ?? Body()
        let code = b.code ?? "unknown"
        switch (status, code) {
        case (401, "clock_skew"): return .clockSkew(serverTime: b.server_time)
        case (401, "session_expired"): return .sessionExpired
        case (401, "pairing_failed"): return .pairingFailed
        case (401, _): return .authFailed
        case (403, "step_up_required"): return .stepUpRequired
        case (403, "forbidden_scope"): return .forbiddenScope
        case (409, "sas_mismatch"): return .sasMismatch
        case (409, "pairing_expired"): return .pairingExpired
        case (410, "past_retention") where b.floor != nil: return .pastRetention(floor: b.floor!)
        case (429, _): return .rateLimited(retryAfter: headers["retry-after"].flatMap { TimeInterval($0) })
        case (400, _): return .badRequest(message: b.message ?? "bad request")
        default: return .http(status: status, code: code, message: b.message ?? "HTTP \(status)")
        }
    }

    /// The `CoreError` inside whatever the generated client wrapped it in, if any.
    public static func unwrapping(_ error: any Error) -> CoreError? {
        var current: (any Error)? = error
        while let e = current {
            if let core = e as? CoreError { return core }
            let mirror = Mirror(reflecting: e)
            current = mirror.children.first { $0.label == "underlyingError" }?.value as? any Error
        }
        return nil
    }
}
