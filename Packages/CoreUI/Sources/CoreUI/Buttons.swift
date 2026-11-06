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
    @State private var hovering = false

    private var pressed: Bool { configuration.isPressed || forced == .pressed }
    private var hover: Bool { hovering || forced == .hover }

    var body: some View {
        let ink: Color = .white
        HStack(spacing: Space.s2) {
            ZStack {
                configuration.label.opacity(busy ? 0 : 1)
                if busy { ProgressView().controlSize(.small).tint(ink) }
            }
            // The key that runs this button, shown on it (Ahmed, 2026-11-05: every action keyboard driven).
            if let keycap {
                Text(keycap).font(.system(size: 10, weight: .medium, design: .rounded))
                    .padding(.horizontal, 5).frame(minHeight: 16)
                    .background(.white.opacity(0.16), in: coreShape(5))
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: size.text, weight: .semibold))
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

/// Every CoreUI button is the app-header tile (Ahmed, 2026-11-05: "apply this style of buttons everywhere"): prominent is
/// a soft blue tile, danger a soft red one, secondary a dark glass well; a light edge, a glow and a small lift on hover.
/// Plain buttons stay quiet until hovered.
private struct ButtonSurface: ViewModifier {
    let kind: CoreButtonKind
    let radius: CGFloat
    let fill: Color
    let hover: Bool

    func body(content: Content) -> some View {
        let shape = coreShape(radius)
        let hue: Color =
            kind == .danger ? GlassInk.red : kind == .prominent ? GlassInk.blue : GlassInk.slate
        content
            .background {
                switch kind {
                case .prominent, .danger: shape.fill(hue.opacity(hover ? 0.95 : 0.8))
                case .secondary: shape.fill(hover ? hue.opacity(0.28) : GlassInk.well)
                case .plain: shape.fill(hover ? GlassInk.wellHover : .clear)
                }
            }
            .overlay {
                if kind != .plain {
                    shape.strokeBorder(.white.opacity(kind == .secondary ? 0.15 : 0.3), lineWidth: 1)
                }
            }
            .shadow(color: (kind == .plain ? Color.clear : hue).opacity(hover ? 0.45 : 0), radius: 10)
            .scaleEffect(hover && kind != .plain ? 1.04 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: hover)
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
    case number(Int)

    var label: String {
        switch self {
        case .cancel: "esc"
        case .primary: "↩"
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
            .overlay(alignment: .topTrailing) {
                Text(label).font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 5).frame(minHeight: 16)
                    .background(.black.opacity(0.35), in: coreShape(4))
                    .padding(6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}
