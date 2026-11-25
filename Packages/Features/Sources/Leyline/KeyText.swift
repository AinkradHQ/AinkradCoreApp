import CryptoKit
import Foundation

/// The Keys panel's inline Generate or Import form.
enum KeyForm: Equatable { case generate, importing }

/// What the Import form holds: where the key came from, its text and passphrase. Cleared the moment the form closes.
struct KeyDraft: Equatable {
    var name = ""
    var text = ""
    var passphrase = ""
    /// The file the key came from (a drop or Choose File…); nil for pasted text.
    var file: String?
    /// "Paste text instead": the text area, not the drop area.
    var pasting = false
    /// Generate's type: "ed25519" or "rsa".
    var type = "ed25519"

    /// What the key text looks like; nil while there is none.
    var detected: KeyText.Kind? { text.isEmpty ? nil : KeyText.detect(text) }

    /// Fills the form from a key file: its text, and its name from the file's.
    mutating func load(file: String, text: String, taken: [String]) {
        self.file = file
        self.text = text
        passphrase = ""
        pasting = false
        if name.isEmpty { name = KeyText.name(fromFile: file, taken: taken) }
    }
}

/// Plain logic behind the Keys panel: names, what a private key's text says about itself, and the host chips.
enum KeyText {
    /// What a pasted or dropped text is.
    enum Kind: Equatable {
        /// A private key: its type ("ed25519", "RSA 4096", "ecdsa P-256"; nil when the text does not say), whether it
        /// needs a passphrase, and its `SHA256:` fingerprint when the text carries the public half (OpenSSH keys do).
        case privateKey(type: String?, encrypted: Bool, fingerprint: String?)
        /// The public half (`ssh-ed25519 AAAA…`, a `.pub` file).
        case publicKey
        case notAKey
    }

