import CoreKit
import CryptoKit
import Foundation

/// One wait for a new Core (E3-1, auto-connect). The app makes a one-time code and a throwaway X25519 key, puts both in the
/// install command, and the installer leaves the connect link at the rendezvous sealed to that key (Core PR 392,
/// `rendezvous.rs`; Worker PR 3). The rendezvous holds only ciphertext under `id` and is never told the code, so it can
/// neither read nor forge the link. Whoever read the command could still leave a link for their own Core, which is why the
/// app shows the Core's address and fingerprint and waits for the person to press Connect.
struct RendezvousSession: Sendable {
    /// Binds key and message to this protocol; the installer uses the same bytes.
    static let context = Data("ainkrad-rendezvous-v1".utf8)
    let code: Data
    private let key: Curve25519.KeyAgreement.PrivateKey

    init() {
        code = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        key = Curve25519.KeyAgreement.PrivateKey()
    }

    init(code: Data, key: Curve25519.KeyAgreement.PrivateKey) {
        self.code = code
        self.key = key
    }

    var publicKey: Data { key.publicKey.rawRepresentation }
    /// What goes into the install command as `AINKRAD_RENDEZVOUS`: `<code>.<public key>`, both base64url.
    var spec: String { Wire.b64(code) + "." + Wire.b64(publicKey) }
    /// Where the message waits: base64url of SHA-256 of the code. The code itself never leaves this Mac.
    var id: String { Wire.b64(Data(SHA256.hash(data: code))) }

    /// The link in a message from the installer, or nil when it is not for this session (wrong code, wrong key, altered).
    func open(epk: Data, ct: Data) -> String? {
        guard ct.count > 16, let peer = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: epk),
            let shared = try? key.sharedSecretFromKeyAgreement(with: peer),
            let nonce = try? ChaChaPoly.Nonce(data: Data(count: 12))
        else { return nil }
        let sym = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: code, sharedInfo: Self.context + epk + publicKey, outputByteCount: 32)
        guard
            let box = try? ChaChaPoly.SealedBox(
                nonce: nonce, ciphertext: Data(ct.dropLast(16)), tag: Data(ct.suffix(16))),
            let plain = try? ChaChaPoly.open(box, using: sym, authenticating: Self.context)
        else { return nil }
        return String(data: plain, encoding: .utf8)
    }
}

enum RendezvousError: Error, Equatable {
    /// The message under this code was collected already.
    case used
}

/// The rendezvous, as the wizard polls it.
protocol RendezvousClient: Sendable {
    /// The sealed message under `id`, or nil while nothing is there. Throws `.used` once it was collected, and any
    /// transport error (the wizard keeps polling through those).
    func fetch(id: String) async throws -> (epk: Data, ct: Data)?
}

struct LiveRendezvous: RendezvousClient {
    static let base = URL(string: "https://signin.ainkrad.io")!

    func fetch(id: String) async throws -> (epk: Data, ct: Data)? {
        var req = URLRequest(url: Self.base.appending(path: "v1/rendezvous/\(id)"), timeoutInterval: 10)
        req.httpMethod = "GET"
        let (data, res) = try await URLSession.shared.data(for: req)
        switch (res as? HTTPURLResponse)?.statusCode {
        case 200:
            struct Body: Decodable {
                let epk: String
                let ct: String
            }
            guard let b = try? JSONDecoder().decode(Body.self, from: data), let epk = Wire.unb64(b.epk),
                let ct = Wire.unb64(b.ct)
            else { throw URLError(.cannotParseResponse) }
            return (epk, ct)
        case 404: return nil
        case 410: throw RendezvousError.used
        default: throw URLError(.badServerResponse)
        }
    }
}
