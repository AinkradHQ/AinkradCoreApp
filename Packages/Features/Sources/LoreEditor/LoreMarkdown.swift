import AppKit

/// Where each paragraph came from in the Markdown that was loaded, so saving gives the same bytes back (plan T1).
/// A paragraph whose canonical Markdown still equals what it was at load is written as its original source lines; a
/// changed one is written fresh. Only edited blocks change; open + save without edits is byte-identical.
struct LoreSourceMap {
    struct Source {
        /// Raw lines between the previous block and this one (for block 0: the lines before it).
        var gap: [String]
        var lines: [String]
    }
    var blocks: [Source] = []
    /// Each block's canonical lines as read, compared with the current ones at save.
    var canon: [[String]?] = []
    /// Raw lines after the last block (`[""]` is the trailing newline).
    var tail: [String] = [""]
}

/// Markdown → attributed paragraphs (symbols become attributes).
@MainActor enum MarkdownReader {
    private static func re(_ p: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: p)
    }
    private static let headingRE = re(#"^(#{1,6})\s+(.*)$"#)
    private static let listRE = re(#"^([ \t]*)([-*+]|\d+[.)])\s+(?:\[( |x|X)\]\s+)?(.*)$"#)
    private static let quoteRE = re(#"^\s*>\s?(.*)$"#)
    /// Every quantifier is bounded, so a hostile line costs at most a few hundred steps per position (imports and AI
    /// sessions write notes: an unbounded `.+?` made a 40 KB line of `[[` take 98 s).
    private static let inlineRE = re(
        [
            #"\\([\\`*_\[\]#>|+.)!-])"#,  // 1 escape
            #"`([^`\n]{1,256})`"#,  // 2 code
            #"\[\[([^\[\]\n]{1,256})\]\]"#,  // 3 note link
            #"\[([^\[\]\n]{1,256})\]\(([^()\s]{1,2048})\)"#,  // 4,5 link
            #"(https?://[^\s<>()\[\]]{0,2048}[^\s<>()\[\].,;:!?'"])"#,  // 6 bare url
            #"\*\*(?=\S)([^*\n]{1,256}?)(?<=\S)\*\*"#,  // 7 bold
            #"(?<![*\w])\*(?=[^\s*])([^*\n]{1,256}?)(?<=\S)\*(?![*\w])"#,  // 8 italic
            #"(?<![_\w])_(?=[^\s_])([^_\n]{1,256}?)(?<=\S)_(?![_\w])"#,  // 9 italic
        ].joined(separator: "|"))
    /// A paragraph longer than this is shown as plain text, with no inline parse at all.
    static let inlineLimit = 4096
    /// At most this many inline spans per paragraph, and per note; the rest is plain text. Each span costs styling work
    /// (a 2 MB note packed with code spans took 27 s to load), so the whole load stays bounded.
    static let spansPerParagraph = 200
    static let spansPerNote = 10_000
    /// Spans left for the note being read.
    private static var budget = Int.max

    /// Reads a whole note. `trailingNewline: false` drops the last paragraph's newline (pasting into a paragraph).
    static func parse(_ md: String, trailingNewline: Bool = true) -> (NSAttributedString, LoreSourceMap) {
        budget = spansPerNote
        defer { budget = Int.max }
        let out = NSMutableAttributedString()
        // Raw lines keep a CRLF's "\r" for the source map; the parser sees the line without it.
        let raw = md.components(separatedBy: "\n")
        let lines = raw.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var map = LoreSourceMap()
        var prevEnd = 0
        var indents: [Int] = []
        var lastWasList = false
        func add(
            _ content: NSAttributedString, _ b: Block, _ a: Int, _ e: Int, _ extra: [NSAttributedString.Key: Any] = [:]
        ) {
            // Two list items with a blank line between them stay apart: an empty paragraph keeps the gap you see.
            if b.isList && lastWasList && prevEnd < a {
                out.append(NSAttributedString(string: "\n", attributes: Style.blockAttrs(.p)))
            }
            lastWasList = b.isList
            let p = NSMutableAttributedString(attributedString: content)
            p.append(NSAttributedString(string: "\n"))
            var attrs = Style.blockAttrs(b).merging(extra) { $1 }
            attrs[.loreSeq] = map.blocks.count
            p.addAttributes(attrs, range: NSRange(location: 0, length: p.length))
            out.append(p)
            map.blocks.append(.init(gap: Array(raw[prevEnd..<a]), lines: Array(raw[a..<e])))
            prevEnd = e
        }
        func match(_ re: NSRegularExpression, _ s: String) -> [String?]? {
            let ns = s as NSString
            // Anchored: every line rule starts at `^`, so a long line costs one attempt, not one per character.
            guard let m = re.firstMatch(in: s, options: .anchored, range: NSRange(location: 0, length: ns.length))
            else {
                return nil
            }
            return (0..<m.numberOfRanges).map {
                m.range(at: $0).location == NSNotFound ? nil : ns.substring(with: m.range(at: $0))
            }
        }
        func startsBlock(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.isEmpty || t.hasPrefix("```") || t.hasPrefix("|") || match(headingRE, s) != nil
                || match(listRE, s) != nil || match(quoteRE, s) != nil
        }
        func rawBlock(_ a: Int, _ e: Int, open: String, close: String) {
            add(
                NSAttributedString(string: lines[a..<e].joined(separator: "\u{2028}")), .code,
                a - (open.isEmpty ? 0 : 1), e + (close.isEmpty ? 0 : 1), [.loreCodeOpen: open, .loreCodeClose: close])
            indents = []
        }

        var i = 0
        // Front matter: shown as a raw block, written back as it was.
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            rawBlock(1, end, open: "---", close: "---")
            i = end + 1
        }
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                i += 1
                continue
            }
            if t.hasPrefix("```") {
                var e = i + 1
                while e < lines.count, !lines[e].trimmingCharacters(in: .whitespaces).hasPrefix("```") { e += 1 }
                // An unclosed fence runs to the end; its trailing blank lines stay outside it.
                let closed = e < lines.count
                if !closed { while e > i + 1, lines[e - 1].trimmingCharacters(in: .whitespaces).isEmpty { e -= 1 } }
                rawBlock(i + 1, e, open: line, close: closed ? lines[e] : "")
                i = closed ? e + 1 : e
                continue
            }
            // Tables stay text (mono, on a well): every edit is plain typing, so undo and the source never disagree.
            if t.hasPrefix("|"), i + 1 < lines.count, lines[i + 1].contains("---") {
                var e = i + 2
                while e < lines.count, lines[e].trimmingCharacters(in: .whitespaces).hasPrefix("|") { e += 1 }
                rawBlock(i, e, open: "", close: "")
                i = e
                continue
            }
            if let g = match(headingRE, line) {
                add(inline(g[2] ?? ""), .h(g[1]!.count), i, i + 1)
                indents = []
            } else if let g = match(listRE, line) {
                let indent = g[1]!.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                while let last = indents.last, indent < last { indents.removeLast() }
                if indents.isEmpty || indent > indents.last! { indents.append(indent) }
                let level = indents.count - 1
                let b: Block =
                    if let box = g[3] { .task(level, box != " ") } else if g[2]!.first!.isNumber { .ol(level) } else {
                        .ul(level)
                    }
                // The item's own marker (`*`, `+`, `-`, `3.`, `10)`) is kept for when it is written fresh.
                add(inline(g[4] ?? ""), b, i, i + 1, [.loreMarker: g[2]!])
            } else if let g = match(quoteRE, line) {
                add(inline(g[1] ?? ""), .quote, i, i + 1)
                indents = []
            } else {
                let a = i
                // Soft-wrapped lines flow as one paragraph (Apple Notes). A hard break (two trailing spaces or a trailing
                // backslash) stays a line break (U+2028), with the next line's indentation. Untouched, the paragraph is
                // saved as its original bytes anyway; once edited, soft wraps are written as one line.
                var text = String(line.drop { $0 == " " || $0 == "\t" })
                while i + 1 < lines.count, !startsBlock(lines[i + 1]) {
                    let hard = lines[i].hasSuffix("  ") || lines[i].hasSuffix("\\")
                    i += 1
                    if hard {
                        text += "\u{2028}" + lines[i]
                    } else {
                        if !text.hasSuffix(" ") { text += " " }
                        // Leading space only: trailing spaces may be the next hard break.
                        text += String(lines[i].drop { $0 == " " || $0 == "\t" })
                    }
                }
                add(inline(text), .p, a, i + 1)
                indents = []
            }
            i += 1
        }
        map.tail = Array(raw[min(prevEnd, raw.count)...])
        if !trailingNewline, out.length > 0 { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        let ts = NSTextStorage(attributedString: out)
        Style.renderParagraphs(ts, in: NSRange(location: 0, length: ts.length))
        Style.renumber(ts, around: nil)
        map.canon = Array(repeating: nil, count: map.blocks.count)
        for e in MarkdownWriter.entries(ts) { if let s = e.seq, s < map.canon.count { map.canon[s] = e.lines } }
        return (ts, map)
    }

    static func inline(_ text: String, _ base: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let ns = text as NSString
        // Source text that was not parsed is marked raw: the writer copies it out as it was, never escaped.
        var rawBase = base
        rawBase[.loreRaw] = true
        guard ns.length <= inlineLimit else { return NSAttributedString(string: text, attributes: rawBase) }
        var pos = 0
        func plain(_ s: String, _ extra: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
            NSAttributedString(string: s, attributes: base.merging(extra) { $1 })
        }
        func raw(_ r: NSRange) -> NSAttributedString {
            NSAttributedString(string: ns.substring(with: r), attributes: rawBase)
        }
        var matches: [NSTextCheckingResult] = []
        let cap = min(spansPerParagraph, max(0, budget))
        if cap > 0 {
            inlineRE.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, stop in
                if let m { matches.append(m) }
                if matches.count >= cap { stop.pointee = true }
            }
        }
        budget -= matches.count
        for m in matches {
            if m.range.location > pos {
                out.append(raw(NSRange(location: pos, length: m.range.location - pos)))
            }
            func g(_ i: Int) -> String? {
                m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
            }
            if let e = g(1) {
                out.append(plain(e))
            } else if let c = g(2) {
                out.append(plain(c, [.loreCode: true]))
            } else if let t = g(3) {
                out.append(plain(t, [.loreChip: t]))
            } else if let t = g(4), let u = g(5) {
                // A link we cannot parse stays text, exactly as written.
                out.append(URL(string: u).map { plain(t, [.link: $0]) } ?? raw(m.range))
            } else if let u = g(6) {
                out.append(plain(u, URL(string: u).map { [.link: $0] } ?? [:]))
            } else if let b = g(7) {
                let inner = NSMutableAttributedString(attributedString: inline(b, base))
                inner.addAttribute(.loreBold, value: true, range: NSRange(location: 0, length: inner.length))
                out.append(inner)
            } else if let it = g(8) ?? g(9) {
                let inner = NSMutableAttributedString(attributedString: inline(it, base))
                inner.addAttribute(.loreItalic, value: true, range: NSRange(location: 0, length: inner.length))
                out.append(inner)
            }
            pos = NSMaxRange(m.range)
        }
        if pos < ns.length { out.append(raw(NSRange(location: pos, length: ns.length - pos))) }
        return out
    }
}

