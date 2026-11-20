// LoreTableEdit — the row and column tools of a table (E0-7). A table stays Markdown text in the page; the tools
// rewrite its lines (header, separator, rows) and the editor swaps them in as one undoable edit.
import AppKit
import CoreUI

public enum LoreTableCommand: Sendable { case addRow, addColumn, deleteRow }

enum LoreTableEdit {
    /// `lines` is header, separator, then rows; `line` is the one the caret is on. nil = nothing to do.
    static func apply(_ c: LoreTableCommand, lines: [String], line: Int) -> [String]? {
        guard lines.count >= 2, GFMTable.isSeparator(lines[1]) else { return nil }
        let width = GFMTable.cells(lines[0]).count
        switch c {
        case .addRow:
            var out = lines
            // After the caret's row; the header and the separator add the first row.
            out.insert(row(Array(repeating: "", count: width)), at: min(max(line, 1) + 1, out.count))
            return out
        case .addColumn:
            return lines.enumerated().map { i, l in
                var cells = GFMTable.cells(l)
                cells.append(i == 1 ? "---" : i == 0 ? "New" : "")
                return row(cells)
            }
        case .deleteRow:
            // Only a body row goes; the header and the separator stay.
            guard line >= 2, line < lines.count else { return nil }
            var out = lines
            out.remove(at: line)
            return out
        }
    }

    static func row(_ cells: [String]) -> String { "| " + cells.joined(separator: " | ") + " |" }

    /// The sentence-free count of columns and rows, for tests and the toolbar label.
    static func hasTable(_ markdown: String) -> Bool {
        let lines = markdown.components(separatedBy: "\n")
        return lines.indices.contains { GFMTable.extent(lines, at: $0) != nil }
    }
}

extension LoreEditorController {
    /// The table the caret is in, without its trailing newline; nil outside a table.
    func tableRange() -> NSRange? {
        let ts = textView.ts
        let loc = textView.selectedRange().location
        guard loc < ts.length else { return nil }
        var r = NSRange(location: 0, length: 0)
        guard
            ts.attribute(.loreTable, at: loc, longestEffectiveRange: &r, in: NSRange(location: 0, length: ts.length))
                != nil
        else { return nil }
        return textView.content(r)
    }

    public var caretInTable: Bool { tableRange() != nil }

    /// Whether the open page holds a table (the toolbar shows only then).
    public func hasTable() -> Bool { LoreTableEdit.hasTable(markdown()) }

    /// Runs a tool on the table the caret is in, as one edit (⌘Z undoes it). false = no table, or nothing to do.
    @discardableResult public func tableEdit(_ command: LoreTableCommand) -> Bool {
        guard let r = tableRange() else { return false }
        let old = textView.ts.attributedSubstring(from: r).string
        let offset = max(0, min(textView.selectedRange().location - r.location, r.length))
        let line = (old as NSString).substring(to: offset).components(separatedBy: "\u{2028}").count - 1
        guard let new = LoreTableEdit.apply(command, lines: old.components(separatedBy: "\u{2028}"), line: line)
        else { return false }
        let text = new.joined(separator: "\u{2028}")
        guard textView.shouldChangeText(in: r, replacementString: text) else { return false }
        textView.textStorage?.replaceCharacters(in: r, with: text)
        textView.didChangeText()
        return true
    }

    /// Grid draws a table as a grid while the caret is elsewhere; Text always shows its Markdown.
    public var tablesAsText: Bool {
        get { textView.tablesAsText }
        set {
            textView.tablesAsText = newValue
            if let tlm = textView.textLayoutManager { tlm.invalidateLayout(for: tlm.documentRange) }
            textView.needsDisplay = true
        }
    }

    /// Moves the caret to the `index`-th heading of level 1 to 3 (an outline entry, counted the way `LoreOutline`
    /// counts: Markdown order, code blocks skipped) and scrolls to it. By position, so repeated titles are fine.
    public func reveal(headingIndex index: Int) {
        guard let at = LoreHeadingScan.location(ofHeading: index, in: textView.ts) else { return }
        let line = (textView.string as NSString).paragraphRange(for: NSRange(location: at, length: 0))
        textView.setSelectedRange(NSRange(location: line.location, length: 0))
        textView.scrollRangeToVisible(line)
    }
}

enum LoreHeadingScan {
    /// The start of the `index`-th paragraph that is a heading of level 1 to 3.
    static func location(ofHeading index: Int, in ts: NSAttributedString) -> Int? {
        let ns = ts.string as NSString
        var loc = 0
        var seen = 0
        while loc < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            if case .h(let level) = Block.at(ts, para.location), level <= 3 {
                if seen == index { return para.location }
                seen += 1
            }
            loc = NSMaxRange(para)
        }
        return nil
    }
}
