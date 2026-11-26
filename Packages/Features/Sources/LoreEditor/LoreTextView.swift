import AppKit
import CoreUI
import QuartzCore

/// The page: NSTextView on TextKit 2. Markdown shortcuts turn into structure as you type; the symbols are never shown.
/// Productised from prototype A (`Designs/core/lore/editor-prototypes/Sources/LoreA`).
final class LoreTextView: NSTextView {
    weak var controller: LoreEditorController?
    var picker: LorePicker?
    /// The selection bar, the insert menu and the + (`LoreTools`).
    lazy var tools = LoreTools(self)
    var busy = false
    var latency = LoreLatency()
    private let fragments = LoreFragmentProvider()

    var ts: NSTextStorage { textStorage! }
    var ns: NSString { string as NSString }
    var cursor: Int { selectedRange().location }
    var paraRange: NSRange { ns.paragraphRange(for: NSRange(location: min(cursor, ns.length), length: 0)) }
    /// About 70 characters of body text.
    var measure: CGFloat { (Typeface.body * 45).rounded() }

    func setUp() {
        isRichText = true
        importsGraphics = false
        allowsImageEditing = false
        usesFontPanel = false
        usesRuler = false
        allowsUndo = true
        // Unboxed: the page island the host puts it on shows through.
        drawsBackground = false
        insertionPointColor = LoreInk.text
        selectedTextAttributes = [.backgroundColor: LoreInk.selection]
        linkTextAttributes = [
            .foregroundColor: LoreInk.text, .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: LoreInk.text2, .cursor: NSCursor.pointingHand,
        ]
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        // Note text never goes to Writing Tools (Apple Intelligence).
        if #available(macOS 15.0, *) { writingToolsBehavior = .none }
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textLayoutManager?.delegate = fragments
        typingAttributes = Style.typing(.p)
        setAccessibilityLabel("Note")
        LoreInk.resolve(for: effectiveAppearance)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInset()
    }

    /// Keystroke → layout done: the key is handled and the viewport laid out synchronously, then timed.
    override func keyDown(with event: NSEvent) {
        let t0 = CACurrentMediaTime()
        super.keyDown(with: event)
        textLayoutManager?.textViewportLayoutController.layoutViewport()
        latency.record(CACurrentMediaTime() - t0)
    }