/// Attributed paragraphs → Markdown.
@MainActor enum MarkdownWriter {
    struct Entry {
        var seq: Int?
        var lines: [String]
        /// A blank line goes before it when it is written fresh.
        var blank: Bool
    }

    /// The note as Markdown. With the map from `parse`, unchanged blocks keep their original bytes (T1).
    static func markdown(_ s: NSAttributedString, map: LoreSourceMap? = nil) -> String {
        var out: [String] = []
        var prevSeq = -1
        var started = false
        for e in entries(s) {
            var unchanged = false
            var adjacent = false
            if let seq = e.seq, let map, seq < map.blocks.count {
                unchanged = map.canon[seq] == e.lines
                adjacent = seq == prevSeq + 1
            }
            if adjacent, let map, let seq = e.seq {
                out += map.blocks[seq].gap
            } else if started && e.blank {
                out.append("")
            }
            if unchanged, let map, let seq = e.seq { out += map.blocks[seq].lines } else { out += e.lines }
            prevSeq = e.seq ?? -2
            started = true
        }
        guard started else { return map.map { $0.blocks.isEmpty ? $0.tail.joined(separator: "\n") : "" } ?? "" }
        if let map, prevSeq == map.blocks.count - 1 { out += map.tail } else { out.append("") }
        return out.joined(separator: "\n")
    }

