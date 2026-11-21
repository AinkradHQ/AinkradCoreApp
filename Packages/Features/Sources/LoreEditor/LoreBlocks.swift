import AppKit
import CoreUI
import SwiftUI

extension NSAttributedString.Key {
    /// Paragraph kind: p, h1–h6, ul, ol, task, quote, code.
    static let loreBlock = NSAttributedString.Key("loreBlock")
    static let loreLevel = NSAttributedString.Key("loreLevel")
    static let loreChecked = NSAttributedString.Key("loreChecked")
    static let loreOrdinal = NSAttributedString.Key("loreOrdinal")
    /// Code block line position for drawing (always "all": one paragraph per block).
    static let loreFence = NSAttributedString.Key("loreFence")
    /// The opening and closing lines of a raw block: "```swift"/"```", "---"/"---" (front matter), ""/"" (a table).
    static let loreCodeOpen = NSAttributedString.Key("loreCodeOpen")
    static let loreCodeClose = NSAttributedString.Key("loreCodeClose")
    static let loreBold = NSAttributedString.Key("loreBold")
    static let loreItalic = NSAttributedString.Key("loreItalic")
    /// Inline code run: drawn on a rounded well.
    static let loreCode = NSAttributedString.Key("loreCode")
    /// Note link (wikilink): the value is the note title.
    static let loreChip = NSAttributedString.Key("loreChip")
    /// A list item's marker as read (`-`, `*`, `+`, `3.`, `10)`), kept when the item is written fresh.
    static let loreMarker = NSAttributedString.Key("loreMarker")
    /// Source text the reader did not parse (plain runs, a paragraph over the limit): written back exactly, unescaped.
    /// Typed text never carries it, so what the person types is escaped as usual.
    static let loreRaw = NSAttributedString.Key("loreRaw")
    /// A raw block that is a GFM table: drawn as a grid unless the caret is inside it.
    static let loreTable = NSAttributedString.Key("loreTable")
    /// The index of the source block this paragraph was read from (see `LoreSourceMap`).
    static let loreSeq = NSAttributedString.Key("loreSeq")
}

/// What a paragraph is. Stored as attributes on the whole paragraph, never as Markdown symbols.
enum Block: Equatable {
    case p
    case h(Int)
    case ul(Int)
    case ol(Int)
    case task(Int, Bool)
    case quote, code

    var isList: Bool {
        switch self {
        case .ul, .ol, .task: true
        default: false
        }
    }
    var level: Int {
        switch self {
        case .ul(let l), .ol(let l), .task(let l, _): l
        default: 0
        }
    }
    var isHeading: Bool { if case .h = self { true } else { false } }

    func with(level l: Int) -> Block {
        switch self {
        case .ul: .ul(l)
        case .ol: .ol(l)
        case .task(_, let c): .task(l, c)
        default: self
        }
    }

    var key: String {
        switch self {
        case .p: "p"
        case .h(let n): "h\(n)"
        case .ul: "ul"
        case .ol: "ol"
        case .task: "task"
        case .quote: "quote"
        case .code: "code"
        }
    }

    static func at(_ s: NSAttributedString, _ i: Int) -> Block {
        guard s.length > 0 else { return .p }
        return from(s.attributes(at: max(0, min(i, s.length - 1)), effectiveRange: nil))
    }

    static func from(_ a: [NSAttributedString.Key: Any]) -> Block {
        let lv = a[.loreLevel] as? Int ?? 0
        let key = a[.loreBlock] as? String ?? "p"
        switch key {
        case "ul": return .ul(lv)
        case "ol": return .ol(lv)
        case "task": return .task(lv, a[.loreChecked] as? Bool ?? false)
        case "quote": return .quote
        case "code": return .code
        default:
            if key.hasPrefix("h"), let n = Int(key.dropFirst()), (1...6).contains(n) { return .h(n) }
            return .p
        }
    }
}

/// The editor's colours, all from CoreUI's `GlassInk` (Day and Night resolve per appearance). Text attributes take the
/// dynamic `NSColor`s; the fragment drawing reads `cg`, resolved on the main thread whenever the appearance changes.
enum LoreInk {
    @MainActor static let text = NSColor(GlassInk.primary)
    @MainActor static let text2 = NSColor(GlassInk.secondary)
    @MainActor static let faint = NSColor(GlassInk.track)
    @MainActor static let selection = NSColor(GlassInk.lift(0.18))

    struct Resolved: Sendable {
        var text2, faint, code, chip, box, boxOn, check, head: CGColor
    }

