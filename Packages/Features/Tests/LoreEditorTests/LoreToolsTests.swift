import AppKit
import Testing

@testable import LoreEditor

/// The editor tools' edits (selection bar, insert menu, Markdown shortcuts): what the Markdown says afterwards.
@MainActor struct LoreToolsTests {
    private func select(_ c: LoreEditorController, _ word: String) {
        c.textView.setSelectedRange((c.textView.string as NSString).range(of: word))
    }

    private func caretAtEnd(_ c: LoreEditorController) {
        c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
    }

    @Test func boldTogglesOnAndOff() {
        let c = editor("A plain line.\n")
        select(c, "plain")
        c.textView.applyMark(.bold)
        #expect(c.markdown() == "A **plain** line.\n")
        #expect(c.textView.activeMarks == [.bold])
        c.textView.applyMark(.bold)
        #expect(c.markdown() == "A plain line.\n")
    }

    @Test func italicStrikeAndCodeWriteTheirMarkdown() {
        let c = editor("One two three.\n")
        select(c, "One")
        c.textView.applyMark(.italic)
        select(c, "two")
        c.textView.applyMark(.strike)
        select(c, "three")
        c.textView.applyMark(.code)
        #expect(c.markdown() == "*One* ~~two~~ `three`.\n")
    }

    @Test func boldOverAPartlyBoldSelectionMakesAllOfItBold() {
        let c = editor("Some **bold** words\n")
        select(c, "Some bold")
        c.textView.applyMark(.bold)
        #expect(c.markdown() == "**Some bold** words\n")
    }

    @Test func strikeReadsBackAndTildesStayText() {
        let c = editor("Done ~~old~~ new.\n")
        #expect(c.textView.string == "Done old new.\n")
        #expect(c.textView.ts.attribute(.loreStrike, at: 5, effectiveRange: nil) != nil)
        #expect(MarkdownWriter.escape("~/notes") == "~/notes")
        #expect(MarkdownWriter.escape("a~~b") == "a\\~\\~b")
        #expect(editor("a \\~\\~b\n").textView.string == "a ~~b\n")
    }

    @Test func linkGoesOnAndOff() {
        let c = editor("A plain line.\n")
        select(c, "plain")
        c.textView.applyLink(URL(string: "https://example.com"))
        #expect(c.markdown() == "A [plain](https://example.com) line.\n")
        c.textView.applyLink(nil)
        #expect(c.markdown() == "A plain line.\n")
    }

    @Test func addressesAreWebOrMailOnly() {
        #expect(LoreFormat.address("example.com")?.absoluteString == "https://example.com")
        #expect(LoreFormat.address("ada@example.com")?.scheme == "mailto")
        #expect(LoreFormat.address("javascript:alert(1)") == nil)
        #expect(LoreFormat.address("file:///etc/passwd") == nil)
        #expect(LoreFormat.address("two words") == nil)
    }

    @Test func blockTypeChangesTheLinePrefix() {
        let c = editor("Title\n\nBody\n")
        c.textView.setSelectedRange(NSRange(location: 1, length: 0))
        c.textView.applyBlock(.h(2))
        #expect(c.markdown() == "## Title\n\nBody\n")
        select(c, "Body")
        c.textView.applyBlock(.task(0, false))
        #expect(c.markdown() == "## Title\n\n- [ ] Body\n")
        c.textView.applyBlock(.quote)
        #expect(c.markdown() == "## Title\n\n> Body\n")
        c.textView.applyBlock(.p)
        #expect(c.markdown() == "## Title\n\nBody\n")
    }

    @Test func aListKeepsItsLevelWhenItChangesKind() {
        let c = editor("- top\n  - nested\n")
        select(c, "nested")
        c.textView.applyBlock(.ol(0))
        #expect(c.markdown() == "- top\n  1. nested\n")
    }

    @Test func insertTableAfterAParagraph() {
        let c = editor("Intro\n")
        c.textView.setSelectedRange(NSRange(location: 2, length: 0))
        c.textView.insertBlocks(LoreFormat.table)
        let md = c.markdown()
        #expect(md == "Intro\n\n" + LoreFormat.table)
        #expect(LoreTableEdit.hasTable(md))
        // The caret waits on the line after the table, which draws as a grid.
        let loc = (c.textView.string as NSString).range(of: "Column 1").location
        #expect(c.textView.ts.attribute(.loreTable, at: loc, effectiveRange: nil) != nil)
        #expect(c.textView.cursor == (c.textView.string as NSString).length)
    }

