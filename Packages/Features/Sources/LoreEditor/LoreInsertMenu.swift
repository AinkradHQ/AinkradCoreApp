// LoreInsertMenu — the compact list the editor opens at the caret: `/` on an empty line (or ⌥⌘/, or the + beside an
// empty line) lists what can be added; the selection bar's block button lists what a paragraph can be. Typing filters,
// ↑ ↓ move, Return or Tab pick, Esc closes. The text view keeps focus the whole time.
import AppKit
import CoreUI
import SwiftUI

/// One thing the menu can add or turn a paragraph into.
public enum LoreInsertItem: String, CaseIterable, Identifiable, Sendable {
    case text, h1, h2, h3, quote, bullet, numbered, checklist, table, code, divider, image, noteLink, date

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .h1: "Heading 1"
        case .h2: "Heading 2"
        case .h3: "Heading 3"
        case .quote: "Quote"
        case .bullet: "Bullet list"
        case .numbered: "Numbered list"
        case .checklist: "Checklist"
        case .table: "Table"
        case .code: "Code block"
        case .divider: "Divider"
        case .image: "Image"
        case .noteLink: "Link to note"
        case .date: "Date and time"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .h1: "textformat.size.larger"
        case .h2: "textformat.size"
        case .h3: "textformat.size.smaller"
        case .quote: "text.quote"
        case .bullet: "list.bullet"
        case .numbered: "list.number"
        case .checklist: "checklist"
        case .table: "tablecells"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .divider: "minus"
        case .image: "photo"
        case .noteLink: "link"
        case .date: "calendar"
        }
    }

    /// What to type for it without the menu (the Markdown shortcut), or a word on what it adds.
    var hint: String {
        switch self {
        case .text: ""
        case .h1: "#"
        case .h2: "##"
        case .h3: "###"
        case .quote: ">"
        case .bullet: "-"
        case .numbered: "1."
        case .checklist: "[]"
        case .table: "3 × 3"
        case .code: "```"
        case .divider: "---"
        case .image: "Web address"
        case .noteLink: "[["
        case .date: "Now"
        }
    }

    /// Other words it answers to when typed after `/`.
    private var words: [String] {
        switch self {
        case .text: ["paragraph", "plain"]
        case .h1: ["h1", "title"]
        case .h2: ["h2"]
        case .h3: ["h3"]
        case .quote: ["blockquote"]
        case .bullet: ["ul", "list", "unordered"]
        case .numbered: ["ol", "list", "ordered"]
        case .checklist: ["todo", "task", "list", "checkbox"]
        case .table: ["grid"]
        case .code: ["pre", "snippet"]
        case .divider: ["rule", "line", "hr", "separator"]
        case .image: ["picture", "photo"]
        case .noteLink: ["wiki", "note", "page"]
        case .date: ["time", "today", "stamp"]
        }
    }

    /// The block it makes, for the ones that change a paragraph.
    var block: Block? {
        switch self {
        case .text: .p
        case .h1: .h(1)
        case .h2: .h(2)
        case .h3: .h(3)
        case .quote: .quote
        case .bullet: .ul(0)
        case .numbered: .ol(0)
        case .checklist: .task(0, false)
        case .code: .code
        default: nil
        }
    }

    /// The selection bar's block menu.
    static let blocks: [LoreInsertItem] = [.text, .h1, .h2, .h3, .quote, .bullet, .numbered, .checklist, .code]
    /// `/` on an empty line (Text is what the line is already).
    static let inserts: [LoreInsertItem] = allCases.filter { $0 != .text }

    /// The item a block is shown as (its name on the selection bar, its check in the menu).
    static func of(_ b: Block) -> LoreInsertItem {
        switch b {
        case .p: .text
        case .h(let n): n == 1 ? .h1 : n == 2 ? .h2 : .h3
        case .quote: .quote
        case .ul: .bullet
        case .ol: .numbered
        case .task: .checklist
        case .code: .code
        }
    }

    /// Items whose title (or a word of it, or a word it answers to) starts with `query`; titles that start with it
    /// come first. An empty query keeps them all, in order.
    static func filter(_ query: String, in items: [LoreInsertItem] = inserts) -> [LoreInsertItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        let first = items.filter { $0.title.lowercased().hasPrefix(q) }
        let rest = items.filter { item in
            !first.contains(item)
                && (item.title.lowercased().split(separator: " ").contains { $0.hasPrefix(q) }
                    || item.words.contains { $0.hasPrefix(q) })
        }
        return first + rest
    }
}

