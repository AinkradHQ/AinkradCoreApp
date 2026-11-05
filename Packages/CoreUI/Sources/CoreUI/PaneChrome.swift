import SwiftUI

/// One pane: panel surface, a head (icon, title, sub, state chip, close) and the body. The head is the drag handle.
public struct CorePaneChrome<Content: View>: View {
    let title: String
    let sub: String?
    let symbol: String
    let state: (label: String, tone: Tone, symbol: String)?
    let active: Bool
    let onClose: () -> Void
    let content: Content
    @Environment(\.corePalette) private var palette

    public init(
        title: String, sub: String? = nil, symbol: String, state: (label: String, tone: Tone, symbol: String)? = nil,
        active: Bool = false, onClose: @escaping () -> Void, @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.sub = sub
        self.symbol = symbol
        self.state = state
        self.active = active
        self.onClose = onClose
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s2) {
                // Neutral icon and a 13 pt title, as the prototype's pane head (`shell.css` .pane-head).
                Image(systemName: symbol).foregroundStyle(palette.text2).accessibilityHidden(true)
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold)).lineLimit(1)
                if let sub {
                    Text(sub).font(.system(size: MacTextSize.body)).foregroundStyle(palette.text2).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                if let state { StateBadge(state.label, tone: state.tone, symbol: state.symbol) }
                CoreIconButton(symbol: "xmark", label: "Close \(title)", action: onClose)
            }
            .padding(.horizontal, Space.s4)
            .frame(height: MacSize.controlLg + Space.s4)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .corePanel(radius: Radius.pane, padding: 0)
        .clipShape(coreShape(Radius.pane))
        .overlay {
            coreShape(Radius.pane).strokeBorder(active ? palette.navActiveEdge : palette.glassCardEdge, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(sub.map { "\(title), \($0)" } ?? title)
    }
}

/// Square icon button: a glyph on a rounded rectangle that lights on hover and shows the focus ring.
public struct CoreIconButton: View {
    let symbol: String
    let label: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool
    @State private var hovering = false

    public init(symbol: String, label: String, selected: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: MacTextSize.body, weight: .medium))
                .frame(width: MacSize.controlMd, height: MacSize.controlMd)
                .background(
                    selected ? palette.navActive : hovering ? palette.uDimHover : .clear, in: coreShape(Radius.control)
                )
                .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .coreFocusRing(focused, radius: Radius.control, palette: palette)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A keyboard key as text on a small rounded rectangle (launcher footer, shortcut list).
public struct CoreKeycap: View {
    let keys: String
    @Environment(\.corePalette) private var palette
    public init(_ keys: String) { self.keys = keys }
    public var body: some View {
        Text(keys)
            .font(.system(size: MacTextSize.meta, weight: .medium))
            .foregroundStyle(palette.text2)
            .padding(.horizontal, Space.s2)
            .frame(minWidth: MacSize.chip, minHeight: MacSize.chip)
            .background(palette.uDim, in: coreShape(Radius.chip))
            .accessibilityLabel(keys)
    }
}
