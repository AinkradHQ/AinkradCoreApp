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
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: Space.s3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: MacTextSize.title))
                    .foregroundStyle(selected ? palette.navActiveInk : palette.primary)
                    .frame(width: MacSize.controlMd)
                    .coreDimWhenDisabled(enabled)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                // Disabled dims the control (icon, title, trailing), not the helper line under it.
                Text(title).font(.system(size: MacTextSize.headline, weight: .semibold)).coreDimWhenDisabled(enabled)
                if let subtitle {
                    Text(subtitle).font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                }
            }
            Spacer(minLength: Space.s2)
            trailing.coreDimWhenDisabled(enabled)
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
    @Environment(\.coreForcedInteraction) private var forced
    @Environment(\.isFocused) private var isFocused
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed || forced == .pressed
        let hover = hovering || forced == .hover
        configuration.label
            .background(
                selected
                    ? palette.navActive : pressed ? palette.uDimHover : hover ? palette.rowHover : palette.glassCard,
                in: coreShape(Radius.row)
            )
            .overlay {
                if selected { coreShape(Radius.row).strokeBorder(palette.navActiveEdge, lineWidth: 1) }
            }
            .coreFocusRing(isFocused || forced == .focused, radius: Radius.row, palette: palette)
            .animation(Motion.out(Motion.hover), value: hover)
            .animation(Motion.out(Motion.press), value: pressed)
            .onHover { hovering = $0 }
            .contentShape(.focusEffect, coreShape(Radius.row))
    }
}