    /// One entry per written paragraph, in order, with canonical lines.
    static func entries(_ s: NSAttributedString) -> [Entry] {
        let ns = s.string as NSString
        var out: [Entry] = []
        var prev: Block?
        var counts = [Int](repeating: 0, count: 10)
        var kinds = [String?](repeating: nil, count: 10)
        var widths = [Int](repeating: 2, count: 10)
        // An empty paragraph ended the last list; the next list then takes the other marker, so it stays a second list.
        var broke = false
        var alt = false
        var bullets = [String?](repeating: nil, count: 10)
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]
        ) { _, r, _, _ in
            func endList() {
                if prev?.isList == true { broke = true }
                if prev != nil { prev = .p }
            }
            guard r.length > 0 else { return endList() }
            let b = Block.at(s, r.location)
            let body = b == .code ? ns.substring(with: r) : inline(s, r, heading: b.isHeading)
            if b != .code && body.trimmingCharacters(in: .whitespaces).isEmpty { return endList() }
            let seq = s.attribute(.loreSeq, at: r.location, effectiveRange: nil) as? Int
            var blank = false
            if let p = prev, !(p.isList && b.isList), !(p == .quote && b == .quote) { blank = true }
            var lines: [String]
            switch b {
            case .p: lines = body.components(separatedBy: "\u{2028}").map(escapeLead)
            case .h(let n): lines = [String(repeating: "#", count: n) + " " + body]
            case .quote: lines = ["> " + body]
            case .code:
                let open = s.attribute(.loreCodeOpen, at: r.location, effectiveRange: nil) as? String ?? "```"
                let close = s.attribute(.loreCodeClose, at: r.location, effectiveRange: nil) as? String ?? "```"
                lines =
                    (open.isEmpty ? [] : [open]) + body.components(separatedBy: "\u{2028}")
                    + (close.isEmpty ? [] : [close])
            case .ul, .ol, .task:
                let l = min(b.level, 9)
                if !(prev?.isList ?? false) {
                    counts = [Int](repeating: 0, count: 10)
                    kinds = [String?](repeating: nil, count: 10)
                    bullets = [String?](repeating: nil, count: 10)
                    alt = broke ? !alt : false
                }
                for k in (l + 1)..<10 {
                    counts[k] = 0
                    kinds[k] = nil
                    bullets[k] = nil
                }
                // The item's own marker as read, else the one above it in this list, else the default.
                let own = s.attribute(.loreMarker, at: r.location, effectiveRange: nil) as? String
                var marker: String
                if case .ol = b {
                    let numbered = own.flatMap { $0.first?.isNumber == true ? $0 : nil }
                    let start = numbered.flatMap { Int($0.dropLast()) }
                    counts[l] = kinds[l] == "ol" ? counts[l] + 1 : (start ?? 1)
                    let delim = numbered.map { String($0.suffix(1)) } ?? (kinds[l] == "ol" ? bullets[l] : nil)
                    marker = "\(counts[l])" + (delim ?? (alt ? ")" : "."))
                    bullets[l] = String(marker.suffix(1))
                } else {
                    let ownBullet = own.flatMap { ["-", "*", "+"].contains($0) ? $0 : nil }
                    marker = ownBullet ?? (kinds[l] == "ol" ? nil : bullets[l]) ?? (alt ? "*" : "-")
                    bullets[l] = marker
                }
                if case .task(_, let c) = b { marker += c ? " [x]" : " [ ]" }
                kinds[l] = b.key
                widths[l] = b.key == "ol" ? marker.count + 1 : 2
                lines = [String(repeating: " ", count: widths[0..<l].reduce(0, +)) + marker + " " + body]
            }
            if !b.isList { broke = false }
            out.append(Entry(seq: seq, lines: lines, blank: blank))
            prev = b
        }
        return out
    }

    private struct Sig: Equatable {
        var bold = false, italic = false, code = false, raw = false
        var chip: String?, link: String?
    }

    /// One paragraph's runs as inline Markdown.
    static func inline(_ s: NSAttributedString, _ r: NSRange, heading: Bool = false) -> String {
        var segs: [(String, Sig)] = []
        let ns = s.string as NSString
        s.enumerateAttributes(in: r) { a, rr, _ in
            if a[.attachment] != nil { return }
            var sig = Sig()
            sig.bold = !heading && a[.loreBold] != nil
            sig.italic = a[.loreItalic] != nil
            sig.code = a[.loreCode] != nil
            sig.chip = a[.loreChip] as? String
            sig.raw = a[.loreRaw] != nil
            sig.link = (a[.link] as? URL)?.absoluteString ?? a[.link] as? String
            let t = ns.substring(with: rr)
            if let last = segs.last, last.1 == sig { segs[segs.count - 1].0 += t } else { segs.append((t, sig)) }
        }
        return segs.map { t, sig in
            if sig.code { return "`" + t + "`" }
            if sig.chip != nil { return "[[" + t + "]]" }
            // Raw source text goes out as it came in.
            if sig.raw && !sig.bold && !sig.italic && sig.link == nil { return t }
            var core = t.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { return t }
            let lead = String(t.prefix { $0 == " " })
            let trail = String(t.reversed().prefix { $0 == " " })
            if let link = sig.link {
                core = core == link ? link : "[" + escape(core) + "](" + link + ")"
            } else if !sig.raw {
                core = escape(core)
            }
            let open = sig.bold && sig.italic ? "**_" : sig.bold ? "**" : sig.italic ? "*" : ""
            return lead + open + core + String(open.reversed()) + trail
        }.joined()
    }

    /// Every character the reader treats as inline syntax, so text written fresh reads back as the same text. A
    /// backslash that ends a line (U+2028 next) is a hard break and stays as it is. Works on UTF-8 bytes: the escaped
    /// characters are all ASCII, and a 100 KB line must stay a few milliseconds even in a Debug build.
    static func escape(_ t: String) -> String {
        var t = t
        return t.withUTF8 { b -> String in
            var out = [UInt8]()
            out.reserveCapacity(b.count + b.count / 8)
            let n = b.count
            var i = 0
            while i < n {
                let c = b[i]
                switch c {
                case 0x2A, 0x60, 0x5B, 0x5D, 0x5F: out.append(0x5C)  // * ` [ ] _
                case 0x5C where !(i + 3 < n && b[i + 1] == 0xE2 && b[i + 2] == 0x80 && b[i + 3] == 0xA8):
                    out.append(0x5C)
                default: break
                }
                out.append(c)
                i += 1
            }
            return String(decoding: out, as: UTF8.self)
        }
    }

    private static func escapeLead(_ t: String) -> String {
        for p in ["#", "- ", "+ ", "* ", "> ", "|", "```"] where t.hasPrefix(p) { return "\\" + t }
        if let r = t.range(of: #"^\d+(?=[.)] )"#, options: [.regularExpression, .anchored]) {
            return String(t[..<r.upperBound]) + "\\" + String(t[r.upperBound...])
        }
        return t
    }
}
