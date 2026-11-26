// LoreSelectionBar — the small glass bar over a selection: the block it is in (a menu), Bold, Italic, Strikethrough,
// Code and Link. It follows the Look (the pop-up surface) and grows out of the selection; Reduce Motion: it fades.
import AppKit
import CoreUI
import SwiftUI

/// A borderless, non-activating child panel floating a SwiftUI view over the page: the text view keeps focus and
/// the selection, and the panel's clear parts let clicks through.
@MainActor final class LoreFloat<Content: View> {
    private let panel: NSPanel
    private let host: NSHostingView<Content>

    init(_ root: Content, parent: NSWindow?) {
        host = NSHostingView(rootView: root)
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.contentView = host
        parent?.addChildWindow(panel, ordered: .above)
    }

    var root: Content {
        get { host.rootView }
        set { host.rootView = newValue }
    }

    var fitting: CGSize { host.fittingSize }
    var frame: NSRect { panel.frame }

    func place(_ r: NSRect) { panel.setFrame(r, display: true) }

    func close() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}

enum LoreBarAction: Equatable {
    case mark(LoreMark)
    case link, blocks
}

/// The keys the bar and the editor answer to (the bar's tooltips show them).
enum LoreToolKeys {
    static func label(_ m: LoreMark) -> String {
        switch m {
        case .bold: "⌘B"
        case .italic: "⌘I"
        case .strike: "⇧⌘X"
        case .code: "⌘E"
        }
    }
    static let link = "⇧⌘K"
    static let insert = "⌥⌘/"
}

struct LoreSelectionBarView: View {
    var marks: Set<LoreMark> = []
    var link = false
    var block: LoreInsertItem = .text
    /// Over the selection (grows up from it) or under it (grows down).
    var above = true
    var run: (LoreBarAction) -> Void = { _ in }
    @State private var shown = false
    @State private var blockHover = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(spacing: Space.s2) {
            blockButton
            HStack(spacing: 0) {
                mark(.bold, "bold", "Bold")
                mark(.italic, "italic", "Italic")
                mark(.strike, "strikethrough", "Strikethrough")
                mark(.code, "chevron.left.forwardslash.chevron.right", "Code")
            }
            CoreIconButton(
                symbol: "link", label: (link ? "Change or remove the link  " : "Add a link  ") + LoreToolKeys.link,
                selected: link
            ) { run(.link) }
        }
        .padding(Space.s1)
        .coreFrame(radius: Radius.cardMac + Space.s1, rim: Space.s1, part: .popups)
        .fixedSize()
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown || reduce ? 1 : 0.96, anchor: above ? .bottom : .top)
        .offset(y: shown ? 0 : coreMove(reduce, above ? Space.s1 : -Space.s1))
        .padding(LoreSelectionBar.shadowRoom)
        .coreTheme()
        .onAppear { withAnimation(Motion.calm(Motion.out(Motion.press), reduce)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Format")
    }

    private func mark(_ m: LoreMark, _ symbol: String, _ name: String) -> some View {
        CoreIconButton(
            symbol: symbol, label: "\(name)  \(LoreToolKeys.label(m))", selected: marks.contains(m)
        ) { run(.mark(m)) }
    }

    /// The paragraph's kind, opening the block menu.
    private var blockButton: some View {
        Button {
            run(.blocks)
        } label: {
            HStack(spacing: Space.s1) {
                Text(block.title).coreFont(size: MacTextSize.body, weight: .medium).lineLimit(1)
                Image(systemName: "chevron.down").coreFont(size: MacTextSize.meta, weight: .semibold)
                    .foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            }
            .padding(.horizontal, Space.s2)
            .frame(height: MacSize.controlMd)
            .background(blockHover ? GlassInk.wellHover : .clear, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { blockHover = $0 }
        .animation(Motion.out(Motion.hover), value: blockHover)
        .help("Turn into a heading, list, quote or code block")
        .accessibilityLabel("Block type, \(block.title)")
    }
}

enum LoreSelectionBar {
    nonisolated static let shadowRoom = Space.s4
}
