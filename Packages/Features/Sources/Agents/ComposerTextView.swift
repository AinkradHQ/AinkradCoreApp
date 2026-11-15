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
    /// Files pasted or dropped into the field (a pasted image without a file is saved first).
    let onFiles: ([URL]) -> Void

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
        tv.onFiles = onFiles
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
    var onFiles: (([URL]) -> Void)?

    /// ⌘V: files and pasted images become attachments, words stay words.
    override func paste(_ sender: Any?) {
        if let files = Self.files(from: .general), !files.isEmpty {
            onFiles?(files)
        } else {
            super.paste(sender)
        }
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let files = Self.files(from: sender.draggingPasteboard), !files.isEmpty {
            onFiles?(files)
            return true
        }
        return super.performDragOperation(sender)
    }

    /// The files on a pasteboard: file URLs; else an image with no words beside it (a screenshot), saved to a file. Nil
    /// when it holds words, so a rich copy from a page still pastes its text.
    /// Whether a pasteboard holds files or a lone image, without saving anything (menu validation asks often).
    static func hasFiles(_ pb: NSPasteboard) -> Bool {
        pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || (pb.string(forType: .string) == nil && NSImage.canInit(with: pb))
    }

    static func files(from pb: NSPasteboard) -> [URL]? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
            !urls.isEmpty
        {
            return urls
        }
        guard pb.string(forType: .string) == nil, let image = NSImage(pasteboard: pb) else { return nil }
        return AttachmentStore.save(image).map { [$0] }
    }

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

    /// The composer field that holds the keyboard, if any: the pane's own shortcuts step aside while it does. Read from
    /// the field itself, not the key window (which is not always ours) nor SwiftUI's focus (which drifts).
    nonisolated(unsafe) static weak var focusedField: KeyTextView?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            Self.focusedField = self
            onFocus?(true)
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            if Self.focusedField === self { Self.focusedField = nil }
            onFocus?(false)
        }
        return ok
    }

    /// Paste stays on for files and images: a plain-text field reads words only, so the system greyed Paste out for a
    /// copied image and ⌘V never reached `paste(_:)`.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.fileURL, .png, .tiff]
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), Self.hasFiles(.general) { return true }
        return super.validateUserInterfaceItem(item)
    }
}

/// Where pasted images are kept so a tool can read them by path: the app's caches, one PNG each.
enum AttachmentStore {
    static func save(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:]),
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = caches.appending(path: "com.ainkrad.core/attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "pasted-\(UUID().uuidString.prefix(8)).png")
        return (try? png.write(to: url)) != nil ? url : nil
    }
}
