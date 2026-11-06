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

    /// No head and no footer (Ahmed, 2026-11-05): the pane is the one frame, a clear glass rim holding its content on
    /// the Look's background; its title and actions live in its tab in the top bar. The active pane's edge is a touch
    /// brighter. The content may replace the Look for its app, or draw its own background (`paneLook`).
    public var body: some View {
        PaneFrame(active: active) {
            // Content takes exactly the pane's frame and never spills over a neighbour.
            content.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(sub.map { "\(title), \($0)" } ?? title)
    }
}

/// The pane's frame, following what its content asks for (`PaneLookKey`).
private struct PaneFrame<Content: View>: View {
    let active: Bool
    let content: Content
    @State private var ask: PaneLook = .inherit
    @Environment(\.coreLook) private var appearance
    init(active: Bool, @ViewBuilder content: () -> Content) {
        self.active = active
        self.content = content()
    }
    var body: some View {
        let look: CoreLook =
            switch ask {
            case .look(let l): l
            default: appearance
            }
        Group {
            if ask == .own {
                // The content draws its own background: the rim only.
                content.clipShape(coreShape(Radius.pane - Space.s2))
                    .padding(Space.s2)
                    .coreGlass(radius: Radius.pane, interactive: false, tinted: false)
                    .overlay {
                        coreShape(Radius.pane).strokeBorder(.white.opacity(active ? 0.3 : 0.12), lineWidth: 1)
                    }
            } else {
                content.coreFrame(radius: Radius.pane, rim: Space.s2, active: active)
            }
        }
        .environment(\.coreLook, look)
        .onPreferenceChange(PaneLookKey.self) { ask = $0 }
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
