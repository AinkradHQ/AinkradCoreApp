import CryptoKit
import Foundation

/// The handshake spec's wire primitives (§3, §5.2, §7.1, §7.2): base64url, fingerprints, SPKI checks, the
/// canonical request string, the pairing code fold, the proof-of-possession message, the SAS and the step-up message.
public enum Wire {
    /// `Ainkrad-Alg`: the only value in v1.
    public static let alg = "ES256"

    /// DER `SubjectPublicKeyInfo` for `id-ecPublicKey` + `prime256v1`, up to the point (§3).
    static let spkiPrefix: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
        0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ]

    // MARK: base64url

    public static func b64(_ data: some DataProtocol) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Strict base64url without padding: only text that encodes back to itself.
    public static func unb64(_ text: String) -> Data? {
        guard !text.contains(where: { !($0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")) }) else {
            return nil
        }
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        guard let data = Data(base64Encoded: s), b64(data) == text else { return nil }
        return data
    }

    public static func sha256(_ data: some DataProtocol) -> Data { Data(SHA256.hash(data: data)) }

    /// 16 random bytes, base64url (22 characters): a request or handshake nonce.
    public static func nonce() -> String { b64(randomBytes(16)) }

    static func randomBytes(_ n: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: n)
        let status = SecRandomCopyBytes(kSecRandomDefault, n, &out)
        precondition(status == errSecSuccess, "the OS random source works")
        return out
    }

    // MARK: keys

    /// `fp(key)` = base64url_nopad(SHA-256(SPKI)), 43 characters.
    public static func fingerprint(spki: Data) -> String { b64(sha256(spki)) }

    /// A public key from a spec SPKI: exact 91-byte prefix compare, then the point is validated on the curve.
    public static func publicKey(spki: Data) -> P256.Signing.PublicKey? {
        guard spki.count == 91, Array(spki.prefix(26)) == spkiPrefix else { return nil }
        return try? P256.Signing.PublicKey(derRepresentation: spki)
    }

    /// Whether `signature` (raw r‖s) is `spki`'s ES256 signature over `message`.
    public static func verify(spki: Data, message: Data, signature: Data) -> Bool {
        guard signature.count == 64, let key = publicKey(spki: spki),
            let sig = try? P256.Signing.ECDSASignature(rawRepresentation: signature)
        else { return false }
        return key.isValidSignature(sig, for: message)
    }

    // MARK: canonical request (§5.2)

    /// The 11 fields joined by LF, no trailing newline.
    public static func canonicalRequest(
        coreFP: String, deviceID: String, sessionID: String?, method: String, path: String, query: String,
        timestamp: UInt64, nonce: String, body: Data
    ) -> Data {
        let fields = [
            "AINKRAD-REQ-V1", coreFP, alg, deviceID, sessionID ?? "-", method, path, query, String(timestamp), nonce,
            b64(sha256(body)),
        ]
        return Data(fields.joined(separator: "\n").utf8)
    }

    // MARK: pairing (§7)

    static let crockford = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// The first `n` upper-case Crockford characters of `bytes`: 5-bit groups, most significant first.
    static func crockford(_ bytes: Data, count n: Int) -> String {
        let b = [UInt8](bytes)
        var out = ""
        for c in 0..<n {
            var v = 0
            for k in 0..<5 {
                let i = c * 5 + k
                v = (v << 1) | Int((b[i / 8] >> (7 - UInt8(i % 8))) & 1)
            }
            out.append(crockford[v])
        }
        return out
    }

    /// A typed code, canonical (§7.1): case-insensitive, `I`/`L` → `1`, `O` → `0`, dashes and spaces dropped;
    /// nil unless that leaves 10 Crockford characters.
    public static func canonicalCode(_ typed: String) -> String? {
        var out = ""
        for scalar in typed.unicodeScalars where scalar != "-" && scalar != " " {
            guard scalar.isASCII else { return nil }
            var c = Character(scalar)
            c = Character(c.uppercased())
            if c == "I" || c == "L" { c = "1" } else if c == "O" { c = "0" }
            out.append(c)
        }
        guard out.count == 10, out.allSatisfy({ crockford.contains($0) }) else { return nil }
        return out
    }

    /// The string the claimant's keys sign (§7.2 step 3); `stepupFP` is `-` without a step-up key.
    public static func popMessage(coreFP: String, credentialHash: Data, routineFP: String, stepupFP: String?) -> Data {
        Data("AINKRAD-PAIR-V1\n\(coreFP)\n\(b64(credentialHash))\n\(routineFP)\n\(stepupFP ?? "-")".utf8)
    }

    /// The SAS (§3): 16 Crockford characters of SHA-256("AINKRAD-SAS-V1" ‖ core_spki ‖ device_spki ‖ pairing_id),
    /// grouped `XXXX-XXXX-XXXX-XXXX`.
    public static func sas(coreSPKI: Data, deviceSPKI: Data, pairingID: String) -> String {
        var input = Data("AINKRAD-SAS-V1".utf8)
        input.append(coreSPKI)
        input.append(deviceSPKI)
        input.append(Data(pairingID.utf8))
        let s = crockford(sha256(input), count: 16)
        return stride(from: 0, to: 16, by: 4).map { i in
            String(s.dropFirst(i).prefix(4))
        }.joined(separator: "-")
    }

    // MARK: handshake and step-up messages

    /// What the Core signs in `POST /handshake` (§4, §13): `AINKRAD-CORE-V1` LF host LF nonce.
    public static func coreProofMessage(host: String, nonce: String) -> Data {
        Data("AINKRAD-CORE-V1\n\(host)\n\(nonce)".utf8)
    }

    /// What the step-up key signs (§8): five fields joined by LF, no trailing newline.
    public static func stepUpMessage(coreFP: String, deviceID: String, sessionID: String, challenge: String) -> Data {
        Data(["AINKRAD-STEPUP-V1", coreFP, deviceID, sessionID, challenge].joined(separator: "\n").utf8)
    }

    /// An RFC 3339 UTC timestamp with milliseconds (the contract's one timestamp shape), as unix seconds.
    public static func parseTimestamp(_ text: String) -> Int64? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return Int64(d.timeIntervalSince1970.rounded(.down)) }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text).map { Int64($0.timeIntervalSince1970.rounded(.down)) }
    }
}
