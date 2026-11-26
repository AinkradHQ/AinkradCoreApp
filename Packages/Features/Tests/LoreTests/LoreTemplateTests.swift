import AppKit
import LoreEditor
import Testing

@testable import Lore

/// A template fills the blank page: the prompt goes, each empty section has a line to write on, and the caret waits
/// at the first place to write. What is typed there is what the Markdown says.
@MainActor struct LoreTemplateTests {
    /// Draws the page offscreen, as the window would.
    private func draw(_ e: LoreEditorController) {
        guard let v = e.scrollView.documentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.visibleRect) else {
            return
        }
        v.cacheDisplay(in: v.visibleRect, to: rep)
    }

    /// "X" typed where the caret lands, then the saved Markdown.
    static let typed: [String: String] = [
        "journal": "## How I feel\n\nX\n\n## What happened\n\n## Tomorrow\n",
        "meeting": "# Meeting\n\nWith: X\n\n## Notes\n\n## Actions\n",
        "checklist": "# Checklist\n\n- [ ] X\n",
        "daily": "# Daily plan\n\n## Top 3\n\n- [ ] X\n\n## Schedule\n\n## Notes\n",
        "weekly": "# Weekly review\n\n## Wins\n\n- X\n\n## Challenges\n\n## Next week\n",
        "brief": "# Project brief\n\n## Goal\n\nX\n\n## Scope\n\n## Milestones\n\n## Risks\n",
        "bug": "# Bug report\n\n## Steps\n\n1. X\n\n## Expected\n\n## Actual\n\n## Notes\n",
        "decision": "# Decision\n\n## Context\n\nX\n\n## Options\n\n## Decision\n\n## Why\n",
        "reading": "# Reading notes\n\nSource: X\n\n## Key ideas\n\n## Quotes\n\n## Thoughts\n",
    ]

    @Test(arguments: LoreTemplates.all.map(\.id)) func templateLandsTheCaretAtTheFirstPlaceToWrite(_ id: String) {
        _ = NSApplication.shared
        let t = LoreTemplates.all.first { $0.id == id }!
        let e = LoreEditorController()
        e.placeholder = "Start writing…"
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered,
            defer: false)
        w.contentView = e.scrollView
        let page = EditorPage(e)
        page.show("", fold: false)
        draw(e)
        #expect(e.placeholderShown)
        // Programmatic, the way the template button does it: no typing.
        e.insertTemplate(t)
        draw(e)
        #expect(!e.placeholderShown)
        let tv = e.scrollView.documentView as! NSTextView
        tv.insertText("X", replacementRange: tv.selectedRange())
        #expect(e.markdown() == Self.typed[id])
    }

    @Test func everyEmptySectionHasALineToWriteOn() {
        _ = NSApplication.shared
        let e = LoreEditorController()
        e.insertTemplate(LoreTemplates.all[0])
        let tv = e.scrollView.documentView as! NSTextView
        // How I feel, an empty line, What happened, an empty line, Tomorrow, the empty checklist item.
        #expect(tv.string == "How I feel\n\nWhat happened\n\nTomorrow\n\n")
        #expect(tv.selectedRange().location == ("How I feel\n" as NSString).length)
    }
}
