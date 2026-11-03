import CryptoKit
import Foundation
import Testing

@testable import CoreKit

// The committed golden vectors (handshake spec §17.1), copied from AinkradCore at dad06e2 (Fixtures/SOURCE.txt): the client
// must reproduce each canonical string, pop message, SAS and step-up message byte for byte, and verify each committed signature.

private func vector(_ name: String) throws -> [String: Any] {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}

private func s(_ v: [String: Any], _ k: String) -> String { v[k] as! String }
private func bytes(_ v: [String: Any], _ k: String) -> Data { Wire.unb64(s(v, k))! }
private func key(_ v: [String: Any], _ k: String) throws -> P256.Signing.PrivateKey {
    try P256.Signing.PrivateKey(derRepresentation: bytes(v, k))
}

@Suite struct VectorTests {
    @Test func handshakeCanonicalStringAndSignature() throws {
        let v = try vector("handshake-v1")
        let device = try key(v, "device_pkcs8")
        #expect(Wire.b64(device.publicKey.derRepresentation) == s(v, "device_spki"))
        #expect(Wire.fingerprint(spki: device.publicKey.derRepresentation) == s(v, "device_fingerprint"))
        #expect(Wire.fingerprint(spki: try key(v, "core_pkcs8").publicKey.derRepresentation) == s(v, "core_fp"))
        let body = Data(s(v, "body").utf8)
        #expect(Wire.b64(Wire.sha256(body)) == s(v, "body_sha256"))
        let canonical = Wire.canonicalRequest(
            coreFP: s(v, "core_fp"), deviceID: s(v, "device_id"), sessionID: s(v, "session_id"), method: s(v, "method"),
            path: s(v, "path"), query: s(v, "query"), timestamp: UInt64(v["timestamp"] as! Int), nonce: s(v, "nonce"),
            body: body)
        #expect(canonical == Data(s(v, "canonical").utf8), "exact bytes")
        #expect(canonical.last != 0x0A, "no trailing newline")
        #expect(
            Wire.verify(spki: bytes(v, "device_spki"), message: canonical, signature: bytes(v, "signature")),
            "the committed signature")
        var tampered = canonical
        tampered[40] ^= 1
        #expect(!Wire.verify(spki: bytes(v, "device_spki"), message: tampered, signature: bytes(v, "signature")))
        // Session `-`.
        let none = Wire.canonicalRequest(
            coreFP: s(v, "core_fp"), deviceID: s(v, "device_id"), sessionID: nil, method: "POST", path: "/pair/status",
            query: "", timestamp: 1, nonce: s(v, "nonce"), body: Data())
        #expect(
            String(decoding: none, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)[4] == "-")
    }

    @Test func ourSignatureOverTheVectorVerifies() throws {
        let v = try vector("handshake-v1")
        let k = SoftwareKey(key: try key(v, "device_pkcs8"))
        let sig = try k.sign(Data(s(v, "canonical").utf8))
        #expect(sig.count == 64)
        #expect(Wire.verify(spki: k.spki, message: Data(s(v, "canonical").utf8), signature: sig))
    }

    @Test func pairingCodeSecretPopAndSAS() throws {
        let v = try vector("pairing-v1")
        let code = try #require(Wire.canonicalCode(s(v, "typed_code")))
        #expect(code == s(v, "canonical_code"))
        #expect(Wire.b64(Wire.sha256(Data(code.utf8))) == s(v, "code_hash"))
        #expect(Wire.b64(Wire.sha256(bytes(v, "secret"))) == s(v, "secret_hash"))
        let core = try key(v, "core_pkcs8").publicKey.derRepresentation
        let device = try key(v, "device_pkcs8")
        let deviceSPKI = device.publicKey.derRepresentation
        #expect(Wire.b64(core) == s(v, "core_spki"))
        #expect(Wire.fingerprint(spki: core) == s(v, "core_fp"))
        #expect(Wire.fingerprint(spki: deviceSPKI) == s(v, "device_fp"))
        for (hash, message, sig) in [
            ("code_hash", "pop_message_code", "pop_code"), ("secret_hash", "pop_message_secret", "pop_secret"),
        ] {
            let m = Wire.popMessage(
                coreFP: s(v, "core_fp"), credentialHash: bytes(v, hash), routineFP: s(v, "device_fp"), stepupFP: nil)
            #expect(m == Data(s(v, message).utf8), "\(message)")
            #expect(Wire.verify(spki: deviceSPKI, message: m, signature: bytes(v, sig)), "\(sig)")
        }
        #expect(Wire.sas(coreSPKI: core, deviceSPKI: deviceSPKI, pairingID: s(v, "pairing_id")) == s(v, "sas"))
        // The QR secret path hashes the 16 decoded bytes, not the base64 text.
        #expect(Wire.b64(Wire.sha256(Data(s(v, "secret").utf8))) != s(v, "secret_hash"))
    }

    @Test func stepUpMessageAndSignature() throws {
        let v = try vector("stepup-v1")
        let m = Wire.stepUpMessage(
            coreFP: s(v, "core_fp"), deviceID: s(v, "device_id"), sessionID: s(v, "session_id"),
            challenge: s(v, "challenge"))
        #expect(m == Data(s(v, "message").utf8))
        let k = try key(v, "stepup_pkcs8")
        #expect(Wire.b64(k.publicKey.derRepresentation) == s(v, "stepup_spki"))
        #expect(Wire.verify(spki: bytes(v, "stepup_spki"), message: m, signature: bytes(v, "stepup_sig")))
        let other = Data(String(decoding: m, as: UTF8.self).replacingOccurrences(of: "STEPUP", with: "REQ").utf8)
        #expect(!Wire.verify(spki: bytes(v, "stepup_spki"), message: other, signature: bytes(v, "stepup_sig")))
    }

    @Test func coreSigVerifiesAndIsBoundToTheHost() throws {
        let v = try vector("core-sig-v1")
        let m = Wire.coreProofMessage(host: s(v, "host"), nonce: s(v, "nonce"))
        #expect(m == Data(s(v, "message").utf8))
        #expect(Wire.fingerprint(spki: bytes(v, "core_spki")) == s(v, "core_fp"))
        #expect(Wire.verify(spki: bytes(v, "core_spki"), message: m, signature: bytes(v, "core_sig")))
        let evil = Wire.coreProofMessage(host: "evil.example", nonce: s(v, "nonce"))
        #expect(!Wire.verify(spki: bytes(v, "core_spki"), message: evil, signature: bytes(v, "core_sig")))
    }
}
