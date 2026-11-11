import CryptoKit
import Foundation

/// One item in the format every collector sends (plan section 4.1; the Core's `brain-model` Item).
public struct ImportItem: Codable, Sendable, Equatable {
    public struct Origin: Codable, Sendable, Equatable {
        public var device: String
        public var path: String
        public var range: [UInt64]?
    }
    public struct Author: Codable, Sendable, Equatable {
        public var kind: String
        public var name: String
    }
    public var item_id: String
    public var source_kind: String
    public var content_hash: String
    public var origin: Origin
    public var project_hint: String?
    public var author: Author
    public var title: String
    public var text: String
    public var links: [String]
    public var started_at: String
    public var ended_at: String?
}

public enum ItemFormat {
    /// One item's text is at most this many bytes (the Core refuses more).
    public static let maxText = 256 * 1024
    /// Parts are cut a little under the cap.
    public static let partBytes = 250 * 1024

    /// Line ends as `\n`, no trailing whitespace: what the Core hashes.
    public static func normalize(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n")
        while let last = s.last, last.isWhitespace { s.removeLast() }
        return s
    }

    public static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(normalize(text).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// A deterministic 26-character Crockford id from `seed`, so a re-run makes the same ids.
    public static func itemID(seed: String) -> String {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        let digest = Array(SHA256.hash(data: Data(seed.utf8)).prefix(17))
        var bits = 0
        var acc = 0
        var out = ""
        for b in digest {
            acc = (acc << 8) | Int(b)
            bits += 8
            while bits >= 5, out.count < 26 {
                bits -= 5
                out.append(alphabet[(acc >> bits) & 31])
            }
            acc &= (1 << bits) - 1
        }
        return out
    }

    /// Splits `text` into ordered parts of at most `limit` UTF-8 bytes, at line ends where it can.
    public static func split(_ text: String, limit: Int = partBytes) -> [String] {
        guard text.utf8.count > limit else { return [text] }
        var parts: [String] = []
        var cur = ""
        var curBytes = 0
        func flush() {
            if !cur.isEmpty { parts.append(cur) }
            cur = ""
            curBytes = 0
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var piece = String(line)
            // A line longer than a part is cut at character boundaries.
            if piece.utf8.count + 1 > limit {
                flush()
                var idx = piece.startIndex
                while idx < piece.endIndex {
                    let left = piece.utf8.distance(from: idx, to: piece.endIndex)
                    var end = piece.utf8.index(idx, offsetBy: min(limit - 1, left))
                    while end > idx, end != piece.endIndex, end.samePosition(in: piece) == nil {
                        end = piece.utf8.index(before: end)
                    }
                    parts.append(String(piece[idx..<end]))
                    idx = end
                }
                continue
            }
            if curBytes + piece.utf8.count + 1 > limit { flush() }
            cur += (cur.isEmpty ? "" : "\n") + piece
            curBytes += piece.utf8.count + 1
        }
        flush()
        return parts
    }
}
