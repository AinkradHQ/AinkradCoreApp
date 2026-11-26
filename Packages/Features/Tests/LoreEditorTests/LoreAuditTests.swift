import AppKit
import Testing

@testable import LoreEditor

/// The editor audit (2026-11-26): typing, the Markdown shortcuts, lists, undo, Arabic and emoji, each checked by what the
/// Markdown says afterwards. The page sits in a window, so undo works as it does in the app.
@MainActor struct LoreAuditTests {
    private func page(_ md: String) -> (LoreEditorController, LoreTextView, NSWindow) {
        let c = editor(md)
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered,
            defer: true)
        w.contentView = c.scrollView
        w.makeFirstResponder(c.textView)
        c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
        return (c, c.textView, w)
    }

    private func type(_ tv: LoreTextView, _ s: String) {
        for ch in s {
            if ch == "\n" {
                tv.insertNewline(nil)
            } else {
                tv.insertText(String(ch), replacementRange: tv.selectedRange())
            }
        }
    }

    @Test func shortcutsTurnIntoBlocks() {
        let (c, tv, _) = page("")
        type(tv, "# Title\n## Sub\n> said\n\n- one\n")
        type(tv, "\n")
        type(tv, "1. first\n\n[ ] task\nnext\n\n")
        // A list of another kind right under one that ended is a list of its own in Markdown already.
        let md = "# Title\n\n## Sub\n\n> said\n\n- one\n1. first\n- [ ] task\n- [ ] next\n"
        #expect(c.markdown() == md)
        #expect(editor(md).markdown() == md)
    }

    @Test func returnOnAnEmptyItemEndsTheList() {
        let (c, tv, _) = page("")
        type(tv, "- a\nb\n\nafter")
        #expect(c.markdown() == "- a\n- b\n\nafter\n")
    }

    @Test func tabAndShiftTabNestAListItem() {
        let (c, tv, _) = page("")
        type(tv, "- a\nb")
        tv.insertTab(nil)
        #expect(c.markdown() == "- a\n  - b\n")
        tv.insertBacktab(nil)
        #expect(c.markdown() == "- a\n- b\n")
    }

    @Test func backspaceAtTheStartOfAHeadingOrQuoteMakesText() {
        let (c, tv, _) = page("## Head\n\n> Quote\n")
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.deleteBackward(nil)
        let q = (tv.string as NSString).range(of: "Quote").location
        tv.setSelectedRange(NSRange(location: q, length: 0))
        tv.deleteBackward(nil)
        #expect(c.markdown() == "Head\n\nQuote\n")
    }

    @Test func fenceTypingAndTabInCode() {
        let (c, tv, _) = page("")
        type(tv, "```")
        tv.insertTab(nil)
        type(tv, "let a = 1\nlet b = 2\n\n")
        type(tv, "after")
        #expect(c.markdown() == "```\n    let a = 1\nlet b = 2\n```\n\nafter\n")
    }

    @Test func dividerFromThreeDashes() {
        let (c, tv, _) = page("")
        type(tv, "above\n---")
        type(tv, "below")
        #expect(c.markdown() == "above\n\n---\n\nbelow\n")
    }

    @Test func inlineMarksFromTyping() {
        let (c, tv, _) = page("")
        type(tv, "a **bold** and *it* and `code` and ~~gone~~")
        #expect(c.markdown() == "a **bold** and *it* and `code` and ~~gone~~\n")
        #expect(tv.string == "a bold and it and code and gone")
    }

    @Test func codeBlockOverSeveralParagraphsIsOneBlock() {
        let (c, tv, _) = page("one\n\ntwo\nthree\n")
        tv.setSelectedRange(NSRange(location: 0, length: (tv.string as NSString).length))
        tv.applyBlock(.code)
        #expect(c.markdown() == "```\none\ntwo three\n```\n")
    }

    @Test func formattingIsOneUndoStep() {
        let (c, tv, _) = page("A plain line.\n")
        tv.setSelectedRange((tv.string as NSString).range(of: "plain"))
        tv.applyMark(.bold)
        #expect(c.markdown() == "A **plain** line.\n")
        tv.undoManager?.undo()
        #expect(c.markdown() == "A plain line.\n")
        tv.undoManager?.redo()
        #expect(c.markdown() == "A **plain** line.\n")
    }

    /// Each key is its own event in the app: the run loop turns between them, so undo groups as it does there.
    private func keys(_ tv: LoreTextView, _ s: String) {
        for ch in s {
            type(tv, String(ch))
            RunLoop.current.run(until: Date())
        }
    }

    @Test func aShortcutIsUndoneBackToItsText() {
        let (c, tv, _) = page("")
        keys(tv, "# Big")
        #expect(c.markdown() == "# Big\n")
        tv.undoManager?.undo()
        #expect(c.markdown() == "# \n" || c.markdown().isEmpty)
        // The shortcut itself undoes back to text: no heading is left.
        tv.undoManager?.undo()
        #expect(tv.string.hasPrefix("#"))
        #expect(!c.markdown().hasPrefix("# "))
    }

    @Test func undoTakesBackAWordAtATime() {
        let (_, tv, _) = page("")
        keys(tv, "one two three")
        tv.undoManager?.undo()
        #expect(tv.string == "one two")
        tv.undoManager?.undo()
        #expect(tv.string == "one")
    }

    @Test func arabicAndEmojiRoundTripAndTakeMarks() {
        let md = "مرحبا **بالعالم** 👋🏽 نص\n\n- بند أول\n- [ ] مهمة 🌱\n"
        let (c, tv, _) = page(md)
        #expect(c.markdown() == md)
        type(tv, "\nسطر جديد **غامق**")
        #expect(c.markdown().hasSuffix("- [ ] مهمة 🌱\n\nسطر جديد **غامق**\n"))
    }

    @Test func pastedMarkdownKeepsItsStructure() {
        let (c, tv, _) = page("Start\n\nEnd\n")
        let pb = NSPasteboard(name: .init("lore-audit-\(UUID().uuidString)"))
        pb.clearContents()
        pb.setString("## Pasted\n\n- a\n- b\n", forType: .string)
        tv.setSelectedRange(NSRange(location: 6, length: 0))
        tv.insertNewline(nil)
        tv.setSelectedRange(NSRange(location: 6, length: 0))
        _ = tv.readPasteboard(pb)
        pb.releaseGlobally()
        #expect(c.markdown() == "Start\n\n## Pasted\n\n- a\n- b\n\nEnd\n")
    }

    /// A key on a 6,000-line note: measured from the key to the laid-out viewport, in the middle of the note.
    @Test func typingOnALongNoteStaysFast() {
        var md = ""
        for i in 0..<1_000 {
            md +=
                "## Section \(i)\n\nA line of text about the garden, number \(i), with **bold** words.\n\n- item\n- [ ] task\n"
        }
        let (c, tv, _) = page(md)
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length / 2, length: 0))
        tv.scrollRangeToVisible(tv.selectedRange())
        var times: [Double] = []
        for ch in "the quick brown fox jumps over the lazy dog " {
            let t0 = CACurrentMediaTime()
            tv.insertText(String(ch), replacementRange: tv.selectedRange())
            tv.textLayoutManager?.textViewportLayoutController.layoutViewport()
            times.append((CACurrentMediaTime() - t0) * 1000)
        }
        times.sort()
        let p50 = times[times.count / 2]
        let p95 = times[times.count * 95 / 100]
        print(String(format: "LATENCY long note p50 %.2f ms p95 %.2f ms", p50, p95))
        #expect(c.markdown().contains("the quick brown fox"))
        #expect(p95 < 16)
    }

    @Test func theSlashMenuListsTemplatesAndTemplateOpensThem() {
        #expect(LoreMenuEntry.filter("jour", templatesOnly: false).contains(.template(LoreTemplates.all[0])))
        #expect(LoreMenuEntry.filter("", templatesOnly: false).contains(.item(.template)))
        #expect(LoreMenuEntry.filter("", templatesOnly: true).count == LoreTemplates.all.count)
        #expect(
            LoreMenuEntry.filter("re", templatesOnly: true).map(\.title)
                == ["Weekly review", "Bug report", "Reading notes"])
    }
}
