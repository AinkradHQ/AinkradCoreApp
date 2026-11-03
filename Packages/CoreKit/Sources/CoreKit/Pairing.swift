import Foundation

/// A scanned QR payload (§7.1): `ainkrad-pair:v1?h=<host>&p=<port>&c=<core_fp>&s=<secret>&e=<unix>`. It always means HTTPS.
public struct PairingQR: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let host: String
    public let port: Int
    public let coreFingerprint: String
    let secret: Data
    public let expires: Int64
    public var description: String { "PairingQR(\(host):\(port), \(coreFingerprint))" }
    public var debugDescription: String { description }
    /// `dump` and the debugger show the public fields only, never the secret.
    public var customMirror: Mirror {
        Mirror(self, children: ["host": host, "port": port, "coreFingerprint": coreFingerprint, "expires": expires])
    }

    /// Every field exactly once, nothing else; a secret that is not 16 bytes, a fingerprint that is not 43 base64url
    /// characters or a port outside 1...65535 is refused.
    public static func parse(_ text: String) -> PairingQR? {
        let prefix = "ainkrad-pair:v1?"
        guard text.hasPrefix(prefix) else { return nil }
        let names = ["h", "p", "c", "s", "e"]
        var fields: [String: String] = [:]
        for pair in text.dropFirst(prefix.count).split(separator: "&", omittingEmptySubsequences: false) {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2, names.contains(String(kv[0])),
                fields.updateValue(String(kv[1]), forKey: String(kv[0])) == nil
            else { return nil }
        }
        guard let h = fields["h"], let p = fields["p"], let c = fields["c"], let s = fields["s"], let e = fields["e"],
            !h.isEmpty, !h.contains(where: { "/?#@ ".contains($0) }), let port = Int(p), (1...65535).contains(port),
            c.count == 43, Wire.unb64(c) != nil, let secret = Wire.unb64(s), secret.count == 16, let expires = Int64(e)
        else { return nil }
        return PairingQR(host: h, port: port, coreFingerprint: c, secret: secret, expires: expires)
    }
}

/// What was typed or scanned.
public enum PairingCredential: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    /// The canonical 10-character code.
    case code(String)
    case qr(PairingQR)

    public var description: String {
        switch self {
        case .code: "PairingCredential.code(…)"
        case .qr(let q): "PairingCredential.qr(\(q))"
        }
    }
    public var debugDescription: String { description }

    /// A QR payload (`ainkrad-pair:v1?…`) or a typed code (`ABCDE-FGHJK`, any case).
    public static func parse(_ text: String) throws -> PairingCredential {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("ainkrad-pair:") {
            guard let qr = PairingQR.parse(t) else {
                throw CoreError.invalidInput("That QR code is not an Ainkrad pairing.")
            }
            return .qr(qr)
        }
        guard let code = Wire.canonicalCode(t) else {
            throw CoreError.invalidInput("A pairing code is 10 letters and digits, like ABCDE-FGHJK.")
        }
        return .code(code)
    }

    /// SHA-256 of the canonical code's ASCII, or of the QR secret's 16 decoded bytes (§7.2 step 3).
    var credentialHash: Data {
        switch self {
        case .code(let c): Wire.sha256(Data(c.utf8))
        case .qr(let q): Wire.sha256(q.secret)
        }
    }
}

/// A claim the Core accepted. Show `sas` and have the approver compare it with theirs.
public struct PairingClaim: Sendable, Equatable {
    public let deviceID: String
    public let pairingID: String
    /// Computed here from the Core key, our key and the pairing id: never the Core's word for it.
    public let sas: String
    public let coreFingerprint: String
}

/// Where `awaitApproval` stopped.
public enum PairingOutcome: Sendable, Equatable {
    /// Approved and confirmed: the identity is saved and the Core pinned.
    case paired
    /// The approver approved, but the user has not confirmed the SAS: call `confirmSAS()` and `awaitApproval()` again, or
    /// `cancel()`. Nothing is pinned and nothing is forgotten.
    case awaitingConfirmation
}

/// What `cancel()` left behind.
public enum PairingCancel: Sendable, Equatable {
    /// Nothing was approved yet; the local state is gone and that is all.
    case cleared
    /// The approver had approved this device: it is still listed there, so tell the user to revoke it.
    case revokeDeviceOnApprover(deviceID: String)
}

