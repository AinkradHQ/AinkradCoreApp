// LoreTools — the editor's assistant tools around the text view: the selection bar, the insert and block menus, the
// quiet + beside an empty line, and their keys. The text view calls in from its overrides; everything shown here is a
// child panel or a small subview, so the page itself never changes shape.
import AppKit
import CoreUI
import SwiftUI

@MainActor final class LoreTools {
    private unowned let tv: LoreTextView
    private(set) var bar: LoreFloat<LoreSelectionBarView>?
    private(set) var menu: LoreInsertMenu?
    private var gutter: NSHostingView<LoreGutterButton>?
    /// A prompt (link, image) is open over the window: the bar stays away.
    private var prompting = false

    init(_ tv: LoreTextView) { self.tv = tv }

    private var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: keys

    /// ⌘B ⌘I ⌘E ⇧⌘X ⇧⌘K ⌥⌘/ while the page has focus. ⌘K stays the Launcher's, ⌘/ the shortcut list's.
    func keyEquivalent(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let key = e.charactersIgnoringModifiers?.lowercased() else { return false }
        switch (mods, key) {
        case ([.command], "b"): tv.applyMark(.bold)
        case ([.command], "i"): tv.applyMark(.italic)
        case ([.command], "e"): tv.applyMark(.code)
        case ([.command, .shift], "x"): tv.applyMark(.strike)
        case ([.command, .shift], "k"): linkPrompt()
        case ([.command, .option], "/"): openInsert(typed: false, animated: false)
        default: return false
        }
        if bar != nil { showBar() }
        return true
    }

    // MARK: selection bar

    func selectionChanged(stillSelecting: Bool) {
        updateGutter()
        guard !stillSelecting else { return hideBar() }
        if menu?.mode == .blocks, tv.selectedRange().location != menu?.anchor { closeMenu(cancel: true) }
        let sel = tv.selectedRange()
        let calm = sel.length > 0 && tv.picker == nil && (menu == nil || menu?.mode == .blocks) && !prompting
        if calm, tv.window?.firstResponder === tv { showBar() } else { hideBar() }
    }

