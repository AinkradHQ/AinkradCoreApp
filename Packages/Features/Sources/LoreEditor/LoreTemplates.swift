// LoreTemplates — quick starts for a note: headings and the right blocks (checklists where things get done). The
// blank page shows the first three and More…, the `/` menu lists them all under Template. A section with nothing
// under its heading gets an empty line to write in, and the caret waits at the first place to write.
import AppKit
import CoreUI

public struct LoreTemplate: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String
    public let markdown: String
}

public enum LoreTemplates {
    public static let all = [
        LoreTemplate(
            id: "journal", title: "Journal", symbol: "sun.max",
            markdown: "## How I feel\n\n## What happened\n\n## Tomorrow\n\n- [ ] "),
        LoreTemplate(
            id: "meeting", title: "Meeting", symbol: "person.2",
            markdown: "# Meeting\n\nWith: \n\n## Notes\n\n- \n\n## Actions\n\n- [ ] "),
        LoreTemplate(id: "checklist", title: "Checklist", symbol: "checklist", markdown: "# Checklist\n\n- [ ] "),
        LoreTemplate(
            id: "daily", title: "Daily plan", symbol: "calendar",
            markdown: "# Daily plan\n\n## Top 3\n\n- [ ] \n- [ ] \n- [ ] \n\n## Schedule\n\n## Notes"),
        LoreTemplate(
            id: "weekly", title: "Weekly review", symbol: "arrow.triangle.2.circlepath",
            markdown: "# Weekly review\n\n## Wins\n\n- \n\n## Challenges\n\n- \n\n## Next week\n\n- [ ] "),
        LoreTemplate(
            id: "brief", title: "Project brief", symbol: "doc.text",
            markdown: "# Project brief\n\n## Goal\n\n## Scope\n\n- \n\n## Milestones\n\n- [ ] \n\n## Risks\n\n- "),
        LoreTemplate(
            id: "bug", title: "Bug report", symbol: "ladybug",
            markdown: "# Bug report\n\n## Steps\n\n1. \n\n## Expected\n\n## Actual\n\n## Notes"),
        LoreTemplate(
            id: "decision", title: "Decision", symbol: "arrow.triangle.branch",
            markdown: "# Decision\n\n## Context\n\n## Options\n\n- \n\n## Decision\n\n## Why"),
        LoreTemplate(
            id: "reading", title: "Reading notes", symbol: "book",
            markdown: "# Reading notes\n\nSource: \n\n## Key ideas\n\n- \n\n## Quotes\n\n## Thoughts"),
    ]

    /// The chips on the blank page; the rest are under More….
    public static var quick: [LoreTemplate] { Array(all.prefix(3)) }

    /// Templates whose title (or a word of it) starts with `query`; all of them for an empty query.
    static func filter(_ query: String) -> [LoreTemplate] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { t in t.title.lowercased().split(separator: " ").contains { $0.hasPrefix(q) } }
    }
}

extension LoreEditorController {
    /// Puts a template on the page (all of it when the page is empty, else under the caret's line), focused, the
    /// caret at the first place to write. One undo step.
    public func insertTemplate(_ t: LoreTemplate) {
        focus()
        textView.insertTemplate(t)
    }

    /// The template list at the caret, as `/` then Template would open it: ↑ ↓, Return, typing filters, Esc closes.
    public func openTemplates() {
        focus()
        textView.tools.openInsert(typed: false, animated: true, templates: true)
    }
}

extension LoreTextView {
    func insertTemplate(_ t: LoreTemplate) {
        let pr = paraRange
        let at = content(pr).length == 0 ? pr.location : NSMaxRange(pr)
        let before = ns.length
        var slot: NSRange?
        edit {
            insertBlocks(t.markdown + "\n")
            var range = NSRange(location: at, length: max(0, ns.length - before))
            range.length += openSections(in: range)
            slot = firstSlot(in: range)
        }
        let s = slot ?? NSRange(location: ns.length, length: 0)
        setSelectedRange(NSRange(location: NSMaxRange(s), length: 0))
        typingAttributes = s.location < ts.length ? Style.typing(Block.at(ts, s.location)) : Style.typing(.p)
        scrollRangeToVisible(selectedRange())
        tools.updateGutter()
    }

    /// Every `##` or `###` in `r` with no line of its own under it gets an empty Text line (the Markdown keeps no
    /// empty paragraphs, so the template's blank lines would vanish). Returns how many characters were added.
    private func openSections(in r: NSRange) -> Int {
        var heads: [NSRange] = []
        ns.enumerateSubstrings(in: r, options: [.byParagraphs, .substringNotRequired]) { _, _, encl, _ in
            heads.append(encl)
        }
        var added = 0
        for (i, pr) in heads.enumerated().reversed() {
            guard case .h(let n) = Block.at(ts, pr.location), n >= 2 else { continue }
            let next = i + 1 < heads.count ? heads[i + 1] : nil
            if let next, !Block.at(ts, next.location).isHeading { continue }
            // On the page's last line (no newline yet) this ends it, and the empty last line is the place to write.
            replace(
                NSRange(location: NSMaxRange(pr), length: 0),
                with: NSAttributedString(string: "\n", attributes: Style.typing(.p)))
            added += 1
        }
        return added
    }

    /// The first place to write in `r`: an empty line or list item, or a label line ending with ":".
    private func firstSlot(in r: NSRange) -> NSRange? {
        var found: NSRange?
        ns.enumerateSubstrings(in: r, options: [.byParagraphs, .substringNotRequired]) { _, _, encl, stop in
            let c = self.content(encl)
            let text = self.ns.substring(with: c).trimmingCharacters(in: .whitespaces)
            if c.length == 0 || text.hasSuffix(":") {
                found = c
                stop.pointee = true
            }
        }
        // A heading that ended the page: the empty last line under it.
        if found == nil, NSMaxRange(r) >= ns.length, ns.length > 0, ns.character(at: ns.length - 1) == 10 {
            found = NSRange(location: ns.length, length: 0)
        }
        return found
    }
}
