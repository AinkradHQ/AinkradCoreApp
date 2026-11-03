import Foundation

/// A scanned QR payload (§7.1): `ainkrad-pair:v1?h=<host>&p=<port>&c=<core_fp>&s=<secret>&e=<unix>`. It always means HTTPS.
public struct PairingQR: Sendable, Equatable, CustomStringConvertible {
    public let host: String
    public let port: Int
    public let coreFingerprint: String
    let secret: Data
    public let expires: Int64
    public var description: String { "PairingQR(\(host):\(port), \(coreFingerprint))" }

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
public enum PairingCredential: Sendable, Equatable {
    /// The canonical 10-character code.
    case code(String)
    case qr(PairingQR)

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

/// Pairing as a new device (§7.2 steps 2 to 4 and 8): `claim`, show the SAS, then `awaitApproval`.
public actor DevicePairing {
    private let keyStore: any KeyStore
    private let clock: any CoreClock
    private let makeHTTP: @Sendable (CoreEndpoint) -> any CoreHTTP
    private var pending: SessionManager?

    public init(keyStore: any KeyStore, clock: any CoreClock = SystemCoreClock(), urlSession: URLSession? = nil) {
        let session = urlSession ?? makeCoreSession()
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
        if try keyStore.loadIdentity() != nil {
            throw CoreError.invalidInput("This device is paired already. Forget the Core first.")
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
                credential, core: core, http: http, pinned: pinned, routine: routine, stepup: stepup)
            let identity = PairedIdentity(deviceID: claim.deviceID, coreFingerprint: pinned, endpoint: core.url)
            try keyStore.saveIdentity(identity)
            pending = SessionManager(endpoint: core, identity: identity, key: routine, http: http, clock: clock)
            return claim
        } catch {
            try? keyStore.deleteKey(.routine)
            try? keyStore.deleteKey(.stepup)
            throw error
        }
    }

    private func sendClaim(
        _ credential: PairingCredential, core: CoreEndpoint, http: any CoreHTTP, pinned: String, routine: any DeviceKey,
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

    /// Polls `POST /pair/status` (signed, session `-`) with a backoff until the approver decides. `active` returns; `rejected`
    /// or `expired` (or `timeout` passing: a pairing lives 5 minutes) forgets the keys and throws `notApproved`.
    public func awaitApproval(timeout: Duration = .seconds(330)) async throws {
        guard let sessions = pending else { throw CoreError.notPaired }
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
                    pending = nil
                    return
                case "pending": break
                default:
                    try? keyStore.wipe()
                    pending = nil
                    throw CoreError.notApproved(status)
                }
            } catch CoreError.offline {
                // The Core may be restarting: keep asking until the pairing could not be live any more.
            } catch CoreError.authFailed {
                // A claimed-then-rejected device is refused like a stranger.
                try? keyStore.wipe()
                pending = nil
                throw CoreError.notApproved("rejected")
            }
            if clock.now() >= deadline {
                try? keyStore.wipe()
                pending = nil
                throw CoreError.notApproved("expired")
            }
            try await clock.sleep(for: .seconds(delay))
            delay = min(delay * 1.5, 5)
        }
    }
}
