import SwiftUI

public enum CoreButtonKind: Sendable {
    case prominent, secondary, plain, danger
    /// Red ink and a red outline on a quiet fill: Delete, Revoke, Disconnect where a solid red tile would shout.
    case quietDanger
}
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
    /// The large glass button of first run and the failure cards: the CoreUI button (Liquid Glass on macOS 26), so it
    /// shows its key like every other; `tint` colours a prominent one (red for a destructive choice).
    @ViewBuilder
    public func coreGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        buttonStyle(CoreButtonStyle(tint != nil ? .danger : prominent ? .prominent : .secondary, size: .large))
    }
}

extension ButtonStyle where Self == CoreButtonStyle {
    public static var coreProminent: CoreButtonStyle { CoreButtonStyle(.prominent) }
    public static var coreSecondary: CoreButtonStyle { CoreButtonStyle(.secondary) }
    public static var corePlain: CoreButtonStyle { CoreButtonStyle(.plain) }
    public static var coreDanger: CoreButtonStyle { CoreButtonStyle(.danger) }
    public static var coreQuietDanger: CoreButtonStyle { CoreButtonStyle(.quietDanger) }
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
    @Environment(\.coreKeycap) private var keycap
    @Environment(\.isFocused) private var isFocused
    @State private var hovering = false

    private var pressed: Bool { configuration.isPressed || forced == .pressed }
    private var hover: Bool { hovering || forced == .hover }

    var body: some View {
        // White on the blue and red fills; the glass ink on the wells (dark by day).
        let solid = kind == .prominent || kind == .danger
        let ink: Color = kind == .quietDanger ? GlassInk.redInk : solid ? .white : GlassInk.primary
        HStack(spacing: Space.s2) {
            ZStack {
                configuration.label.opacity(busy ? 0 : 1)
                if busy { ProgressView().controlSize(.small).tint(ink) }
            }
            // The key that runs this button, shown on it (Ahmed, 2026-11-05: every action keyboard driven).
            if let keycap {
                // fixedSize: a keycap never gives way to its label ("Deny ⌘⌫" drew as "⌘…" on a small button).
                Text(keycap).coreFont(size: 10, weight: .medium, design: .rounded).fixedSize()
                    .padding(.horizontal, 5).frame(minHeight: 16)
                    .background(solid ? .white.opacity(0.16) : GlassInk.lift(0.16), in: coreShape(5))
                    .accessibilityHidden(true)
            }
        }
        .coreFont(size: size.text, weight: .semibold)
        .foregroundStyle(ink)
        .frame(minHeight: size.height)
        .padding(.horizontal, size == .small ? Space.s2 : Space.s3)
        .modifier(ButtonSurface(kind: kind, radius: size.radius, fill: fill, hover: hover, darken: pressed && reduce))
        // Keyboard focus: the hover fill step, a brighter edge and a 1 pt lift (D6), no ring.
        .coreFocusRing(isFocused || forced == .focused, radius: size.radius, palette: palette)
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
        case .plain, .quietDanger: hover || pressed ? palette.uDim : .clear
        // ui.css `.btn.danger`: solid #D92D20, #E4402F on hover, white label in both themes.
        case .danger:
            hover || pressed
                ? Color(red: 0.894, green: 0.251, blue: 0.184) : Color(red: 0.851, green: 0.176, blue: 0.125)
        }
    }
}

/// Every CoreUI button is the app-header tile (Ahmed, 2026-11-05: "apply this style of buttons everywhere"): prominent is
/// a soft blue tile, danger a soft red one, secondary a dark glass well; a light edge that brightens on hover.
/// No glow and no scale on hover (D3): hover is a fill step and a brighter edge. Plain buttons stay quiet until hovered.
private struct ButtonSurface: ViewModifier {
    let kind: CoreButtonKind
    let radius: CGFloat
    let fill: Color
    let hover: Bool
    /// Pressed under Reduce Motion: the fill darkens instead of the button shrinking.
    let darken: Bool

