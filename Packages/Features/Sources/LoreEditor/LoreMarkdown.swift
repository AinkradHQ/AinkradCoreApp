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
    private static let inlineRE = re(
        [
            #"\\([\\`*_\[\]#>|+.)!-])"#,  // 1 escape
            #"`([^`]+)`"#,  // 2 code
            #"\[\[([^\]\n]+)\]\]"#,  // 3 note link
            #"\[([^\]\n]+)\]\(([^)\s]+)\)"#,  // 4,5 link
            #"(https?://[^\s<>()\[\]]*[^\s<>()\[\].,;:!?'"])"#,  // 6 bare url
            #"\*\*(?=\S)(.+?)(?<=\S)\*\*"#,  // 7 bold
            #"(?<![*\w])\*(?=[^\s*])([^*\n]+?)(?<=\S)\*(?![*\w])"#,  // 8 italic
            #"(?<![_\w])_(?=[^\s_])([^_\n]+?)(?<=\S)_(?![_\w])"#,  // 9 italic
        ].joined(separator: "|"))

    /// Reads a whole note. `trailingNewline: false` drops the last paragraph's newline (pasting into a paragraph).
    static func parse(_ md: String, trailingNewline: Bool = true) -> (NSAttributedString, LoreSourceMap) {
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
            guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
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
                add(inline(g[4] ?? ""), b, i, i + 1)
            } else if let g = match(quoteRE, line) {
                add(inline(g[1] ?? ""), .quote, i, i + 1)
                indents = []
            } else {
                let a = i
                var text = t
                while i + 1 < lines.count, !startsBlock(lines[i + 1]) {
                    i += 1
                    text += " " + lines[i].trimmingCharacters(in: .whitespaces)
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
        var pos = 0
        func plain(_ s: String, _ extra: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
            NSAttributedString(string: s, attributes: base.merging(extra) { $1 })
        }
        for m in inlineRE.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > pos {
                out.append(plain(ns.substring(with: NSRange(location: pos, length: m.range.location - pos))))
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
                out.append(URL(string: u).map { plain(t, [.link: $0]) } ?? plain(ns.substring(with: m.range)))
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
        if pos < ns.length { out.append(plain(ns.substring(from: pos))) }
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
            case .p: lines = [escapeLead(body)]
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
                    alt = broke ? !alt : false
                }
                for k in (l + 1)..<10 {
                    counts[k] = 0
                    kinds[k] = nil
                }
                var marker = alt ? "*" : "-"
                if case .ol = b {
                    counts[l] = kinds[l] == "ol" ? counts[l] + 1 : 1
                    marker = "\(counts[l])" + (alt ? ")" : ".")
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
        var bold = false, italic = false, code = false
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
            sig.link = (a[.link] as? URL)?.absoluteString ?? a[.link] as? String
            let t = ns.substring(with: rr)
            if let last = segs.last, last.1 == sig { segs[segs.count - 1].0 += t } else { segs.append((t, sig)) }
        }
        return segs.map { t, sig in
            if sig.code { return "`" + t + "`" }
            if sig.chip != nil { return "[[" + t + "]]" }
            var core = t.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { return t }
            let lead = String(t.prefix { $0 == " " })
            let trail = String(t.reversed().prefix { $0 == " " })
            if let link = sig.link {
                core = core == link ? link : "[" + escape(core) + "](" + link + ")"
            } else {
                core = escape(core)
            }
            let open = sig.bold && sig.italic ? "**_" : sig.bold ? "**" : sig.italic ? "*" : ""
            return lead + open + core + String(open.reversed()) + trail
        }.joined()
    }

    private static func escape(_ t: String) -> String {
        t.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "`", with: "\\`").replacingOccurrences(of: "[[", with: "\\[[")
    }

    private static func escapeLead(_ t: String) -> String {
        for p in ["#", "- ", "+ ", "* ", "> ", "|", "```"] where t.hasPrefix(p) { return "\\" + t }
        if let r = t.range(of: #"^\d+(?=[.)] )"#, options: .regularExpression) {
            return String(t[..<r.upperBound]) + "\\" + String(t[r.upperBound...])
        }
        return t
    }
}
