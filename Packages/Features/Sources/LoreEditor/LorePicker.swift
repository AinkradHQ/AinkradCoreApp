import AppKit
import CoreUI
import SwiftUI

struct LorePickerView: View {
    var query = ""
    var items: [String] = []
    var selected = 0
    var onChoose: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            if items.isEmpty {
                Text(query.isEmpty ? "No notes yet" : "No matching note")
                    .coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                    .padding(.horizontal, Space.s3)
                    .frame(maxWidth: .infinity, minHeight: MacSize.controlLg, alignment: .leading)
            }
            // TODO(design-system): proposal CoreMenuList — the dropdown panel's rows, driven by a caller's own keyboard
            // (the text view keeps focus here). CoreRow is the closest public row until then.
            ForEach(Array(items.enumerated()), id: \.element) { i, title in
                CoreRow(title, symbol: "doc.text", selected: i == selected) { onChoose(title) }
                    .help("Link to \(title) (Return)")
            }
        }
        .padding(Space.s1)
        .frame(width: Space.s8 * 8, alignment: .leading)
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1, part: .popups)
        .padding(Space.s6)  // room for the frame's shadow inside the panel
        .fixedSize()
        .coreTheme()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Link to a note")
    }
}

/// `[[` note-link picker: a non-activating child panel under the caret. The text view keeps focus; typing filters,
/// ↑/↓ move, Return or Tab pick, Escape closes. Not animated: it opens on every `[[` (keyboard-driven, many times a day).
@MainActor final class LorePicker {
    let anchor: Int
    /// Set whole on every change, so the panel is redrawn and sized at once (an observed model in a non-key panel was
    /// drawn a step late).
    private var model = LorePickerView() {
        didSet {
            host.rootView = model
            place()
        }
    }
    private let panel: NSPanel
    private let host: NSHostingView<LorePickerView>
    private weak var textView: NSTextView?
    private let source: LoreNoteTitles
    private var lookup: Task<Void, Never>?

    init(anchor: Int, textView: NSTextView, source: LoreNoteTitles, onChoose: @escaping (String) -> Void) {
        self.anchor = anchor
        self.textView = textView
        self.source = source
        model.onChoose = onChoose
        host = NSHostingView(rootView: model)
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.contentView = host
        update(query: "")
        place()
        textView.window?.addChildWindow(panel, ordered: .above)
    }

    var current: String? { model.items.indices.contains(model.selected) ? model.items[model.selected] : nil }

    func update(query: String) {
        model.query = query
        lookup?.cancel()
        lookup = Task { [weak self, source] in
            let found = Array(await source.titles(matching: query).prefix(8))
            guard let self, !Task.isCancelled, self.model.query == query else { return }
            var next = self.model
            next.items = found
            next.selected = min(next.selected, max(0, found.count - 1))
            self.model = next
        }
    }

    func move(_ d: Int) {
        guard !model.items.isEmpty else { return }
        model.selected = (model.selected + d + model.items.count) % model.items.count
    }

    func close() {
        lookup?.cancel()
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func place() {
        guard let tv = textView else { return }
        let caret = tv.firstRect(forCharacterRange: NSRange(location: anchor, length: 0), actualRange: nil)
        let size = host.fittingSize
        // The list's leading edge sits on the `[[`, its top just under the line.
        panel.setFrame(
            NSRect(
                x: caret.minX - Space.s6 - Space.s1, y: caret.minY - size.height + Space.s6 - Space.s1,
                width: size.width, height: size.height),
            display: true)
    }
}
