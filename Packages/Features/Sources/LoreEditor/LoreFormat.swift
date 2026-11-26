// LoreFormat — the editor tools' edits: inline marks (bold, italic, strike, code, link), block types, and the blocks the
// insert menu adds. Marks and blocks are the same attributes typing makes, so the page re-renders as today and the
// Markdown that is saved is plain `**…**`, `# `, `- [ ] `. Every edit is one undo step.
import AppKit
import CoreUI

/// An inline mark the selection bar toggles.
public enum LoreMark: String, CaseIterable, Sendable {
    case bold, italic, strike, code

    var key: NSAttributedString.Key {
        switch self {
        case .bold: .loreBold
        case .italic: .loreItalic
        case .strike: .loreStrike
        case .code: .loreCode
        }
    }
}

enum LoreFormat {
    /// Every character of `r` that can carry a mark has `m` (an empty range or one with nothing markable: false).
    static func has(_ m: LoreMark, in s: NSAttributedString, _ r: NSRange) -> Bool {
        var any = false
        var all = true
        markable(s, r) { rr in
            any = true
            s.enumerateAttribute(m.key, in: rr) { v, _, stop in
                if v == nil {
                    all = false
                    stop.pointee = true
                }
            }
        }
        return any && all
    }

    /// Adds `m` to `r`, or takes it off when every character has it already. Code blocks, newlines and note links are
    /// left alone; inline code drops the other marks (Markdown has no bold code).
    static func toggle(_ m: LoreMark, in s: NSMutableAttributedString, _ r: NSRange) {
        let on = !has(m, in: s, r)
        markable(s, r) { rr in
            if on {
                s.addAttribute(m.key, value: true, range: rr)
                if m == .code { for k in [LoreMark.bold, .italic, .strike] { s.removeAttribute(k.key, range: rr) } }
            } else {
                s.removeAttribute(m.key, range: rr)
            }
        }
    }

    /// The runs of `r` a mark can go on: not code blocks, not note links, not line ends.
    private static func markable(_ s: NSAttributedString, _ r: NSRange, _ body: (NSRange) -> Void) {
        let ns = s.string as NSString
        guard r.length > 0, NSMaxRange(r) <= ns.length else { return }
        s.enumerateAttributes(in: r) { a, rr, _ in
            guard a[.loreChip] == nil, (a[.loreBlock] as? String) != "code" else { return }
            var start = rr.location
            for i in rr.location..<NSMaxRange(rr) {
                let c = ns.character(at: i)
                if c == 10 || c == 13 || c == 0x2029 {
                    if i > start { body(NSRange(location: start, length: i - start)) }
                    start = i + 1
                }
            }
            if NSMaxRange(rr) > start { body(NSRange(location: start, length: NSMaxRange(rr) - start)) }
        }
    }

    /// The block a paragraph becomes: a list keeps its level when it changes kind.
    static func target(_ b: Block, from current: Block) -> Block {
        b.isList && current.isList ? b.with(level: current.level) : b
    }

    /// A 3 × 3 table: a header and two empty rows, drawn as a grid by the table renderer.
    static let table = "| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n|  |  |  |\n|  |  |  |\n"

    /// Today's date and time, the way this Mac writes them ("26 November 2026 at 14:05").
    static func stamp(_ d: Date = Date()) -> String { d.formatted(date: .long, time: .shortened) }

    /// A web or mail address someone typed; nil for anything a link must not be (file:, javascript:, no host).
    static func address(_ typed: String) -> URL? {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        let full = t.contains(":") ? t : (t.contains("@") ? "mailto:" + t : "https://" + t)
        guard let u = URL(string: full), LoreLinkPolicy.action(for: u) == .open else { return nil }
        return u
    }
}

// MARK: - the text view's tool edits

extension LoreTextView {
    /// The paragraphs the selection touches (the caret's one when nothing is selected).
    var selectedParagraphs: [NSRange] {
        let sel = selectedRange()
        var out: [NSRange] = []
        let full = ns.paragraphRange(for: sel)
        if full.length == 0 { return [full] }
        ns.enumerateSubstrings(in: full, options: [.byParagraphs, .substringNotRequired]) { _, _, encl, _ in
            out.append(encl)
        }
        return out
    }

    /// The marks every character of the selection has (or the typing attributes have, with a caret).
    var activeMarks: Set<LoreMark> {
        let sel = selectedRange()
        if sel.length == 0 { return Set(LoreMark.allCases.filter { typingAttributes[$0.key] != nil }) }
        return Set(LoreMark.allCases.filter { LoreFormat.has($0, in: ts, sel) })
    }

