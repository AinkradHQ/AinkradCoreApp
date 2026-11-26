#if DEBUG
// Debug only: drives the editor tools the way a person would, for the Lore walk's screenshots.
import AppKit

extension LoreEditorController {
    /// Selects the first `text` on the page, as a mouse selection does: the selection bar comes up over it.
    public func demoSelect(_ text: String) {
        focus()
        textView.setSelectedRange((textView.string as NSString).range(of: text))
    }

    /// The selection bar's block button.
    public func demoBlockMenu() {
        textView.tools.showBar()
        textView.tools.run(.blocks)
    }

    /// On a new line at the end: `/` and `query` typed.
    public func demoSlash(_ query: String) {
        newLineAtEnd()
        for ch in "/" + query { textView.insertText(String(ch), replacementRange: textView.selectedRange()) }
    }

    /// An insert menu item, on a new line at the end.
    public func demoInsert(_ item: LoreInsertItem) {
        newLineAtEnd()
        textView.tools.apply(item)
    }

    /// An image ref on a new line at the end (what the Image item adds from a web address).
    public func demoImage(_ name: String, _ url: String) {
        newLineAtEnd()
        textView.insertMarkdown("![\(name)](\(url))", at: textView.selectedRange())
    }

    /// Ticks the task that holds `text` (with its animation).
    public func demoTick(_ text: String) {
        let at = (textView.string as NSString).range(of: text).location
        guard at != NSNotFound else { return }
        textView.toggleTask((textView.string as NSString).paragraphRange(for: NSRange(location: at, length: 0)))
    }

    private func newLineAtEnd() {
        focus()
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        if textView.content(textView.paraRange).length > 0 { textView.insertNewline(nil) }
    }
}
#endif
