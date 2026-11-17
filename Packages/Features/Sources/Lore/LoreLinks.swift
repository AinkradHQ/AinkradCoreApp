import Foundation

/// The host's gate for internal links (security review of R6-02). The editor hands every `lore:` and `lore-attachment:`
/// URL from note text to the host unchecked, so this is the only check: `lore:<note id>` opens that note in the space,
/// `lore-attachment:<64 hex sha256>` goes to the in-app viewer (never `NSWorkspace.open`). Anything else is refused.
enum LoreLink: Equatable {
    case note(String)
    case attachment(String)

    init?(_ url: URL) {
        // `opaque` form only: `lore:ln_…`, no `//`, no query, no fragment, no percent escapes.
        let s = url.absoluteString
        guard let colon = s.firstIndex(of: ":") else { return nil }
        let scheme = s[..<colon].lowercased()
        let rest = String(s[s.index(after: colon)...])
        switch scheme {
        case "lore" where Self.isNoteID(rest): self = .note(rest)
        case "lore-attachment" where Self.isSHA(rest): self = .attachment(rest)
        default: return nil
        }
    }

    /// `ln_` and 12 base32 characters (a-z, 2-7), as the Core makes them.
    static func isNoteID(_ s: String) -> Bool {
        s.utf8.count == 15 && s.hasPrefix("ln_")
            && s.utf8.dropFirst(3).allSatisfy { (0x61...0x7a).contains($0) || (0x32...0x37).contains($0) }
    }

    /// 64 lowercase hex characters.
    static func isSHA(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }
}