    func body(content: Content) -> some View {
        let shape = coreShape(radius)
        let hue: Color =
            kind == .danger ? GlassInk.red : kind == .prominent ? GlassInk.blue : GlassInk.slate
        content
            .background {
                switch kind {
                case .prominent, .danger: shape.fill(hue.opacity(hover ? 0.95 : 0.8))
                case .secondary:
                    shape.fill(hover ? GlassInk.adaptive(hue.opacity(0.28), day: .white.opacity(0.85)) : GlassInk.well)
                case .plain: shape.fill(hover ? GlassInk.wellHover : .clear)
                case .quietDanger: shape.fill(GlassInk.red.opacity(hover ? 0.22 : 0.1))
                }
            }
            .overlay {
                if kind == .quietDanger {
                    shape.strokeBorder(GlassInk.red.opacity(hover ? 0.85 : 0.55), lineWidth: 1)
                } else if kind != .plain {
                    shape.strokeBorder(
                        GlassInk.rim(0.3 + (hover ? 0.15 : 0)), lineWidth: 1)
                }
            }
            .overlay { shape.fill(.black.opacity(darken ? 0.18 : 0)).allowsHitTesting(false) }
            .animation(Motion.out(Motion.hover), value: darken)
    }
}

/// The press for glass tiles and icon buttons: scale 0.97 with the press curve; Reduce Motion darkens the tile instead.
/// Hover and fill stay with the tile itself.
struct CoreTilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TilePressBody(configuration: configuration) }
}

private struct TilePressBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduce ? 0.97 : 1)
            .overlay { Color.black.opacity(configuration.isPressed && reduce ? 0.18 : 0).allowsHitTesting(false) }
            .animation(Motion.press(Motion.press), value: configuration.isPressed)
    }
}

private struct KeycapKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    /// The key a CoreUI button shows on itself (set with `coreShortcut`).
    public var coreKeycap: String? {
        get { self[KeycapKey.self] }
        set { self[KeycapKey.self] = newValue }
    }
}

/// The shortcuts every modal uses: Esc for the way back, Return for the main action, ⌘1… for the rest, in order.
public enum ModalKey {
    case cancel
    case primary
    /// ⌘↩: the main action of a dialog that removes something, so Return alone never destroys.
    case command
    /// Esc without the keycap, for a way back that is not called Cancel or Close.
    case escape
    case number(Int)

    var label: String {
        switch self {
        case .cancel: "esc"
        case .primary: "↩"
        case .command: "⌘↩"
        case .escape: ""
        case .number(let n): "⌘\(n)"
        }
    }
}

extension View {
    /// Runs this button with `key` and shows the key on it.
    @ViewBuilder
    public func coreShortcut(_ key: ModalKey) -> some View {
        switch key {
        case .cancel: keyboardShortcut(.cancelAction).environment(\.coreKeycap, key.label)
        case .primary: keyboardShortcut(.defaultAction).environment(\.coreKeycap, key.label)
        case .command: keyboardShortcut(.return, modifiers: .command).environment(\.coreKeycap, key.label)
        case .escape: keyboardShortcut(.cancelAction).environment(\.coreKeycap, nil)
        case .number(let n):
            keyboardShortcut(KeyEquivalent(Character("\(n % 10)")), modifiers: .command)
                .environment(\.coreKeycap, key.label)
        }
    }
}

extension View {
    /// A choice tile's key: runs it with `key` (+ `modifiers`) and shows `label` in its top-right corner.
    public func coreTileKey(_ label: String, key: Character, modifiers: EventModifiers = .command) -> some View {
        keyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
            .overlay(alignment: .bottomTrailing) {
                Text(label).coreFont(size: 10, weight: .semibold, design: .rounded)
                    .foregroundStyle(GlassInk.adaptive(.white.opacity(0.85), day: GlassInk.dayInk.opacity(0.7)))
                    .padding(.horizontal, 5).frame(minHeight: 16)
                    .background(GlassInk.adaptive(.black.opacity(0.35), day: .white.opacity(0.85)), in: coreShape(4))
                    .padding(6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}
