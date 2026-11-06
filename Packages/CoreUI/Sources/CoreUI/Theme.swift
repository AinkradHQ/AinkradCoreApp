import SwiftUI

/// Interaction states a component can be shown in. Real input drives them; the gallery forces them.
public enum CoreInteraction: Sendable, Hashable { case hover, pressed, focused }

/// Colour roles for the current theme. Night and day come from `Themes`; roles the night block does not define
/// are derived here from the same tokens, exactly as `tokens.css` does (u-dim 8%/14%, glass card = row tint).
public struct Palette: Sendable {
    public let isDay: Bool
    private let theme: ThemeColors

    public static let night = Palette(isDay: false, theme: Themes.night)
    public static let day = Palette(isDay: true, theme: Themes.dayMac)

    private func pick(_ key: String, fallback: Color) -> Color { theme.roles[key] ?? fallback }

    public var text: Color { theme["text"] }
    public var text2: Color { theme["text2"] }
    public var primary: Color { theme["primary"] }
    public var disabled: Color { theme["disabled"] }
    public var btnPrimary: Color { theme["btnPrimary"] }
    public var btnPrimaryHover: Color { theme["btnPrimaryHover"] }
    public var btnPrimaryPress: Color { theme["btnPrimaryPress"] }
    public var btnInk: Color { theme["btnInk"] }
    /// Selection, hover and dim fills are the launcher's white glass on every screen (Ahmed, 2026-11-05: one style).
    public var navActive: Color { Self.navActiveFill }
    public var navActiveEdge: Color { Self.navActiveStroke }
    public var navActiveInk: Color { .white }
    public var rowHover: Color { Self.rowHoverFill }
    public var edge: Color { theme["edge"] }
    public var track: Color { theme["track"] }
    public var success: Color { theme["success"] }
    public var warning: Color { theme["warning"] }
    public var error: Color { theme["error"] }
    public var bg: Color { theme["bg"] }
    public var surface: Color { theme["surface"] }

    /// The one focus ring: blue at night, white over the deep day glass.
    /// No blue focus rings anywhere (Ahmed, 2026-11-05): views that still outline the focused control get the quiet edge.
    public var focusRing: Color { glassCardEdge }
    /// Neutral glass card tint (rows, banners, toasts): never a blue fill on a large surface.
    /// Cards sit on Liquid Glass everywhere now (Ahmed, 2026-11-05: "everything shall be liquid glass"), so a card is a
    /// soft white well with a light edge, not a dark slab, in both themes.
    public var glassCard: Color { Self.glassCardFill }
    public var glassCardEdge: Color { Self.glassCardStroke }
    public var panelStrong: Color { pick("panelGlassStrong", fallback: theme["mRead"]) }
    /// Deep-blue glass tint (day: panelGlass; night: the pane glass).
    public var glassTint: Color { pick("panelGlass", fallback: theme["mGlass"]) }
    public var uDim: Color { Self.uDimFill }
    public var uDimHover: Color { Self.uDimHoverFill }

    // TODO tokens.json: hard-coded white overrides of theme roles, named here until tokens.json carries them.
    private static let navActiveFill = Color.white.opacity(0.18)
    private static let navActiveStroke = Color.white.opacity(0.3)
    private static let rowHoverFill = Color.white.opacity(0.1)
    private static let glassCardFill = Color.white.opacity(0.08)
    private static let glassCardStroke = Color.white.opacity(0.14)
    private static let uDimFill = Color.white.opacity(0.1)
    private static let uDimHoverFill = Color.white.opacity(0.16)

    public func tone(_ tone: Tone) -> (ink: Color, fill: Color) {
        switch tone {
        case .run: (theme["chipRun"], theme["chipRunBg"])
        case .done: (theme["chipDone"], theme["chipDoneBg"])
        case .fail: (theme["chipFail"], theme["chipFailBg"])
        case .queue: (theme["chipQueue"], theme["chipQueueBg"])
        case .warn:
            (pick("chipWarn", fallback: theme["warning"]), pick("chipWarnBg", fallback: theme["warning"].opacity(0.18)))
        }
    }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.night }
private struct ForcedKey: EnvironmentKey { static let defaultValue: CoreInteraction? = nil }

extension EnvironmentValues {
    /// Set by `coreTheme()` from the colour scheme.
    public var corePalette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
    /// Gallery and previews only: pins a component to hover, pressed or focused.
    public var coreForcedInteraction: CoreInteraction? {
        get { self[ForcedKey.self] }
        set { self[ForcedKey.self] = newValue }
    }
}

private struct CoreThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .environment(\.corePalette, scheme == .dark ? .night : .day)
            .foregroundStyle((scheme == .dark ? Palette.night : Palette.day).text)
            // System controls (switches, sliders, pickers, glass buttons) follow the app's blue, never the Mac's accent colour.
            .tint((scheme == .dark ? Palette.night : Palette.day).btnPrimary)
            .font(.system(size: MacTextSize.body))
            // No focus rings anywhere (Ahmed, 2026-11-05): the system ring and our own both stay off. Keyboard focus
            // still moves; the focused control is the one that answers Space and Return.
            .focusEffectDisabled()
    }
}

extension View {
    /// Apply once near the root: night when the system is dark, day ("Light" to people) otherwise.
    public func coreTheme() -> some View { modifier(CoreThemeModifier()) }

    /// Motion with the Reduce Motion fallback: movement is dropped, fades and colour changes stay (motion spec).
    public func coreAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(CoreAnimationModifier(animation: animation, value: value))
    }

    /// The disabled look every control shares.
    public func coreDimWhenDisabled(_ enabled: Bool) -> some View { opacity(enabled ? 1 : 0.55) }

    /// Focus ring: 2 pt, offset 2, in `focusRing`. Shape is always a rounded rectangle.
    /// Draws nothing in the app: focus rings are off everywhere (Ahmed, 2026-11-05). Kept so callers need no change.
    public func coreFocusRing(_ show: Bool, radius: CGFloat, palette: Palette) -> some View { self }
}

private struct CoreAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    let animation: Animation
    let value: V
    func body(content: Content) -> some View {
        content.animation(reduce ? Motion.out(Motion.hover) : animation, value: value)
    }
}

/// Reduce Motion: translate and scale are dropped (opacity stays). One place so every component agrees.
public func coreMove(_ reduce: Bool, _ distance: CGFloat) -> CGFloat { reduce ? 0 : distance }

/// A rounded rectangle at a token radius. The only shape the system draws.
public func coreShape(_ radius: CGFloat) -> RoundedRectangle {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
}
