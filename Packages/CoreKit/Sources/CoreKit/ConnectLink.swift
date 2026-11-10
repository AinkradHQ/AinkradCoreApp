import Darwin
import Foundation

/// Why a pasted or opened link is not a usable connect link, in words a person can act on.
public enum ConnectLinkError: Error, Equatable, LocalizedError {
    case notALink
    case wrongScheme
    case missing(String)
    case duplicate(String)
    case badHost
    case nonASCIIHost
    case badFingerprint
    case badSecret

    public var errorDescription: String? {
        switch self {
        case .notALink: "That is not a link. Paste the one the installer printed; it starts with ainkrad://connect."
        case .wrongScheme: "That link is not for Ainkrad. It should start with ainkrad://connect."
        case .missing(let f): "The link is missing its \(Self.word(f)). Copy the whole link again."
        case .duplicate(let f): "The link has its \(Self.word(f)) twice. Copy the whole link again."
        case .badHost: "The link's address is not valid. Copy the whole link again."
        case .nonASCIIHost:
            "The link's address has characters that can look like others, so Ainkrad refuses it. Only use a link from your own Core."
        case .badFingerprint: "The link's Core fingerprint is damaged. Copy the whole link again."
        case .badSecret: "The link's secret is damaged. Copy the whole link again."
        }
    }

    private static func word(_ field: String) -> String {
        switch field {
        case "host": "address"
        case "fp": "Core fingerprint"
        default: "secret"
        }
    }
}

/// `ainkrad://connect?host=<host[:port]>&fp=<core fingerprint>&secret=<secret>`: what the installer prints and what the Add
/// device QR carries. The fingerprint is how this Mac recognises the Core on first contact; the secret is a one-time invite.
/// It always means HTTPS (port 443 when the host names none). Claiming reuses `DevicePairing` with the invite as a QR
/// credential, so the proof of possession over the Core fingerprint is the one the pairing already has.
public struct ConnectLink: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let host: String
    public let port: Int
    public let coreFingerprint: String
    let secret: Data

    public var description: String { "ConnectLink(\(host):\(port), \(coreFingerprint))" }
    public var debugDescription: String { description }
    /// `dump` and the debugger never show the secret.
    public var customMirror: Mirror {
        Mirror(self, children: ["host": host, "port": port, "coreFingerprint": coreFingerprint])
    }

    /// An invite has no expiry on the wire, so the QR the pairing code expects gets one that never passes.
    var qr: PairingQR {
        PairingQR(host: host, port: port, coreFingerprint: coreFingerprint, secret: secret, expires: .max)
    }

    /// What to hand to `DevicePairing.claim`.
    public var credential: PairingCredential { .qr(qr) }

    /// The shortened fingerprint a person can compare by eye: the first and last characters.
    public var fingerprintHint: String { "\(coreFingerprint.prefix(8))…\(coreFingerprint.suffix(4))" }

    /// `host` or `host:port`, as shown to the person.
    public var address: String { port == 443 ? host : "\(host):\(port)" }

    public init(host: String, port: Int = 443, coreFingerprint: String, secret: Data) throws {
        guard host.allSatisfy(\.isASCII) else { throw ConnectLinkError.nonASCIIHost }
        guard Self.validHost(host), (1...65535).contains(port) else { throw ConnectLinkError.badHost }
        guard coreFingerprint.count == 43, Wire.unb64(coreFingerprint) != nil else {
            throw ConnectLinkError.badFingerprint
        }
        guard secret.count == 16 else { throw ConnectLinkError.badSecret }
        (self.host, self.port, self.coreFingerprint, self.secret) = (host, port, coreFingerprint, secret)
    }

    /// An allowlist: a DNS name (labels of letters, digits and inner hyphens, a trailing dot allowed), an IPv4 address, or a
    /// bracketed IPv6 literal. Anything else (controls, backslash, quotes, `<`, `|`, spaces) is refused.
    static func validHost(_ h: String) -> Bool {
        // `inet_pton` stops at the first NUL, and query values are percent-decoded: no control character may get that far.
        guard !h.utf8.contains(where: { $0 < 0x21 || $0 == 0x7f }) else { return false }
        if h.hasPrefix("[") {
            guard h.hasSuffix("]"), h.count > 3 else { return false }
            var addr = in6_addr()
            let inner = String(h.dropFirst().dropLast())
            // No zone id (`%25en0`) and nothing but what an address is made of.
            guard inner.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }) else { return false }
            return inner.withCString { inet_pton(AF_INET6, $0, &addr) == 1 }
        }
        var v4 = in_addr()
        if h.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 { return true }
        let name = h.hasSuffix(".") ? String(h.dropLast()) : h
        guard (1...253).contains(name.count) else { return false }
        // A name that ends in a number (`1.2.3`, `0x7f.1`, `999.1.1.1`) is an address in disguise, never a DNS name.
        let last = name.split(separator: ".", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        if last.allSatisfy(\.isNumber) || last.lowercased().hasPrefix("0x") { return false }
        return name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            (1...63).contains(label.count) && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    /// The whole fingerprint, for a link that came from another app: a person can compare it with the Core's own.
    public var fingerprintFull: String { coreFingerprint }

    /// The link as text, secret included: for the Add device QR and its Copy button. Never log it.
    public var text: String {
        "ainkrad://connect?host=\(address)&fp=\(coreFingerprint)&secret=\(Wire.b64(secret))"
    }

    /// Parses exactly one link. Unknown extra fields are ignored; a field twice is refused.
    public static func parse(_ raw: String) throws -> ConnectLink {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: t), let scheme = c.scheme else { throw ConnectLinkError.notALink }
        guard scheme.lowercased() == "ainkrad", c.host?.lowercased() == "connect" else {
            throw ConnectLinkError.wrongScheme
        }
        var fields: [String: String] = [:]
        for item in c.queryItems ?? [] where ["host", "fp", "secret"].contains(item.name) {
            guard fields.updateValue(item.value ?? "", forKey: item.name) == nil else {
                throw ConnectLinkError.duplicate(item.name)
            }
        }
        for name in ["host", "fp", "secret"] where (fields[name] ?? "").isEmpty { throw ConnectLinkError.missing(name) }
        var host = fields["host"]!
        var port = 443
        guard host.allSatisfy(\.isASCII) else { throw ConnectLinkError.nonASCIIHost }
        // A bracketed IPv6 literal keeps its colons; a port follows the closing bracket.
        let portAt: String.Index? =
            host.hasPrefix("[")
            ? host.firstIndex(of: "]").flatMap { i in
                let next = host.index(after: i)
                return host[next...].first == ":" ? next : nil
            }
            : host.lastIndex(of: ":")
        if let colon = portAt {
            guard let p = Int(host[host.index(after: colon)...]) else { throw ConnectLinkError.badHost }
            (host, port) = (String(host[..<colon]), p)
        }
        guard let secret = Wire.unb64(fields["secret"]!) else { throw ConnectLinkError.badSecret }
        return try ConnectLink(host: host, port: port, coreFingerprint: fields["fp"]!, secret: secret)
    }

    /// Finds the link in whatever was pasted: the whole installer output works, not only the link line.
    public static func find(in pasted: String) -> String? {
        pasted.split(whereSeparator: \.isWhitespace).map(String.init).first { $0.lowercased().hasPrefix("ainkrad://") }
    }
}