/// Pairing as a new device (§7.2 steps 2 to 4 and 8): `claim`, show the SAS, `confirmSAS` when the user says it matches the
/// approver's, `awaitApproval`. The Core is pinned (the identity saved) only when the device is active and the SAS confirmed.
/// A pairing in flight survives a relaunch: `resume()` picks it up.
public actor DevicePairing {
    private let keyStore: any KeyStore
    private let clock: any CoreClock
    private let makeHTTP: @Sendable (CoreEndpoint) -> any CoreHTTP
    private var sessions: SessionManager?
    private var claiming = false

    public init(keyStore: any KeyStore, clock: any CoreClock = SystemCoreClock()) {
        let session = makeCoreSession()  // always CoreKit's own: no redirects, no cookies, no cache
        self.init(keyStore: keyStore, clock: clock) { URLSessionHTTP(endpoint: $0, session: session) }
    }

    init(keyStore: any KeyStore, clock: any CoreClock, makeHTTP: @escaping @Sendable (CoreEndpoint) -> any CoreHTTP) {
        self.keyStore = keyStore
        self.clock = clock
        self.makeHTTP = makeHTTP
    }

    /// Makes the two keys, proves the Core, claims with the code or QR secret and the proof of possession, checks the Core key
    /// that answered and computes the SAS. A typed code needs `endpoint` (loopback `http://127.0.0.1:7700` or
    /// `https://host:port`); a QR names its own. `expectedCoreFingerprint` pins the Core when one is known beforehand.
    public func claim(
        _ credential: PairingCredential, endpoint: URL? = nil, expectedCoreFingerprint: String? = nil
    ) async throws -> PairingClaim {
        guard !claiming else { throw CoreError.invalidInput("A pairing is being claimed already.") }
        claiming = true
        defer { claiming = false }
        if try keyStore.loadIdentity() != nil {
            throw CoreError.invalidInput("This device is paired already. Forget the Core first.")
        }
        if try keyStore.loadPending() != nil {
            throw CoreError.invalidInput("A pairing is waiting for approval. Resume it or cancel it.")
        }
        let core: CoreEndpoint
        var given = expectedCoreFingerprint
        switch credential {
        case .qr(let q):
            guard q.expires > Int64(clock.now().timeIntervalSince1970) else { throw CoreError.pairingExpired }
            core = try CoreEndpoint(host: q.host, port: q.port)
            given = q.coreFingerprint
        case .code:
            guard let endpoint else { throw CoreError.invalidInput("A typed code needs the Core's address.") }
            core = try CoreEndpoint(endpoint)
        }
        let http = makeHTTP(core)
        // The Core proves itself before a key is made or anything is sent. First use (no pin): trust on first use, which the
        // SAS comparison then confirms (§7.2 step 4).
        let proof = try await CoreHandshake.prove(http: http, host: core.host, pinned: given)
        let pinned = proof.fingerprint
        guard let routine = try keyStore.generateKey(.routine) else { throw CoreError.keyStore("no routine key") }
        do {
            let stepup = try keyStore.generateKey(.stepup)
            let claim = try await sendClaim(
                credential, http: http, pinned: pinned, routine: routine, stepup: stepup)
            let identity = PairedIdentity(deviceID: claim.deviceID, coreFingerprint: pinned, endpoint: core.url)
            // Pending, not paired: with a pin from the QR or the caller the Core key is trusted already; with a typed code the
            // user's SAS confirmation decides.
            try keyStore.savePending(
                PendingPairing(
                    identity: identity, pairingID: claim.pairingID, sas: claim.sas, sasConfirmed: given != nil))
            sessions = SessionManager(endpoint: core, identity: identity, key: routine, http: http, clock: clock)
            return claim
        } catch {
            try? keyStore.deleteKey(.routine)
            try? keyStore.deleteKey(.stepup)
            try? keyStore.clearPending()
            throw error
        }
    }

    /// Picks up a pairing that was claimed before the app quit: nil when there is none. Show the claim's SAS again, then
    /// `awaitApproval`.
    public func resume() async throws -> PairingClaim? {
        guard let p = try keyStore.loadPending(), let routine = try keyStore.key(.routine, reason: "") else {
            return nil
        }
        let core = try CoreEndpoint(p.identity.endpoint)
        sessions = SessionManager(
            endpoint: core, identity: p.identity, key: routine, http: makeHTTP(core), clock: clock)
        return PairingClaim(
            deviceID: p.identity.deviceID, pairingID: p.pairingID, sas: p.sas,
            coreFingerprint: p.identity.coreFingerprint)
    }

    /// The user compared the SAS with the approver's and they match: the Core key may be pinned once the device is active.
    public func confirmSAS() throws {
        guard var p = try keyStore.loadPending() else { throw CoreError.notPaired }
        p.sasConfirmed = true
        try keyStore.savePending(p)
    }

    /// Gives up on a pairing in flight: clears the pending slot and its keys. Never touches a paired device (it throws).
    @discardableResult
    public func cancel() throws -> PairingCancel {
        if try keyStore.loadIdentity() != nil {
            throw CoreError.invalidInput("This device is paired; use Forget, not cancel.")
        }
        let pending = try keyStore.loadPending()
        sessions = nil
        try keyStore.deleteKey(.routine)
        try keyStore.deleteKey(.stepup)
        try keyStore.clearPending()
        if let p = pending, p.approved { return .revokeDeviceOnApprover(deviceID: p.identity.deviceID) }
        return .cleared
    }

    private func sendClaim(
        _ credential: PairingCredential, http: any CoreHTTP, pinned: String, routine: any DeviceKey,
        stepup: (any DeviceKey)?
    ) async throws -> PairingClaim {
        let message = Wire.popMessage(
            coreFP: pinned, credentialHash: credential.credentialHash, routineFP: routine.fingerprint,
            stepupFP: stepup?.fingerprint)
        var body: [String: String] = [
            "routine_spki": Wire.b64(routine.spki), "platform": Self.platform,
            "key_storage": routine.storage.rawValue, "pop": Wire.b64(try routine.sign(message)),
        ]
        if let stepup {
            // Signing with the step-up key is what asks the user to verify, here on the new device.
            let sig = try await offloaded { try stepup.sign(message) }
            body["stepup_spki"] = Wire.b64(stepup.spki)
            body["pop_stepup"] = Wire.b64(sig)
        }
        switch credential {
        case .code(let c): body["code"] = c
        case .qr(let q): body["secret"] = Wire.b64(q.secret)
        }
        let res = try await http.send(
            RawRequest(
                method: "POST", target: "/pair/claim", headers: ["content-type": "application/json"],
                body: try JSONEncoder().encode(body)))
        guard res.status == 202 else { throw CoreError.from(status: res.status, headers: res.headers, body: res.body) }
        struct Claimed: Decodable {
            var device_id: String?
            var core_spki: String?
            var pairing_id: String?
            var sas: String?
        }
        guard let c = try? JSONDecoder().decode(Claimed.self, from: res.body), let device = c.device_id,
            let spkiText = c.core_spki, let pairing = c.pairing_id, let spki = Wire.unb64(spkiText)
        else { throw CoreError.protocolViolation("a claim answer without device_id, core_spki or pairing_id") }
        // §7.2 step 4: the Core key that answered is the one that proved itself.
        let served = Wire.fingerprint(spki: spki)
        guard served == pinned else { throw CoreError.coreIdentityMismatch(pinned: pinned, served: served) }
        let mine = Wire.sas(coreSPKI: spki, deviceSPKI: routine.spki, pairingID: pairing)
        guard c.sas == mine else { throw CoreError.sasMismatch }
        return PairingClaim(deviceID: device, pairingID: pairing, sas: mine, coreFingerprint: pinned)
    }

    static var platform: String {
        #if os(iOS)
        "ios"
        #else
        "macos"
        #endif
    }

    /// Polls `POST /pair/status` (signed, session `-`) with a backoff until the approver decides. `active` stops the clock and
    /// never forgets anything: with the SAS confirmed the identity is saved (the pin) and it returns `.paired`; without, it
    /// returns `.awaitingConfirmation` so the UI can confirm or cancel. `rejected` or `expired` (or `timeout` passing while
    /// still pending: a pairing lives 5 minutes) forgets everything and throws `notApproved`.
    @discardableResult
    public func awaitApproval(timeout: Duration = .seconds(330)) async throws -> PairingOutcome {
        guard let sessions else { throw CoreError.notPaired }
        let deadline = clock.now().addingTimeInterval(Double(timeout.components.seconds))
        var delay = 0.5
        while true {
            do {
                let res = try await sessions.perform(method: "POST", target: "/pair/status", session: .none)
                guard
                    let status = (try? JSONSerialization.jsonObject(with: res.body) as? [String: Any])?["status"]
                        as? String
                else { throw CoreError.protocolViolation("a pairing status without a status") }
                switch status {
                case "active":
                    guard var p = try keyStore.loadPending() else { throw CoreError.notPaired }
                    guard p.sasConfirmed else {
                        p.approved = true
                        try keyStore.savePending(p)
                        return .awaitingConfirmation
                    }
                    try keyStore.saveIdentity(p.identity)
                    try keyStore.clearPending()
                    self.sessions = nil
                    return .paired
                case "pending": break
                default: throw forget(status)
                }
            } catch CoreError.offline {
                // The Core may be restarting: keep asking until the pairing could not be live any more.
            } catch CoreError.authFailed {
                // A claimed-then-rejected device is refused like a stranger.
                throw forget("rejected")
            }
            // Once the approver has approved, the pairing is not ours to expire: keep asking (a relaunch while offline, say).
            let approved = (try? keyStore.loadPending())?.approved == true
            if !approved, clock.now() >= deadline { throw forget("expired") }
            try await clock.sleep(for: .seconds(delay))
            delay = min(delay * 1.5, 5)
        }
    }

    private func forget(_ status: String) -> CoreError {
        try? keyStore.wipe()
        sessions = nil
        return .notApproved(status)
    }
}
