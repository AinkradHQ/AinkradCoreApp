import SwiftUI

public enum CoreButtonKind: Sendable { case prominent, secondary, plain }
public enum CoreButtonSize: Sendable {
    case small, medium, large
    var height: CGFloat {
        switch self {
        case .small: MacSize.controlSm
        case .medium: MacSize.controlMd
        case .large: MacSize.controlLg
        }
    }
    var text: CGFloat { self == .large ? MacTextSize.title : self == .small ? MacTextSize.meta : MacTextSize.body }
    var radius: CGFloat { self == .small ? Radius.chip : Radius.control }
}

/// Prominent (one per card), secondary (glass edge, never reads as plain text) and plain buttons.
/// States: rest, hover, pressed, focus, disabled, busy.
public struct CoreButtonStyle: ButtonStyle {
    let kind: CoreButtonKind
    let size: CoreButtonSize
    let busy: Bool
    public init(_ kind: CoreButtonKind = .secondary, size: CoreButtonSize = .medium, busy: Bool = false) {
        self.kind = kind
        self.size = size
        self.busy = busy
    }
    public func makeBody(configuration: Configuration) -> some View {
        CoreButtonBody(configuration: configuration, kind: kind, size: size, busy: busy)
    }
}

extension ButtonStyle where Self == CoreButtonStyle {
    public static var coreProminent: CoreButtonStyle { CoreButtonStyle(.prominent) }
    public static var coreSecondary: CoreButtonStyle { CoreButtonStyle(.secondary) }
    public static var corePlain: CoreButtonStyle { CoreButtonStyle(.plain) }
}

private struct CoreButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: CoreButtonKind
    let size: CoreButtonSize
    let busy: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.coreForcedInteraction) private var forced
    @State private var hovering = false

    private var pressed: Bool { configuration.isPressed || forced == .pressed }
    private var hover: Bool { hovering || forced == .hover }

    var body: some View {
        let ink = kind == .prominent ? palette.btnInk : palette.text
        ZStack {
            configuration.label.opacity(busy ? 0 : 1)
            if busy { ProgressView().controlSize(.small).tint(ink) }
        }
        .font(.system(size: size.text, weight: .medium))
        .foregroundStyle(ink)
        .frame(minHeight: size.height)
        .padding(.horizontal, size == .small ? Space.s2 : Space.s3)
        .background(fill, in: coreShape(size.radius))
        .overlay {
            if kind == .secondary {
                coreShape(size.radius).strokeBorder(palette.glassCardEdge, lineWidth: 1)
            }
        }
        .coreFocusRing(focused || forced == .focused, radius: size.radius, palette: palette)
        .opacity(enabled ? 1 : 0.45)
        .scaleEffect(pressed && !reduce ? 0.97 : 1)
        .animation(reduce ? nil : Motion.press(Motion.press), value: pressed)
        .animation(Motion.out(Motion.hover), value: hover)
        .onHover { hovering = $0 }
        .focusEffectDisabled()
        .allowsHitTesting(!busy)
        .accessibilityAddTraits(busy ? .updatesFrequently : [])
        .accessibilityValue(busy ? "Busy" : "")
    }

    private var fill: Color {
        switch kind {
        case .prominent: pressed ? palette.btnPrimaryPress : hover ? palette.btnPrimaryHover : palette.btnPrimary
        case .secondary: hover || pressed ? palette.uDim : .clear
        case .plain: hover || pressed ? palette.uDim : .clear
        }
    }
}