    /// Written on the main thread when the text view's appearance changes; read while TextKit draws (main thread).
    nonisolated(unsafe) static var cg = Resolved(
        text2: .black, faint: .black, code: .black, chip: .black, box: .black, boxOn: .black, check: .white,
        head: .black)

    @MainActor static func resolve(for appearance: NSAppearance) {
        appearance.performAsCurrentDrawingAppearance {
            cg = Resolved(
                text2: text2.cgColor, faint: faint.cgColor, code: NSColor(GlassInk.sunk(0.18)).cgColor,
                chip: NSColor(GlassInk.well).cgColor, box: faint.cgColor, boxOn: NSColor(GlassInk.blue).cgColor,
                check: NSColor(Palette.night.btnInk).cgColor, head: NSColor(GlassInk.lift(0.12)).cgColor)
        }
    }
}

/// SF Pro at the writing sizes, scaled by Settings, Appearance, Text size.
@MainActor enum Typeface {
    /// Body is the Mac title size (15 pt): a page for reading, not a form.
    static var body: CGFloat { MacTextSize.scaled(MacTextSize.title) * userScale }
    /// Lore's own Text size (Settings, Lore, Options): 0.9 small, 1 medium, 1.15 large, on top of Appearance's.
    static var userScale: CGFloat = 1
    /// h1, h2, h3; h4–h6 draw as body-sized semibold.
    static func heading(_ n: Int) -> CGFloat {
        MacTextSize.scaled([26, MacTextSize.large, 17][min(max(n, 1), 3) - 1]) * userScale
    }
    private static var cache: [String: NSFont] = [:]

    static func text(_ size: CGFloat, _ weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        let key = "\(size)|\(weight.rawValue)|\(italic)"
        if let f = cache[key] { return f }
        var d = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        if italic { d = d.withSymbolicTraits(.italic) }
        let f = NSFont(descriptor: d, size: size) ?? .systemFont(ofSize: size)
        cache[key] = f
        return f
    }

    static func mono(_ size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }
}