    var selectionHasLink: Bool {
        let sel = selectedRange()
        guard sel.length > 0 else { return false }
        var found = false
        ts.enumerateAttribute(.link, in: sel) { v, _, stop in
            if v != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// Bold, italic, strike or code on the selection; with a caret, for the text typed next.
    func applyMark(_ m: LoreMark) {
        let sel = selectedRange()
        guard currentBlock() != .code else { return }
        guard sel.length > 0 else {
            if typingAttributes[m.key] != nil { typingAttributes[m.key] = nil } else { typingAttributes[m.key] = true }
            typingAttributes.merge(Style.runAttrs(currentBlock(), typingAttributes)) { $1 }
            return
        }
        guard shouldChangeText(in: sel, replacementString: nil) else { return }
        edit {
            ts.beginEditing()
            LoreFormat.toggle(m, in: ts, sel)
            Style.renderParagraphs(ts, in: sel)
            ts.endEditing()
            didChangeText()
        }
        setSelectedRange(sel)
    }

    /// Puts a link on the selection (nil takes it off).
    func applyLink(_ url: URL?) {
        let sel = selectedRange()
        guard sel.length > 0, shouldChangeText(in: sel, replacementString: nil) else { return }
        edit {
            ts.beginEditing()
            if let url { ts.addAttribute(.link, value: url, range: sel) } else { ts.removeAttribute(.link, range: sel) }
            Style.renderParagraphs(ts, in: sel)
            ts.endEditing()
            didChangeText()
        }
        setSelectedRange(sel)
    }

    /// Every paragraph the selection touches becomes `b` (a list keeps its level). Tables and rules stay raw.
    func applyBlock(_ b: Block) {
        let sel = selectedRange()
        let paras = selectedParagraphs
        edit {
            for pr in paras.reversed() {
                let raw =
                    pr.length > 0
                    && (ts.attribute(.loreTable, at: pr.location, effectiveRange: nil) != nil
                        || ts.attribute(.loreRule, at: pr.location, effectiveRange: nil) != nil)
                guard !raw else { continue }
                let cur = pr.length == 0 ? currentBlock() : Block.at(ts, pr.location)
                setBlock(LoreFormat.target(b, from: cur), paragraph: pr, updateTyping: false)
            }
        }
        let at = min(sel.location, ts.length)
        setSelectedRange(NSRange(location: at, length: min(sel.length, ts.length - at)))
        typingAttributes = Style.typing(currentBlock())
        tools.updateGutter()
    }

    /// Inserts whole blocks (a table, a rule) as Markdown: in place of an empty paragraph, else after the caret's one.
    /// The caret lands on the empty line after them, ready to type.
    func insertBlocks(_ md: String) {
        let pr = paraRange
        let empty = content(pr).length == 0
        let blocks = NSMutableAttributedString(attributedString: MarkdownReader.parse(md).0)
        blocks.removeAttribute(.loreSeq, range: NSRange(location: 0, length: blocks.length))
        let size = blocks.length
        edit {
            var at = empty ? pr.location : NSMaxRange(pr)
            // The last paragraph has no newline of its own yet: it gets one, with its own attributes.
            if !empty, at == ts.length, at > 0, ns.character(at: at - 1) != 10 {
                let own = ts.attributes(at: at - 1, effectiveRange: nil)
                replace(NSRange(location: at, length: 0), with: NSAttributedString(string: "\n", attributes: own))
                at += 1
            }
            // After a paragraph with text below it, an empty line gives the caret a place of its own.
            if !empty, at < ts.length { blocks.append(NSAttributedString(string: "\n", attributes: Style.typing(.p))) }
            replace(NSRange(location: at, length: 0), with: blocks)
            let end = at + size
            // The empty line the blocks went in front of is a plain one now.
            if empty, end < ts.length {
                setBlock(.p, paragraph: NSRange(location: end, length: 1), updateTyping: false)
            }
            setSelectedRange(NSRange(location: end, length: 0))
        }
        Style.renumber(ts, around: nil)
        typingAttributes = Style.typing(.p)
        tools.updateGutter()
    }

    /// `---` typed on a Text line is a divider.
    func ruleTrigger() {
        let pr = paraRange
        guard currentBlock() == .p, ns.substring(with: content(pr)) == "---" else { return }
        makeRule(pr)
    }

    /// Turns the caret's paragraph (`---` typed) into a rule and moves the caret to a new line under it.
    func makeRule(_ pr: NSRange) {
        let c = content(pr)
        edit {
            replace(c, with: "")
            setSelectedRange(NSRange(location: c.location, length: 0))
            insertBlocks("---\n")
        }
    }

    /// Plain text at the caret, as if typed (the date stamp).
    func insertPlain(_ s: String) {
        typingAttributes[.loreRaw] = nil
        let r = selectedRange()
        edit { replace(r, with: s) }
        setSelectedRange(NSRange(location: r.location + (s as NSString).length, length: 0))
    }
}
