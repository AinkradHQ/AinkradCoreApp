import Foundation

/// What `POST /handshake` proved (§4, §13).
public struct CoreProof: Sendable, Equatable {
    public let coreSPKI: Data
    public let fingerprint: String
    public let serverVersion: String?
    public let apiMinor: Int32?
    public let supportedMinors: [Int32]?
}

enum CoreHandshake {
    /// The Core proves, over a fresh nonce, that it holds the key `pinned` names. With no pin yet (a typed code: trust on first
    /// use, confirmed by the SAS) the fingerprint it returns is `fp(core_spki)`, still only after the signature verifies.
    /// Fails closed (§13): any status but 200 (a 429 aside, which is the rate), a missing or malformed `core_spki`/`core_sig`,
    /// a key that is not the pinned one or a signature that does not verify is `coreIdentityMismatch`. Never falls back to
    /// `GET /handshake`, whose fingerprint is only a claim. Nothing signed is sent.
    static func prove(http: any CoreHTTP, host: String, pinned: String?) async throws -> CoreProof {
        struct Answer: Decodable {
            var core_spki: String?
            var core_sig: String?
            var server_version: String?
            var api_minor: Int32?
            var supported_minors: [Int32]?
        }
        let nonce = Wire.nonce()
        let body = try JSONEncoder().encode(["nonce": nonce])
        let res = try await http.send(
            RawRequest(method: "POST", target: "/handshake", headers: ["content-type": "application/json"], body: body))
        if res.status == 429 { throw CoreError.from(status: 429, headers: res.headers, body: res.body) }
        let pin = pinned ?? "(nothing yet)"
        func mismatch(_ why: String) -> CoreError { .coreIdentityMismatch(pinned: pin, served: why) }
        guard res.status == 200 else { throw mismatch("unproven (POST /handshake \(res.status))") }
        guard let a = try? JSONDecoder().decode(Answer.self, from: res.body) else {
            throw mismatch("unproven (not a handshake)")
        }
        guard let spkiText = a.core_spki, let sigText = a.core_sig, let spki = Wire.unb64(spkiText),
            let sig = Wire.unb64(sigText), Wire.publicKey(spki: spki) != nil
        else { throw mismatch("unproven (no usable core_spki/core_sig)") }
        let served = Wire.fingerprint(spki: spki)
        if let pinned, pinned != served { throw mismatch(served) }
        guard Wire.verify(spki: spki, message: Wire.coreProofMessage(host: host, nonce: nonce), signature: sig) else {
            throw mismatch("\(served) (core_sig does not verify)")
        }
        return CoreProof(
            coreSPKI: spki, fingerprint: served, serverVersion: a.server_version, apiMinor: a.api_minor,
            supportedMinors: a.supported_minors)
    }
}