/// Derives fonts, colours and paragraph styles from the semantic attributes (block, bold, italic, code, chip, link).
/// Paragraph metrics are the approved prototype A's (R0-01); spacing is set per paragraph, never per source line.
@MainActor enum Style {
    static func para(_ b: Block) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 7
        switch b {
        case .p:
            p.paragraphSpacingBefore = 6
            p.paragraphSpacing = 6
        case .h(let n):
            p.paragraphSpacingBefore = [22, 18, 12][min(n, 3) - 1]
            p.paragraphSpacing = Space.s1
            p.lineSpacing = Space.s1
        case .ul, .ol, .task:
            let ind = 28 + CGFloat(b.level) * Space.s6
            p.firstLineHeadIndent = ind
            p.headIndent = ind
            p.paragraphSpacingBefore = 2
            p.paragraphSpacing = 2
        case .quote:
            p.firstLineHeadIndent = 18
            p.headIndent = 18
            p.paragraphSpacingBefore = 6
            p.paragraphSpacing = 6
        case .code:
            p.firstLineHeadIndent = Space.s4
            p.headIndent = Space.s4
            p.tailIndent = -Space.s4
            p.lineSpacing = Space.s1
            p.paragraphSpacingBefore = Space.s4
            p.paragraphSpacing = 14
        }
        return p
    }

    static func blockAttrs(_ b: Block) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.loreBlock: b.key, .loreLevel: b.level, .paragraphStyle: para(b)]
        if case .task(_, let c) = b { a[.loreChecked] = c } else { a[.loreChecked] = false }
        return a
    }

    static func runAttrs(_ b: Block, _ a: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        let bold = a[.loreBold] != nil
        let italic = a[.loreItalic] != nil
        let code = a[.loreCode] != nil
        let font: NSFont
        switch b {
        case .h(let n): font = Typeface.text(n <= 3 ? Typeface.heading(n) : Typeface.body, .semibold, italic: italic)
        case .code: font = Typeface.mono(Typeface.body - 2)
        default:
            font =
                code
                ? Typeface.mono(Typeface.body - 1.5)
                : Typeface.text(Typeface.body, bold ? .semibold : .regular, italic: italic)
        }
        let color: NSColor
        switch b {
        case .task(_, true), .quote: color = LoreInk.text2
        default: color = LoreInk.text
        }
        let link = a[.link] != nil
        return [
            .font: font, .foregroundColor: color, .kern: 0,
            .underlineStyle: link ? NSUnderlineStyle.single.rawValue : 0, .underlineColor: LoreInk.text2,
        ]
    }

    /// Re-derives everything for one paragraph from its semantic attributes.
    static func render(_ ts: NSTextStorage, _ r: NSRange) {
        guard r.length > 0, NSMaxRange(r) <= ts.length else { return }
        let b = Block.at(ts, r.location)
        ts.removeAttribute(.loreFence, range: r)
        ts.addAttributes(blockAttrs(b), range: r)
        if b == .code { ts.addAttribute(.loreFence, value: "all", range: r) }
        // A table row never wraps (the grid draws one row per line); the grid truncates what does not fit.
        if ts.attribute(.loreTable, at: r.location, effectiveRange: nil) != nil {
            let p = (para(.code).mutableCopy() as! NSMutableParagraphStyle)  // swiftlint:disable:this force_cast
            p.lineBreakMode = .byClipping
            p.lineSpacing = 10
            ts.addAttribute(.paragraphStyle, value: p, range: r)
        }
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
        ts.enumerateAttributes(in: r) { a, rr, _ in runs.append((rr, runAttrs(b, a))) }
        for (rr, a) in runs { ts.addAttributes(a, range: rr) }
        // Breathing room around inline code and note links: kern the character before and the run's last one.
        guard b != .code else { return }
        var wells: [NSRange] = []
        for key in [NSAttributedString.Key.loreCode, .loreChip] {
            ts.enumerateAttribute(key, in: r) { v, rr, _ in if v != nil { wells.append(rr) } }
        }
        for rr in wells {
            if rr.location > r.location {
                ts.addAttribute(.kern, value: 5, range: NSRange(location: rr.location - 1, length: 1))
            }
            ts.addAttribute(.kern, value: 5, range: NSRange(location: NSMaxRange(rr) - 1, length: 1))
        }
    }

    /// Renders every paragraph touching `r`.
    static func renderParagraphs(_ ts: NSTextStorage, in r: NSRange) {
        let ns = ts.string as NSString
        guard ns.length > 0 else { return }
        let loc = min(r.location, ns.length)
        let full = ns.paragraphRange(for: NSRange(location: loc, length: min(r.length, ns.length - loc)))
        ts.beginEditing()
        ns.enumerateSubstrings(in: full, options: [.byParagraphs, .substringNotRequired]) { _, _, encl, _ in
            render(ts, encl)
        }
        ts.endEditing()
    }

    static func typing(_ b: Block) -> [NSAttributedString.Key: Any] {
        var a = blockAttrs(b)
        a.merge(runAttrs(b, [:])) { $1 }
        if b == .code { a[.loreFence] = "all" }
        return a
    }

    /// Keeps the drawn numbers of ordered lists right around `location` (and the whole note when nil).
    static func renumber(_ ts: NSTextStorage, around location: Int?) {
        let ns = ts.string as NSString
        guard ns.length > 0 else { return }
        var r: NSRange
        if let location {
            r = ns.paragraphRange(for: NSRange(location: min(location, ns.length - 1), length: 0))
            if !Block.at(ts, r.location).isList {
                guard NSMaxRange(r) < ns.length else { return }
                r = ns.paragraphRange(for: NSRange(location: NSMaxRange(r), length: 0))
                guard Block.at(ts, r.location).isList else { return }
            }
            while r.location > 0 {
                let prev = ns.paragraphRange(for: NSRange(location: r.location - 1, length: 0))
                guard Block.at(ts, prev.location).isList else { break }
                r = prev
            }
        } else {
            r = ns.paragraphRange(for: NSRange(location: 0, length: 0))
        }
        var counts = [Int](repeating: 0, count: 10)
        var kinds = [String?](repeating: nil, count: 10)
        while r.location < ns.length {
            let b = Block.at(ts, r.location)
            if b.isList, r.length > 1 {
                let l = min(b.level, 9)
                for k in (l + 1)..<10 {
                    counts[k] = 0
                    kinds[k] = nil
                }
                if case .ol = b {
                    // A list that starts at 3 in the Markdown is drawn from 3.
                    let start = (ts.attribute(.loreMarker, at: r.location, effectiveRange: nil) as? String)
                        .flatMap { Int($0.dropLast()) }
                    counts[l] = kinds[l] == "ol" ? counts[l] + 1 : (start ?? 1)
                    if ts.attribute(.loreOrdinal, at: r.location, effectiveRange: nil) as? Int != counts[l] {
                        ts.addAttribute(.loreOrdinal, value: counts[l], range: r)
                    }
                }
                kinds[l] = b.key
            } else {
                if location != nil { return }
                counts = [Int](repeating: 0, count: 10)
                kinds = [String?](repeating: nil, count: 10)
            }
            let next = NSMaxRange(r)
            guard next < ns.length else { return }
            r = ns.paragraphRange(for: NSRange(location: next, length: 0))
        }
    }
}
