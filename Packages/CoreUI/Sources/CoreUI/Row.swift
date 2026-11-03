import SwiftUI

/// List row: leading icon, title, subtitle, trailing state. States: rest, hover, selected, focus, disabled.
public struct CoreRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String?
    let selected: Bool
    let action: (() -> Void)?
    let trailing: Trailing

    public init(
        _ title: String, subtitle: String? = nil, symbol: String? = nil, selected: Bool = false,
        action: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.selected = selected
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        if let action {
            Button(action: action) {
                RowBody(title: title, subtitle: subtitle, symbol: symbol, selected: selected, trailing: trailing)
            }
            .buttonStyle(RowButtonStyle(selected: selected))
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            RowBody(title: title, subtitle: subtitle, symbol: symbol, selected: selected, trailing: trailing)
        }
    }
}

extension CoreRow where Trailing == EmptyView {
    public init(
        _ title: String, subtitle: String? = nil, symbol: String? = nil, selected: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(title, subtitle: subtitle, symbol: symbol, selected: selected, action: action) { EmptyView() }
    }
}

private struct RowBody<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String?
    let selected: Bool
    let trailing: Trailing
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: MacTextSize.title))
                    .foregroundStyle(selected ? palette.navActiveInk : palette.primary)
                    .frame(width: MacSize.controlMd)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                }
            }
            Spacer(minLength: Space.s2)
            trailing
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, minHeight: MacSize.controlLg + Space.s2, alignment: .leading)
        .contentShape(coreShape(Radius.row))
    }
}

private struct RowButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        RowChrome(configuration: configuration, selected: selected)
    }
}

private struct RowChrome: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.coreForcedInteraction) private var forced
    @State private var hovering = false

    var body: some View {
        let hover = hovering || configuration.isPressed || forced == .hover || forced == .pressed
        configuration.label
            .background(
                selected ? palette.navActive : hover ? palette.rowHover : palette.glassCard, in: coreShape(Radius.row)
            )
            .overlay {
                if selected { coreShape(Radius.row).strokeBorder(palette.navActiveEdge, lineWidth: 1) }
            }
            .coreFocusRing(focused || forced == .focused, radius: Radius.row, palette: palette)
            .opacity(enabled ? 1 : 0.45)
            .animation(Motion.out(Motion.hover), value: hover)
            .onHover { hovering = $0 }
            .focusEffectDisabled()
    }
}