    /// A table is a grid while the caret is elsewhere and text while it is inside: repaint when the selection moves.
    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        let loc = selectedRange().location
        let inTable = loc < ts.length && ts.attribute(.loreTable, at: loc, effectiveRange: nil) != nil
        if inTable || caretWasInTable { needsDisplay = true }
        if inTable != caretWasInTable { controller?.onTable?(inTable) }
        caretWasInTable = inTable
        tools.selectionChanged(stillSelecting: stillSelecting)
    }
    private var caretWasInTable = false
    /// Text mode: tables always show their Markdown (E0-7), not a grid.
    var tablesAsText = false
    var placeholder: String?  // drawn on the empty page (`LoreEditorController.placeholder`)
    var placeholderDrawn = false  // what the last draw showed; a text change that flips it redraws

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        LoreInk.resolve(for: effectiveAppearance)
        if let tlm = textLayoutManager { tlm.invalidateLayout(for: tlm.documentRange) }
        needsDisplay = true
    }

    func content(_ pr: NSRange) -> NSRange {
        var r = pr
        while r.length > 0, [10, 13, 0x2029].contains(ns.character(at: NSMaxRange(r) - 1)) { r.length -= 1 }
        return r
    }

    /// The block at the caret; an empty last paragraph has no characters, so it lives in the typing attributes.
    func currentBlock() -> Block {
        let pr = paraRange
        return pr.length == 0 ? Block.from(typingAttributes) : Block.at(ts, pr.location)
    }

    // MARK: edit primitives (all undoable, one undo step each)

    func edit(_ body: () -> Void) {
        breakUndoCoalescing()
        undoManager?.beginUndoGrouping()
        body()
        undoManager?.endUndoGrouping()
    }

    func replace(_ r: NSRange, with a: NSAttributedString) {
        busy = true
        defer { busy = false }
        if shouldChangeText(in: r, replacementString: a.string) {
            ts.replaceCharacters(in: r, with: a)
            didChangeText()
        }
    }

    func replace(_ r: NSRange, with s: String) {
        replace(r, with: NSAttributedString(string: s, attributes: typingAttributes))
    }

    func restyle(_ r: NSRange) { Style.renderParagraphs(ts, in: r) }

    /// Sets the block of one paragraph. An empty last paragraph gets a real newline so its marker can draw.
    func setBlock(_ b: Block, paragraph: NSRange? = nil, updateTyping: Bool = true) {
        var pr = paragraph ?? paraRange
        if pr.length == 0 {
            if b == .p {
                typingAttributes = Style.typing(.p)
                return
            }
            replace(pr, with: NSAttributedString(string: "\n", attributes: Style.typing(b)))
            setSelectedRange(NSRange(location: pr.location, length: 0))
            pr = NSRange(location: pr.location, length: 1)
        }
        if shouldChangeText(in: pr, replacementString: nil) {
            ts.beginEditing()
            ts.addAttributes(Style.blockAttrs(b), range: pr)
            Style.render(ts, pr)
            ts.endEditing()
            didChangeText()
        }
        if updateTyping { typingAttributes = Style.typing(b) }
    }

    /// The range a change from outside the editor's own code (typing, Find & Replace, the system) writes.
    private var outsideEdit: NSRange?

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let ok = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        let undoing = undoManager?.isUndoing == true || undoManager?.isRedoing == true
        if ok, !busy, !undoing, let s = replacementString {
            outsideEdit = NSRange(location: affectedCharRange.location, length: (s as NSString).length)
        }
        return ok
    }

    override func didChangeText() {
        // Replaced text keeps the attributes of what it replaced; new text is never raw source, so it is escaped when
        // written (Find & Replace put a live link into a raw paragraph). Undo and redo restore the original as it was.
        if let r = outsideEdit {
            outsideEdit = nil
            if r.length > 0, NSMaxRange(r) <= ts.length { ts.removeAttribute(.loreRaw, range: r) }
        }
        super.didChangeText()
        controller?.spy.starts = nil
        Style.renumber(ts, around: min(cursor, max(0, ts.length - 1)))
        controller?.onChange?()
    }

    // MARK: typing triggers

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // Typed text is the person's own: never raw source, so its `*` or `_` is escaped when written.
        typingAttributes[.loreRaw] = nil
        // Undo takes back a word at a time, not the whole run of typing.
        if (string as? String) == " ", !busy { breakUndoCoalescing() }
        super.insertText(string, replacementRange: replacementRange)
        guard !busy, selectedRange().length == 0,
            let s = (string as? String) ?? (string as? NSAttributedString)?.string
        else { return }
        if tools.menu != nil { return tools.updateMenu() }
        if picker != nil { return updatePicker() }
        guard s.count == 1 else { return }
        switch s {
        case " ": blockTrigger()
        case "`": if !fenceTrigger() { inlineTrigger() }
        case "*", "_", "~": inlineTrigger()
        case "[": linkTrigger()
        case "/": tools.slashTyped()
        case "-": ruleTrigger()
        default: break
        }
    }

    private func blockTrigger() {
        let pr = paraRange
        let cur = currentBlock()
        let prefix = ns.substring(with: NSRange(location: pr.location, length: cursor - pr.location))
        var target: Block?
        switch (cur, prefix) {
        case (.p, "# "): target = .h(1)
        case (.p, "## "): target = .h(2)
        case (.p, "### "): target = .h(3)
        case (.p, "- "), (.p, "* "), (.p, "+ "): target = .ul(0)
        case (.p, "> "): target = .quote
        case (.p, "[] "), (.p, "[ ] "), (.p, "- [ ] "), (.p, "- [] "): target = .task(0, false)
        case (.p, "[x] "), (.p, "- [x] "): target = .task(0, true)
        case (.ul(let l), "[] "), (.ul(let l), "[ ] "): target = .task(l, false)
        case (.p, _) where prefix.range(of: #"^\d{1,3}[.)] $"#, options: .regularExpression) != nil: target = .ol(0)
        default: break
        }
        guard let target else { return }
        // A list started right under a list that was just ended (Return on an empty item) is a second list: an empty
        // paragraph keeps them apart, on the page and in the Markdown.
        // (A numbered list under bullets, or bullets under numbers, is a new list in Markdown already.)
        let above = pr.location > 0 ? Block.at(ts, pr.location - 1) : .p
        let restart = target.isList && above.isList && (target.key == "ol") == (above.key == "ol")
        edit {
            replace(NSRange(location: pr.location, length: (prefix as NSString).length), with: "")
            var at = pr.location
            if restart {
                replace(
                    NSRange(location: at, length: 0),
                    with: NSAttributedString(string: "\n", attributes: Style.typing(.p)))
                at += 1
            }
            setSelectedRange(NSRange(location: at, length: 0))
            setBlock(target)
        }
    }

    private func fenceTrigger() -> Bool {
        let c = content(paraRange)
        guard currentBlock() == .p, ns.substring(with: c) == "```" else { return false }
        edit {
            replace(c, with: "")
            setSelectedRange(NSRange(location: c.location, length: 0))
            setBlock(.code)
        }
        return true
    }

    private static func re(_ p: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: p)
    }
    private static let inlineRules: [(NSRegularExpression, NSAttributedString.Key)] = [
        (re(#"~~(?=\S)([^~\n]{1,256}?)(?<=\S)~~$"#), .loreStrike),
        (re(#"(?<!`)`([^`\n]{1,256})`$"#), .loreCode),
        (re(#"\*\*(?=\S)([^*\n]{1,256}?)(?<=\S)\*\*$"#), .loreBold),
        (re(#"(?<![*\w])\*(?=[^\s*])([^*\n]{1,256}?)(?<=\S)\*$"#), .loreItalic),
        (re(#"(?<![_\w])_(?=[^\s_])([^_\n]{1,256}?)(?<=\S)_$"#), .loreItalic),
    ]

    private func inlineTrigger() {
        let pr = paraRange
        let b = currentBlock()
        guard b != .code else { return }
        // Only the last few hundred characters before the caret: the rules match at most 260 of them.
        let from = max(pr.location, cursor - 300)
        let r = NSRange(location: from, length: cursor - from)
        let text = ns.substring(with: r)
        for (rx, key) in Self.inlineRules {
            guard let m = rx.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else {
                continue
            }
            let full = NSRange(location: pr.location + m.range.location, length: m.range.length)
            let innerR = NSRange(location: pr.location + m.range(at: 1).location, length: m.range(at: 1).length)
            let inner = NSMutableAttributedString(attributedString: ts.attributedSubstring(from: innerR))
            inner.addAttribute(key, value: true, range: NSRange(location: 0, length: inner.length))
            edit {
                replace(full, with: inner)
                restyle(NSRange(location: full.location, length: inner.length))
            }
            setSelectedRange(NSRange(location: full.location + inner.length, length: 0))
            typingAttributes = Style.typing(b)
            return
        }
    }

    // MARK: [[ note links

    func linkTrigger() {
        guard cursor >= 2, ns.substring(with: NSRange(location: cursor - 2, length: 2)) == "[[",
            currentBlock() != .code, let controller
        else { return }
        picker = LorePicker(anchor: cursor - 2, textView: self, source: controller.titles) { [weak self] title in
            self?.choose(title)
        }
    }

    func updatePicker() {
        guard let p = picker else { return }
        let start = p.anchor + 2
        guard cursor >= start, cursor <= ns.length, p.anchor + 2 <= ns.length,
            ns.substring(with: NSRange(location: p.anchor, length: 2)) == "[["
        else { return closePicker() }
        let q = ns.substring(with: NSRange(location: start, length: cursor - start))
        if q.contains("]") || q.contains("\n") || q.count > 80 { return closePicker() }
        p.update(query: q)
    }

    func closePicker() {
        picker?.close()
        picker = nil
    }

    func choose(_ title: String) {
        guard let p = picker else { return }
        closePicker()
        let plain = Style.typing(currentBlock())
        let a = NSMutableAttributedString(string: title, attributes: plain.merging([.loreChip: title]) { $1 })
        a.append(NSAttributedString(string: " ", attributes: plain))
        let r = NSRange(location: p.anchor, length: cursor - p.anchor)
        edit {
            replace(r, with: a)
            restyle(NSRange(location: r.location, length: a.length))
        }
        setSelectedRange(NSRange(location: r.location + a.length, length: 0))
        typingAttributes = plain
    }

    override func moveUp(_ sender: Any?) {
        if tools.menu != nil { tools.move(-1) } else if let p = picker { p.move(-1) } else { super.moveUp(sender) }
    }
    override func moveDown(_ sender: Any?) {
        if tools.menu != nil { tools.move(1) } else if let p = picker { p.move(1) } else { super.moveDown(sender) }
    }
    override func cancelOperation(_ sender: Any?) {
        if tools.menu != nil {
            tools.closeMenu(cancel: true)
        } else if picker != nil {
            closePicker()
        } else if tools.bar != nil {
            tools.hideBar()
        } else {
            super.cancelOperation(sender)
        }
    }
    override func complete(_ sender: Any?) { if picker != nil { closePicker() } else { super.complete(sender) } }
    override func resignFirstResponder() -> Bool {
        closePicker()
        tools.closeAll()
        return super.resignFirstResponder()
    }

    // MARK: Return, Tab, Delete

    override func insertNewline(_ sender: Any?) {
        if tools.menu != nil { return tools.chooseCurrent() }
        if let p = picker {
            if let t = p.current { choose(t) } else { closePicker() }
            return
        }
        guard selectedRange().length == 0 else { return super.insertNewline(sender) }
        let pr = paraRange
        let b = currentBlock()
        let c = content(pr)
        let text = ns.substring(with: c)
        let atEnd = cursor == NSMaxRange(c)
        switch b {
        case .code:
            if atEnd && (text.isEmpty || text.hasSuffix("\u{2028}")) {
                edit {
                    if text.hasSuffix("\u{2028}") { replace(NSRange(location: cursor - 1, length: 1), with: "") }
                    if text.isEmpty {
                        setBlock(.p)
                    } else {
                        super.insertNewline(sender)
                        setBlock(.p)
                    }
                }
            } else {
                insertLineBreak(sender)
            }
        case .ul, .ol, .task, .quote:
            if text.isEmpty { return edit { setBlock(.p) } }
            edit {
                super.insertNewline(sender)
                if case .task(let l, _) = b { setBlock(.task(l, false)) } else if paraRange.length == 0 { setBlock(b) }
            }
        case .h:
            edit {
                super.insertNewline(sender)
                if atEnd { setBlock(.p) }
            }
        case .p:
            // Each paragraph is its own undo step.
            breakUndoCoalescing()
            super.insertNewline(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
        if tools.menu != nil { return tools.chooseCurrent() }
        if let p = picker {
            if let t = p.current { choose(t) }
            return
        }
        let b = currentBlock()
        if b.isList {
            shiftLevel(1)
        } else if b == .code {
            insertText("    ", replacementRange: selectedRange())
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if currentBlock().isList { shiftLevel(-1) } else { super.insertBacktab(sender) }
    }

    private func shiftLevel(_ d: Int) {
        let sel = selectedRange()
        let full = ns.paragraphRange(for: sel)
        edit {
            if full.length == 0 {
                return setBlock(currentBlock().with(level: max(0, min(5, currentBlock().level + d))))
            }
            ns.enumerateSubstrings(in: full, options: [.byParagraphs, .substringNotRequired]) { _, _, encl, _ in
                let b = Block.at(self.ts, encl.location)
                if b.isList {
                    self.setBlock(b.with(level: max(0, min(5, b.level + d))), paragraph: encl, updateTyping: false)
                }
            }
        }
        setSelectedRange(sel)
        typingAttributes = Style.typing(currentBlock())
    }

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        if sel.length == 0 {
            let pr = paraRange
            let b = currentBlock()
            if sel.location == pr.location && b != .p {
                return edit { setBlock(b.isList && b.level > 0 ? b.with(level: b.level - 1) : .p) }
            }
            // A note link or an image goes whole.
            var chip = NSRange()
            for key in [NSAttributedString.Key.loreChip, .loreImage]
            where sel.location > 0 && ts.attribute(key, at: sel.location - 1, effectiveRange: &chip) != nil {
                return edit { replace(chip, with: "") }
            }
        }
        super.deleteBackward(sender)
        if tools.menu != nil { tools.updateMenu() }
        if picker != nil { updatePicker() }
    }

    // MARK: find (⌘F, ⌘G, ⇧⌘G): the native find bar. ⌘E is Code (`LoreTools`), not Use Selection for Find.

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, tools.keyEquivalent(event) { return true }
        guard window?.firstResponder === self,
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift) == .command,
            let key = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }
        let shift = event.modifierFlags.contains(.shift)
        let action: NSTextFinder.Action? =
            switch key {
            case "f" where !shift: .showFindInterface
            case "g": shift ? .previousMatch : .nextMatch
            default: nil
            }
        guard let action else { return super.performKeyEquivalent(with: event) }
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
        // No focus rings anywhere (CoreUI rule): the find bar's search field included.
        if let bar = enclosingScrollView?.findBarView { Self.noFocusRings(bar) }
        return true
    }

    private static func noFocusRings(_ view: NSView) {
        view.focusRingType = .none
        view.subviews.forEach(noFocusRings)
    }
}