    @Test func insertChecklistOnAnEmptyLine() {
        let c = editor("Intro\n")
        caretAtEnd(c)
        c.textView.tools.apply(.checklist)
        c.textView.insertText("Buy seeds", replacementRange: c.textView.selectedRange())
        #expect(c.markdown() == "Intro\n\n- [ ] Buy seeds\n")
    }

    @Test func slashFilters() {
        #expect(LoreInsertItem.filter("") == LoreInsertItem.inserts)
        #expect(LoreInsertItem.filter("ta") == [.table, .checklist])  // Checklist answers to "task"
        #expect(Array(LoreInsertItem.filter("h").prefix(3)) == [.h1, .h2, .h3])
        #expect(LoreInsertItem.filter("h2") == [.h2])
        #expect(Set(LoreInsertItem.filter("list")) == [.bullet, .numbered, .checklist])
        #expect(LoreInsertItem.filter("rule") == [.divider])
        #expect(LoreInsertItem.filter("zzz").isEmpty)
        #expect(!LoreInsertItem.inserts.contains(.text))
    }

    @Test func slashMenuInsertsATableAndTakesTheCommandAway() {
        let c = editor("Intro\n")
        caretAtEnd(c)
        let tv = c.textView
        tv.insertText("/", replacementRange: tv.selectedRange())
        #expect(tv.tools.menu != nil)
        tv.insertText("ta", replacementRange: tv.selectedRange())
        #expect(tv.tools.menu?.current == .item(.table))
        tv.insertNewline(nil)
        #expect(tv.tools.menu == nil)
        #expect(c.markdown() == "Intro\n\n" + LoreFormat.table)
    }

    @Test func slashMidLineIsText() {
        let c = editor("and/or\n")
        c.textView.setSelectedRange(NSRange(location: 3, length: 0))
        c.textView.insertText("/", replacementRange: c.textView.selectedRange())
        #expect(c.textView.tools.menu == nil)
    }

    @Test func escapeTakesAwayTheSlashTheShortcutPutIn() {
        let c = editor("Intro\n")
        caretAtEnd(c)
        c.textView.tools.openInsert(typed: false, animated: false)
        #expect(c.textView.string == "Intro\n/")
        c.textView.cancelOperation(nil)
        #expect(c.textView.tools.menu == nil)
        #expect(c.markdown() == "Intro\n")
    }

    @Test func threeDashesMakeADivider() {
        let c = editor("Intro\n")
        caretAtEnd(c)
        for ch in "---" { c.textView.insertText(String(ch), replacementRange: c.textView.selectedRange()) }
        #expect(c.textView.ts.attribute(.loreRule, at: 6, effectiveRange: nil) != nil)
        c.textView.insertText("After", replacementRange: c.textView.selectedRange())
        #expect(c.markdown() == "Intro\n\n---\n\nAfter\n")
    }

    @Test func aRuleReadsAsItsOwnBlockAndRoundTrips() {
        for md in ["Above\n\n---\n\nBelow\n", "***\n", "Setext-ish\n---\n\ntext\n"] {
            let c = editor(md)
            #expect(c.markdown() == md)
        }
        let c = editor("Above\n\n---\n")
        let at = (c.textView.string as NSString).range(of: "---").location
        #expect(c.textView.ts.attribute(.loreRule, at: at, effectiveRange: nil) != nil)
    }

    @Test func imageRefIsWrittenAsAnImage() {
        let c = editor("x\n")
        c.textView.insertMarkdown("![Plot map](https://example.com/map.png)", at: NSRange(location: 1, length: 0))
        #expect(c.textView.string == "xPlot map\n")
        #expect(c.markdown() == "x![Plot map](https://example.com/map.png)\n")
    }

    @Test func dateStampIsPlainText() {
        let c = editor("")
        c.textView.tools.apply(.date)
        #expect(c.markdown().hasPrefix(LoreFormat.stamp().prefix(4)))
    }
}
