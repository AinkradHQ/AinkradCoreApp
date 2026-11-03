import CoreKit
import Foundation

/// What a person types into the first-run form, made into what CoreKit takes.
enum CodeFormat {
    /// Crockford base 32: no I, L, O or U.
    private static let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Upper case, `I`/`L` as 1, `O` as 0, anything else that is not a code character dropped, at most 10, a dash after 5.
    /// A QR payload (`ainkrad-pair:`) is left alone.
    static func format(_ typed: String) -> String {
        if isQR(typed) { return typed }
        var out = ""
        for ch in typed.uppercased() {
            let c: Character = (ch == "I" || ch == "L") ? "1" : ch == "O" ? "0" : ch
            if alphabet.contains(c), out.count < 10 { out.append(c) }
        }
        return out.count > 5 ? "\(out.prefix(5))-\(out.dropFirst(5))" : out
    }

    static func isQR(_ typed: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("ainkrad-pair:")
    }

    /// Ten code characters typed so far (or a QR payload, which has its own checks).
    static func isComplete(_ typed: String) -> Bool {
        isQR(typed) ? true : format(typed).replacingOccurrences(of: "-", with: "").count == 10
    }
}

enum EndpointInput {
    /// `https://host[:port]`, or just `host[:port]` (https), or `http://127.0.0.1:port` for a Core on this Mac.
    static func parse(_ text: String) throws -> URL {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw CoreError.invalidInput("Enter the address of your Core.") }
        let withScheme = t.contains("://") ? t : "\(isLoopback(t) ? "http" : "https")://\(t)"
        guard let url = URL(string: withScheme) else { throw CoreError.invalidInput("That is not an address.") }
        return try CoreEndpoint(url).url
    }

    private static func isLoopback(_ t: String) -> Bool {
        ["127.0.0.1", "localhost", "[::1]"].contains { t == $0 || t.hasPrefix("\($0):") }
    }
}