    /// "key-1", or the first "key-N" no key has yet.
    static func uniqueName(_ taken: [String], base: String = "key") -> String {
        let used = Set(taken.map { $0.lowercased() })
        var n = 1
        while used.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    /// A key's name from its file: "id_ed25519" from "id_ed25519", "deploy" from "deploy.pem"; "deploy-2" when taken.
    static func name(fromFile file: String, taken: [String]) -> String {
        var stem = (file as NSString).deletingPathExtension
        if stem.isEmpty || stem.hasPrefix(".") { stem = "key" }
        let clean = String(
            stem.map { $0.isLetter || $0.isNumber || "-_.".contains($0) ? $0 : "-" }.prefix(48))
        // The same rule as Add Host's import: a taken name becomes "name-2".
        return AddHostFlow.freeName(clean, taken: Set(taken))
    }

    /// The first `limit` items and how many more there are ("+2").
    static func chips<T>(_ items: [T], limit: Int = 3) -> (shown: [T], more: Int) {
        (Array(items.prefix(limit)), max(items.count - limit, 0))
    }

    static func detect(_ raw: String) -> Kind {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("ssh-") || text.hasPrefix("ecdsa-sha2-") { return .publicKey }
        guard let head = text.range(of: #"-----BEGIN ([A-Z ]*)PRIVATE KEY-----"#, options: .regularExpression) else {
            return .notAKey
        }
        let label = text[head].dropFirst("-----BEGIN ".count).dropLast("PRIVATE KEY-----".count)
            .trimmingCharacters(in: .whitespaces)
        // PEM (`Proc-Type: 4,ENCRYPTED`) and PKCS#8 (`ENCRYPTED PRIVATE KEY`) say so in the text.
        let pemEncrypted = text.contains("ENCRYPTED")
        switch label {
        case "OPENSSH": return openSSH(text)
        case "RSA": return .privateKey(type: "RSA", encrypted: pemEncrypted, fingerprint: nil)
        case "EC": return .privateKey(type: "ecdsa", encrypted: pemEncrypted, fingerprint: nil)
        default: return .privateKey(type: nil, encrypted: pemEncrypted, fingerprint: nil)
        }
    }

    /// `openssh-key-v1`: the cipher, then the public key in the clear, so the type and the fingerprint show before the
    /// passphrase. A body that does not read as one still counts as a key: the Core has the last word.
    private static func openSSH(_ text: String) -> Kind {
        let body = text.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        guard let data = Data(base64Encoded: body), var r = Reader(data), r.magic() else {
            return .privateKey(type: nil, encrypted: false, fingerprint: nil)
        }
        guard let cipher = r.string(), r.string() != nil, r.string() != nil, r.uint32() != nil, let blob = r.bytes()
        else { return .privateKey(type: nil, encrypted: false, fingerprint: nil) }
        let digest = Data(SHA256.hash(data: blob)).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return .privateKey(
            type: type(of: blob), encrypted: String(decoding: cipher, as: UTF8.self) != "none",
            fingerprint: "SHA256:\(digest)")
    }

    /// "ed25519", "RSA 4096", "ecdsa P-256" from a public key blob.
    private static func type(of blob: Data) -> String? {
        guard var r = Reader(blob), let name = r.string().map({ String(decoding: $0, as: UTF8.self) }) else {
            return nil
        }
        switch name {
        case "ssh-ed25519": return "ed25519"
        case "ssh-rsa":
            guard r.string() != nil, let n = r.bytes() else { return "RSA" }
            return "RSA \(n.drop { $0 == 0 }.count * 8)"
        case "ecdsa-sha2-nistp256": return "ecdsa P-256"
        case "ecdsa-sha2-nistp384": return "ecdsa P-384"
        default: return name
        }
    }

    /// Reads the length-prefixed fields of an OpenSSH key.
    private struct Reader {
        let data: Data
        var at: Data.Index
        init?(_ data: Data) {
            self.data = data
            at = data.startIndex
        }
        mutating func magic() -> Bool {
            let m = Data("openssh-key-v1\0".utf8)
            guard data.count >= m.count, data.prefix(m.count) == m else { return false }
            at += m.count
            return true
        }
        mutating func uint32() -> Int? {
            guard data.endIndex - at >= 4 else { return nil }
            let v = data[at..<at + 4].reduce(0) { $0 << 8 | Int($1) }
            at += 4
            return v
        }
        mutating func bytes() -> Data? {
            guard let n = uint32(), data.endIndex - at >= n else { return nil }
            defer { at += n }
            return data[at..<at + n]
        }
        mutating func string() -> Data? { bytes() }
    }

    #if DEBUG
    /// A made-up OpenSSH private key's text around a public key of `type` (`ssh-ed25519`) and its fields: enough for `detect` to read
    /// its type, cipher and fingerprint. Tests and the demo only; the private part is noise.
    static func sample(
        type: String = "ssh-ed25519", cipher: String = "none", publicFields: [Data] = [Data(repeating: 7, count: 32)]
    )
        -> String
    {
        func field(_ d: Data) -> Data {
            var n = UInt32(d.count).bigEndian
            return Data(bytes: &n, count: 4) + d
        }
        let blob = ([Data(type.utf8)] + publicFields).map(field).reduce(Data(), +)
        var n = UInt32(1).bigEndian
        let body =
            Data("openssh-key-v1\0".utf8) + field(Data(cipher.utf8))
            + field(Data((cipher == "none" ? "none" : "bcrypt").utf8))
            + field(Data()) + Data(bytes: &n, count: 4) + field(blob) + field(Data(repeating: 1, count: 64))
        let lines = body.base64EncodedString().chunked(70)
        return
            "-----BEGIN OPENSSH PRIVATE KEY-----\n\(lines.joined(separator: "\n"))\n-----END OPENSSH PRIVATE KEY-----\n"
    }
    #endif
}

#if DEBUG
extension String {
    fileprivate func chunked(_ n: Int) -> [String] {
        stride(from: 0, to: count, by: n).map {
            let a = index(startIndex, offsetBy: $0)
            return String(self[a..<(index(a, offsetBy: n, limitedBy: endIndex) ?? endIndex)])
        }
    }
}
#endif