struct LoreInsertMenuView: View {
    var items: [LoreInsertItem] = []
    var selected = 0
    /// The paragraph's block, checked (block menu only).
    var current: LoreInsertItem?
    /// Grow from the top (under the anchor) or the bottom (above it).
    var fromTop = true
    /// Opened by the mouse (the + or the bar's button) rises in; opened by `/` it is just there (typed many times a day).
    var animated = false
    var onChoose: (LoreInsertItem) -> Void = { _ in }
    @State private var shown = false
    @State private var hovered: LoreInsertItem?
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            if items.isEmpty {
                Text("No matching block").coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary)
                    .padding(.horizontal, Space.s3)
                    .frame(maxWidth: .infinity, minHeight: MacSize.controlMd + Space.s1, alignment: .leading)
            }
            ForEach(Array(items.enumerated()), id: \.element) { i, item in row(item, on: i == selected) }
        }
        .padding(Space.s1)
        .frame(width: LoreInsertMenu.width, alignment: .leading)
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1, part: .popups)
        .fixedSize()
        .opacity(shown || !animated ? 1 : 0)
        .scaleEffect(shown || !animated || reduce ? 1 : 0.97, anchor: fromTop ? .topLeading : .bottomLeading)
        .padding(LoreInsertMenu.shadowRoom)
        .frame(
            width: LoreInsertMenu.width + LoreInsertMenu.shadowRoom * 2, height: LoreInsertMenu.height,
            alignment: fromTop ? .topLeading : .bottomLeading
        )
        .coreTheme()
        .onAppear { withAnimation(Motion.calm(Motion.out(Motion.hover), reduce)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(current == nil ? "Insert a block" : "Turn into")
    }

    /// Headings show H1, H2, H3 (no symbol says it as plainly); the rest their symbol.
    @ViewBuilder private func glyph(_ item: LoreInsertItem) -> some View {
        switch item {
        case .h1, .h2, .h3: Text(item.rawValue.uppercased()).coreFont(size: MacTextSize.meta, weight: .bold)
        default: Image(systemName: item.symbol).coreFont(size: MacTextSize.body, weight: .medium)
        }
    }

    private func row(_ item: LoreInsertItem, on: Bool) -> some View {
        Button {
            onChoose(item)
        } label: {
            HStack(spacing: Space.s2) {
                glyph(item).foregroundStyle(GlassInk.secondary).frame(width: Space.s5).accessibilityHidden(true)
                Text(item.title).coreFont(size: MacTextSize.body).lineLimit(1)
                Spacer(minLength: Space.s3)
                if current == item {
                    Image(systemName: "checkmark").coreFont(size: MacTextSize.meta, weight: .bold)
                        .accessibilityHidden(true)
                } else if !item.hint.isEmpty {
                    Text(item.hint).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                }
            }
            .foregroundStyle(GlassInk.primary)
            .padding(.horizontal, Space.s2)
            .frame(height: MacSize.controlMd + Space.s1)
            .background(on || hovered == item ? GlassInk.wellHover : .clear, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? item : (hovered == item ? nil : hovered) }
        .help(item.hint.isEmpty ? item.title : "\(item.title)  \(item.hint)")
        .accessibilityAddTraits(on || current == item ? .isSelected : [])
    }
}

/// The menu's panel: a non-activating child panel under (or over) its anchor. One fixed size, the list hugging the
/// anchor's side, so it never resizes while the filter changes.
@MainActor final class LoreInsertMenu {
    enum Mode { case insert, blocks }
    nonisolated static let width = Space.s8 * 8
    nonisolated static let shadowRoom = Space.s6
    /// Room for every insert item.
    nonisolated static let height =
        CGFloat(LoreInsertItem.allCases.count) * (MacSize.controlMd + Space.s1 + Space.s1) + Space.s1 * 2
        + Space.s6 * 2

    let mode: Mode
    /// The `/` (insert) or the selection start (blocks).
    let anchor: Int
    /// The `/` was typed by the person: Esc leaves it. Opened by a key or the +, Esc takes it away again.
    let typed: Bool
    private let all: [LoreInsertItem]
    private(set) var query = ""
    private var model: LoreInsertMenuView {
        didSet { float.root = model }
    }
    private let float: LoreFloat<LoreInsertMenuView>

    /// `hang` is the screen rect to open against: under it when there is room, else over it.
    init(
        mode: Mode, anchor: Int, typed: Bool, hang: NSRect, window: NSWindow?, current: Block? = nil, animated: Bool,
        onChoose: @escaping (LoreInsertItem) -> Void
    ) {
        self.mode = mode
        self.anchor = anchor
        self.typed = typed
        all = mode == .insert ? LoreInsertItem.inserts : LoreInsertItem.blocks
        let room = hang.minY - (window?.screen?.visibleFrame.minY ?? 0)
        let below = room > Self.height - Self.shadowRoom
        var m = LoreInsertMenuView(
            items: all, current: current.map(LoreInsertItem.of), fromTop: below, animated: animated, onChoose: onChoose)
        if let current, mode == .blocks { m.selected = all.firstIndex(of: LoreInsertItem.of(current)) ?? 0 }
        model = m
        float = LoreFloat(m, parent: window)
        let size = CGSize(width: Self.width + Self.shadowRoom * 2, height: Self.height)
        let x = hang.minX - Self.shadowRoom - Space.s1
        let y = below ? hang.minY - size.height + Self.shadowRoom - Space.s1 : hang.maxY - Self.shadowRoom + Space.s1
        float.place(NSRect(origin: CGPoint(x: x, y: y), size: size))
    }

    var current: LoreInsertItem? { model.items.indices.contains(model.selected) ? model.items[model.selected] : nil }
    var isEmpty: Bool { model.items.isEmpty }

    func update(query q: String) {
        query = q
        var m = model
        m.items = LoreInsertItem.filter(q, in: all)
        m.selected = 0
        model = m
    }

    func move(_ d: Int) {
        guard !model.items.isEmpty else { return }
        model.selected = (model.selected + d + model.items.count) % model.items.count
    }

    func close() { float.close() }
}
