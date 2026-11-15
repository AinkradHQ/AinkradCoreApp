import AppKit
import SwiftUI

/// What the composer does with the keys its field hears. Each returns true when it took the key.
struct ComposerKeys {
    /// Return or Enter; `shift` for ⇧Return. False lets the field insert a new line.
    var submit: (_ shift: Bool) -> Bool
    var up: () -> Bool
    var down: () -> Bool
    var tab: () -> Bool
    var escape: () -> Bool
}

/// The composer's text field (Ahmed, 2026-11-15: Enter sometimes did not send, and the command list ignored the arrows).
/// A SwiftUI TextEditor is an NSTextView that takes Return, ↑, ↓, Tab and Esc itself before SwiftUI hears them; the old
/// fix was a window-wide key monitor installed only while SwiftUI *thought* the field was focused, and that focus drifts
/// (after a click, a sheet, a pane switch), so the monitor came and went. This field is its own NSTextView: it hands
/// those keys to the composer itself, every time, with no monitor and no dependence on SwiftUI's focus.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let enabled: Bool
    let font: NSFont
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let keys: ComposerKeys

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = KeyTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.setAccessibilityIdentifier("agent-composer")
        tv.setAccessibilityLabel("Message")
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = tv
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? KeyTextView else { return }
        // Fresh closures on every update: nothing stale (the old monitor kept the first session's closure).
        tv.keys = keys
        tv.onFocus = { [weak coordinator = context.coordinator] on in coordinator?.focusChanged(on) }
        tv.isEditable = enabled
        tv.isSelectable = true
        if tv.font != font {
            tv.font = font
            tv.typingAttributes[.font] = font
        }
        tv.textColor = .labelColor
        tv.insertionPointColor = .labelColor
        if tv.string != text {
            tv.string = text
            tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        // SwiftUI asked for the field: make it first responder once it is in a window.
        if focused.wrappedValue, enabled, let window = tv.window, window.firstResponder !== tv {
            DispatchQueue.main.async { window.makeFirstResponder(tv) }
        }
    }

    /// Grows with its text between `minHeight` and `maxHeight`; past that it scrolls.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        guard let tv = nsView.documentView as? NSTextView, let lm = tv.layoutManager, let tc = tv.textContainer else {
            return CGSize(width: width, height: minHeight)
        }
        tc.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height
        let line = font.ascender - font.descender + font.leading
        return CGSize(width: width, height: min(max(max(used, line), minHeight), maxHeight))
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: KeyTextView?
        init(_ parent: ComposerTextView) { self.parent = parent }

        func textDidChange(_ note: Notification) {
            guard let tv = note.object as? NSTextView else { return }
            if parent.text != tv.string { parent.text = tv.string }
        }

        func focusChanged(_ on: Bool) {
            guard parent.focused.wrappedValue != on else { return }
            let binding = parent.focused
            DispatchQueue.main.async { binding.wrappedValue = on }
        }
    }
}

/// An NSTextView that gives the composer its keys first. IME composition keeps Return until it is done.
final class KeyTextView: NSTextView {
    var keys: ComposerKeys?
    var onFocus: ((Bool) -> Void)?

    override func doCommand(by selector: Selector) {
        if hasMarkedText() || keys == nil {
            super.doCommand(by: selector)
            return
        }
        let shift = keyFlags.contains(.shift)
        let took: Bool =
            switch selector {
            case #selector(insertNewline(_:)): keys?.submit(shift) ?? false
            case #selector(moveUp(_:)): keys?.up() ?? false
            case #selector(moveDown(_:)): keys?.down() ?? false
            case #selector(insertTab(_:)): keys?.tab() ?? false
            case #selector(cancelOperation(_:)): keys?.escape() ?? false
            default: false
            }
        if took { return }
        // Tab and ⇧Tab move to the next and previous control, so the keyboard can leave the field (⌥Tab types a tab).
        if selector == #selector(insertTab(_:)) {
            window?.selectNextKeyView(nil)
        } else if selector == #selector(insertBacktab(_:)) {
            window?.selectPreviousKeyView(nil)
        } else {
            super.doCommand(by: selector)
        }
    }

    /// The modifiers of the key being handled, taken from the key itself (the app's current event is not always it).
    private var keyFlags: NSEvent.ModifierFlags = []

    override func keyDown(with event: NSEvent) {
        keyFlags = event.modifierFlags
        defer { keyFlags = [] }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocus?(false) }
        return ok
    }
}