    func showBar() {
        let sel = tv.selectedRange()
        guard sel.length > 0, let window = tv.window else { return hideBar() }
        // The first line of the selection: the bar sits over it, or under it near the window's top.
        let line = tv.firstRect(
            forCharacterRange: NSRange(location: sel.location, length: sel.length), actualRange: nil)
        let room = LoreSelectionBar.shadowRoom
        var view = LoreSelectionBarView(
            marks: tv.activeMarks, link: tv.selectionHasLink, block: .of(tv.currentBlock())
        ) { [weak self] in self?.run($0) }
        let fresh = bar == nil
        if fresh { bar = LoreFloat(view, parent: window) }
        let size = bar?.fitting ?? .zero
        let top = window.frame.maxY - Space.s8 * 2
        view.above = line.maxY + size.height - room < top
        bar?.root = view
        let w = window.frame
        let x = min(max(line.midX - size.width / 2, w.minX + Space.s2 - room), w.maxX - size.width - Space.s2 + room)
        let y = view.above ? line.maxY + Space.s1 - room : line.minY - size.height + room - Space.s1
        bar?.place(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height))
    }

    func hideBar() {
        bar?.close()
        bar = nil
    }

    func run(_ a: LoreBarAction) {
        switch a {
        case .mark(let m):
            tv.applyMark(m)
            showBar()
        case .link: linkPrompt()
        case .blocks:
            guard let frame = bar?.frame else { return }
            let sel = tv.selectedRange()
            let line = tv.firstRect(
                forCharacterRange: NSRange(location: sel.location, length: sel.length), actualRange: nil)
            // Under the selection's line (the words stay in view), its leading edge on the block button.
            let hang = NSRect(
                x: frame.minX + LoreSelectionBar.shadowRoom + Space.s1, y: line.minY - Space.s1, width: 0, height: 0)
            closeMenu(cancel: true)
            menu = LoreInsertMenu(
                mode: .blocks, anchor: tv.selectedRange().location, typed: true, hang: hang, window: tv.window,
                current: tv.currentBlock(), animated: true
            ) { [weak self] in self?.choose($0) }
        }
    }

    // MARK: insert menu

    /// `/` was typed: on an empty Text line it opens the insert menu.
    func slashTyped() {
        let c = tv.content(tv.paraRange)
        guard tv.currentBlock() == .p, tv.ns.substring(with: c) == "/", tv.picker == nil else { return }
        open(anchor: c.location, typed: true, animated: false)
    }

    /// ⌥⌘/ or the + (or More… for `templates`): puts the `/` in itself, so Esc takes it away again.
    func openInsert(typed: Bool, animated: Bool, templates: Bool = false) {
        tv.closePicker()
        let sel = tv.selectedRange()
        tv.setSelectedRange(NSRange(location: NSMaxRange(sel), length: 0))
        tv.insertPlain("/")
        open(anchor: tv.cursor - 1, typed: typed, animated: animated, templates: templates)
    }

    private func open(anchor: Int, typed: Bool, animated: Bool, templates: Bool = false) {
        closeMenu(cancel: true)
        hideBar()
        let caret = tv.firstRect(forCharacterRange: NSRange(location: anchor, length: 0), actualRange: nil)
        menu = LoreInsertMenu(
            mode: templates ? .templates : .insert, anchor: anchor, typed: typed, hang: caret, window: tv.window,
            animated: animated
        ) { [weak self] in self?.choose($0) }
        updateGutter()
    }

    /// After a key in insert mode: the text after the `/` filters; leaving it closes the menu (the text stays).
    func updateMenu() {
        guard let m = menu, m.mode != .blocks else { return closeMenu(cancel: true) }
        let start = m.anchor + 1
        guard tv.cursor >= start, m.anchor < tv.ns.length, tv.ns.character(at: m.anchor) == 47 else {
            return closeMenu(cancel: false)
        }
        let q = tv.ns.substring(with: NSRange(location: start, length: tv.cursor - start))
        if q.contains("\n") || q.count > 24 { return closeMenu(cancel: false) }
        m.update(query: q)
        // A space after a word nothing answers to: it was text, not a command.
        if m.isEmpty, q.hasSuffix(" ") { closeMenu(cancel: false) }
    }

    func move(_ d: Int) { menu?.move(d) }

    /// Return or Tab: the highlighted item; nothing matches, the menu closes and the text stays.
    func chooseCurrent() {
        if let item = menu?.current { choose(item) } else { closeMenu(cancel: false) }
    }

    /// Esc (`cancel`) on a `/` the menu put in itself takes it away; any other close leaves the text as it is.
    func closeMenu(cancel: Bool) {
        guard let m = menu else { return }
        menu = nil
        m.close()
        if cancel, m.mode != .blocks, !m.typed, m.anchor < tv.ns.length, tv.ns.character(at: m.anchor) == 47 {
            let end = min(max(tv.cursor, m.anchor + 1), tv.ns.length)
            tv.edit { tv.replace(NSRange(location: m.anchor, length: end - m.anchor), with: "") }
            tv.setSelectedRange(NSRange(location: m.anchor, length: 0))
        }
        updateGutter()
    }

    func closeAll() {
        closeMenu(cancel: false)
        hideBar()
        gutter?.isHidden = true
    }

    /// The page scrolled: what floats over it goes (a Mac menu closes on scroll too).
    func scrolled() {
        // Typing near the bottom scrolls the page too: the insert menu the person is typing into stays.
        if menu?.mode == .blocks { closeMenu(cancel: false) }
        hideBar()
    }

    private func choose(_ entry: LoreMenuEntry) {
        guard let m = menu else { return }
        closeMenu(cancel: false)
        if m.mode != .blocks {
            // Template: the same `/` now lists the templates (what was typed after it goes; it filters them anew).
            if entry == .item(.template) {
                let q = NSRange(location: m.anchor + 1, length: max(0, min(tv.cursor, tv.ns.length) - m.anchor - 1))
                if q.length > 0 { tv.edit { tv.replace(q, with: "") } }
                tv.setSelectedRange(NSRange(location: m.anchor + 1, length: 0))
                return open(anchor: m.anchor, typed: m.typed, animated: false, templates: true)
            }
            let r = NSRange(location: m.anchor, length: max(0, min(tv.cursor, tv.ns.length) - m.anchor))
            tv.edit { tv.replace(r, with: "") }
            tv.setSelectedRange(NSRange(location: m.anchor, length: 0))
        }
        switch entry {
        case .item(let item): apply(item)
        case .template(let t): tv.insertTemplate(t)
        }
    }

    func apply(_ item: LoreInsertItem) {
        if let b = item.block { return tv.applyBlock(b) }
        switch item {
        case .table: tv.insertBlocks(LoreFormat.table)
        case .divider: tv.insertBlocks("---\n")
        case .date: tv.insertPlain(LoreFormat.stamp() + " ")
        case .noteLink:
            tv.insertPlain("[[")
            tv.linkTrigger()
        case .image: imagePrompt()
        case .template: openInsert(typed: false, animated: false, templates: true)
        default: break
        }
    }

    // MARK: the + beside an empty line

    /// Shown while the caret sits on an empty Text line of the focused page; a click opens the insert menu.
    func updateGutter() {
        let sel = tv.selectedRange()
        let show =
            tv.window?.firstResponder === tv && sel.length == 0 && menu == nil && tv.picker == nil
            && tv.currentBlock() == .p && tv.content(tv.paraRange).length == 0
        guard show, let window = tv.window else {
            if let g = gutter, !g.isHidden { fade(g, in: false) }
            return
        }
        let g = gutter ?? makeGutter()
        let screen = tv.firstRect(forCharacterRange: NSRange(location: sel.location, length: 0), actualRange: nil)
        let line = tv.convert(window.convertFromScreen(screen), from: nil)
        let side = MacSize.controlMd
        let x = max(0, tv.textContainerInset.width - side - Space.s2)
        let moved = abs(g.frame.minY - (line.midY - side / 2)) > 0.5
        g.frame = NSRect(x: x, y: (line.midY - side / 2).rounded(), width: side, height: side)
        if g.isHidden || moved { fade(g, in: true) }
    }

    private func makeGutter() -> NSHostingView<LoreGutterButton> {
        let g = NSHostingView(
            rootView: LoreGutterButton { [weak self] in self?.openInsert(typed: false, animated: true) })
        g.isHidden = true
        tv.addSubview(g)
        gutter = g
        return g
    }

    /// The + fades; it is there tens of times a day, so it is quick and never moves.
    private func fade(_ v: NSView, in show: Bool) {
        if show {
            v.alphaValue = 0
            v.isHidden = false
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Motion.hover
            v.animator().alphaValue = show ? 1 : 0
        } completionHandler: {
            MainActor.assumeIsolated { if !show, v.alphaValue == 0 { v.isHidden = true } }
        }
    }

    // MARK: prompts

    /// ⇧⌘K or the bar's link: a short sheet for the address. A link on the selection can be changed or removed.
    func linkPrompt() {
        let sel = tv.selectedRange()
        guard sel.length > 0, let window = tv.window else {
            tv.controller?.onNotice?("Select the words to link first.")
            return
        }
        let had = tv.selectionHasLink
        let current = (tv.ts.attribute(.link, at: sel.location, effectiveRange: nil) as? URL)?.absoluteString
        let pasted = NSPasteboard.general.string(forType: .string).flatMap { LoreFormat.address($0)?.absoluteString }
        let field = Self.field(current ?? pasted ?? "", placeholder: "https://example.com")
        let alert = Self.alert("Add Link", "A web or mail address.", field: field, ok: had ? "Change Link" : "Add Link")
        if had { alert.addButton(withTitle: "Remove Link") }
        present(alert, in: window) { [weak self] r in
            guard let self else { return }
            self.tv.setSelectedRange(sel)
            switch r {
            case .alertFirstButtonReturn:
                if let u = LoreFormat.address(field.stringValue) {
                    self.tv.applyLink(u)
                } else {
                    self.tv.controller?.onNotice?("Use a web or mail address, like https://example.com.")
                }
            case .alertThirdButtonReturn: self.tv.applyLink(nil)
            default: break
            }
        }
    }

    /// With an uploader (the Core stores attachments) a file is chosen and uploaded; without one, a web address is
    /// added as an image link. Either way the note never loads it (T9).
    func imagePrompt() {
        guard let window = tv.window, let controller = tv.controller else { return }
        let at = tv.selectedRange()
        if !(controller.uploader is LoreNoUploads) {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = LoreLinkPolicy.uploadTypes
            panel.allowsMultipleSelection = false
            prompting = true
            panel.beginSheetModal(for: window) { [weak self] r in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.prompting = false
                    self.tv.window?.makeFirstResponder(self.tv)
                    guard r == .OK, let url = panel.url else { return }
                    self.tv.setSelectedRange(at)
                    // The paste path checks the file's real type and size before a byte is read.
                    let pb = NSPasteboard(name: .init("lore-image-\(UUID().uuidString)"))
                    pb.clearContents()
                    pb.writeObjects([url as NSURL])
                    _ = self.tv.readPasteboard(pb)
                    pb.releaseGlobally()
                }
            }
            return
        }
        let field = Self.field("", placeholder: "https://example.com/photo.jpg")
        let alert = Self.alert(
            "Add Image",
            "Images are not kept on the Core yet. Add a web address: the note shows it as a link and "
                + "never loads it.", field: field, ok: "Add Image")
        present(alert, in: window) { [weak self] r in
            guard let self, r == .alertFirstButtonReturn else { return }
            guard let u = LoreFormat.address(field.stringValue), ["http", "https"].contains(u.scheme ?? "") else {
                self.tv.controller?.onNotice?("Use a web address, like https://example.com/photo.jpg.")
                return
            }
            let base = u.deletingPathExtension().lastPathComponent
            let name = (base.isEmpty || base == "/" ? u.host ?? "Image" : base).filter { !"[]()\n\r".contains($0) }
            self.tv.insertMarkdown("![\(name)](\(u.absoluteString))", at: at)
        }
    }

    private func present(
        _ alert: NSAlert, in window: NSWindow, done: @escaping @MainActor (NSApplication.ModalResponse) -> Void
    ) {
        prompting = true
        hideBar()
        alert.beginSheetModal(for: window) { [weak self] r in
            MainActor.assumeIsolated {
                self?.prompting = false
                if let tv = self?.tv { tv.window?.makeFirstResponder(tv) }
                done(r)
            }
        }
    }

    private static func field(_ value: String, placeholder: String) -> NSTextField {
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: Space.s8 * 9, height: MacSize.controlMd - Space.s1))
        f.stringValue = value
        f.placeholderString = placeholder
        // No focus rings (CoreUI rule).
        f.focusRingType = .none
        return f
    }

    private static func alert(_ title: String, _ line: String, field: NSTextField, ok: String) -> NSAlert {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = line
        a.accessoryView = field
        a.addButton(withTitle: ok)
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        return a
    }
}

/// The quiet + in the margin of an empty line.
struct LoreGutterButton: View {
    let action: () -> Void
    var body: some View {
        CoreIconButton(symbol: "plus", label: "Add a block  /", action: action)
            .foregroundStyle(GlassInk.secondary)
            .coreTheme()
    }
}
