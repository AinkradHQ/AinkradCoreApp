import AppKit
import LoreEditor
import Testing

@testable import Lore

/// A template fills the blank page: the prompt goes, and the caret waits on the template's last item.
@MainActor struct LoreTemplateTests {
    /// Draws the page offscreen, as the window would.
    private func draw(_ e: LoreEditorController) {
        guard let v = e.scrollView.documentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.visibleRect) else {
            return
        }
        v.cacheDisplay(in: v.visibleRect, to: rep)
    }

    @Test(arguments: LoreTemplates.all.map(\.id)) func templateHidesThePromptAndTypesIntoTheLastItem(_ id: String) {
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
        // Programmatic, the way the template button does it: no typing, no didChangeText.
        page.show(t.markdown, fold: false)
        page.caretToEnd()
        draw(e)
        #expect(!e.placeholderShown)
        let tv = e.scrollView.documentView as! NSTextView
        w.makeFirstResponder(tv)
        tv.insertText("Next", replacementRange: tv.selectedRange())
        #expect(e.markdown().hasSuffix("- [ ] Next"))
    }
}
