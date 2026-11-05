import SwiftUI

public enum CoreButtonKind: Sendable { case prominent, secondary, plain, danger }
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

extension View {
    /// Apple's own Liquid Glass button (`.glass` / `.glassProminent`) on macOS 26 / iOS 26, as an 8 pt rounded rect,
    /// tinted with the theme blue; the CoreUI button below that.
    @ViewBuilder
    public func coreGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26, iOS 26, *) {
            Group {
                // The theme's blue tint would flood the clear glass, so the secondary button drops it.
                if prominent, let tint {
                    buttonStyle(.glassProminent).tint(tint)
                } else if prominent {
                    buttonStyle(.glassProminent)
                } else {
                    buttonStyle(.glass).tint(nil)
                }
            }
            .buttonBorderShape(.roundedRectangle(radius: Radius.control))
            .controlSize(.large)
        } else {
            buttonStyle(prominent ? .coreProminent : .coreSecondary)
        }
    }
}

extension ButtonStyle where Self == CoreButtonStyle {
    public static var coreProminent: CoreButtonStyle { CoreButtonStyle(.prominent) }
    public static var coreSecondary: CoreButtonStyle { CoreButtonStyle(.secondary) }
    public static var corePlain: CoreButtonStyle { CoreButtonStyle(.plain) }
    public static var coreDanger: CoreButtonStyle { CoreButtonStyle(.danger) }
}

private struct CoreButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: CoreButtonKind
    let size: CoreButtonSize
    let busy: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.coreForcedInteraction) private var forced
    @State private var hovering = false

    private var pressed: Bool { configuration.isPressed || forced == .pressed }
    private var hover: Bool { hovering || forced == .hover }

    var body: some View {
        let ink = kind == .prominent || kind == .danger ? palette.btnInk : palette.text
        ZStack {
            configuration.label.opacity(busy ? 0 : 1)
            if busy { ProgressView().controlSize(.small).tint(ink) }
        }
        .font(.system(size: size.text, weight: .medium))
        .foregroundStyle(ink)
        .frame(minHeight: size.height)
        .padding(.horizontal, size == .small ? Space.s2 : Space.s3)
        .modifier(ButtonSurface(kind: kind, radius: size.radius, fill: fill, hover: hover))
        // Gallery only: pinned "focused" preview. Real focus is the system ring below, drawn only on the one control that
        // has keyboard focus (isFocused here reports the container's focus, which lit every button in it).
        .coreFocusRing(forced == .focused, radius: size.radius, palette: palette)
        .coreDimWhenDisabled(enabled)
        .scaleEffect(pressed && !reduce ? 0.97 : 1)
        .coreAnimation(Motion.press(Motion.press), value: pressed)
        .animation(Motion.out(Motion.hover), value: hover)
        .onHover { hovering = $0 }
        .contentShape(.focusEffect, coreShape(size.radius))
        .allowsHitTesting(!busy)
        .accessibilityAddTraits(busy ? .updatesFrequently : [])
        .accessibilityValue(busy ? "Busy" : "")
    }

    private var fill: Color {
        switch kind {
        case .prominent: pressed ? palette.btnPrimaryPress : hover ? palette.btnPrimaryHover : palette.btnPrimary
        case .secondary: hover || pressed ? palette.uDim : .clear
        case .plain: hover || pressed ? palette.uDim : .clear
        // ui.css `.btn.danger`: solid #D92D20, #E4402F on hover, white label in both themes.
        case .danger:
            hover || pressed
                ? Color(red: 0.894, green: 0.251, blue: 0.184) : Color(red: 0.851, green: 0.176, blue: 0.125)
        }
    }
}

/// Every CoreUI button is Liquid Glass on macOS 26 / iOS 26 (Ahmed, 2026-11-05: "everything shall be liquid glass"):
/// prominent and danger are glass tinted with their colour, secondary is clear glass, plain gets glass only on hover.
/// Below 26 the flat fills and edges of the prototype stay.
private struct ButtonSurface: ViewModifier {
    let kind: CoreButtonKind
    let radius: CGFloat
    let fill: Color
    let hover: Bool
    @Environment(\.corePalette) private var palette

    func body(content: Content) -> some View {
        let shape = coreShape(radius)
        if #available(macOS 26, iOS 26, *) {
            switch kind {
            case .prominent, .danger: content.glassEffect(.regular.tint(fill).interactive(), in: shape)
            case .secondary:
                content.glassEffect(.regular.tint(palette.glassTint.opacity(0.25)).interactive(), in: shape)
            case .plain:
                if hover { content.glassEffect(.regular.interactive(), in: shape) } else { content }
            }
        } else {
            content.background(fill, in: shape)
                .overlay {
                    if kind == .secondary {
                        shape.strokeBorder(palette.glassCardEdge, lineWidth: 1)
                    } else if kind == .prominent {
                        // ui.css `.btn.primary`: a 1 px light top edge (inset 0 1px 0 rgba(255,255,255,.22)).
                        shape.strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.22), location: 0),
                                    .init(color: .clear, location: 0.25),
                                ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                }
        }
    }
}
