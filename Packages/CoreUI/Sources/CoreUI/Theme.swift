import SwiftUI

/// Interaction states a component can be shown in. Real input drives them; the gallery forces them.
public enum CoreInteraction: Sendable, Hashable { case hover, pressed, focused }

/// Colour roles for the current theme. Night and day come from `Themes`; roles the night block does not define
/// are derived here from the same tokens, exactly as `tokens.css` does (u-dim 8%/14%, glass card = row tint).
public struct Palette: Sendable {
    public let isDay: Bool
    private let theme: ThemeColors
    /// System Increase Contrast is on: edges and secondary ink go stronger (set by `coreTheme()`).
    public var increased = false

    public static let night = Palette(isDay: false, theme: Themes.night)
    public static let day = Palette(isDay: true, theme: Themes.dayLight)

    private func pick(_ key: String, fallback: Color) -> Color { theme.roles[key] ?? fallback }

    public var text: Color { theme["text"] }
    public var text2: Color { increased ? theme["text"] : theme["text2"] }
    /// A copy of this palette with the system Increase Contrast setting applied.
    public func contrast(_ level: ColorSchemeContrast) -> Palette {
        var copy = self
        copy.increased = level == .increased
        return copy
    }
    public var primary: Color { theme["primary"] }
    public var disabled: Color { theme["disabled"] }
    public var btnPrimary: Color { theme["btnPrimary"] }
    public var btnPrimaryHover: Color { theme["btnPrimaryHover"] }
    public var btnPrimaryPress: Color { theme["btnPrimaryPress"] }
    public var btnInk: Color { theme["btnInk"] }
    /// Selection, hover and dim fills are the launcher's white glass on every screen (Ahmed, 2026-11-05: one style).
    /// Day: the mockups' lit white row with dark ink.
    public var navActive: Color { isDay ? .white.opacity(0.8) : .white.opacity(0.18) }
    public var navActiveEdge: Color { isDay ? .white.opacity(0.9) : .white.opacity(0.3) }
    public var navActiveInk: Color { isDay ? theme["text"] : .white }
    public var rowHover: Color { isDay ? .white.opacity(0.5) : .white.opacity(0.1) }
    /// Neutral edges: white 0.30 or more at night; Increase Contrast goes to 0.55 (day: a dark hairline instead).
    public var edge: Color {
        isDay
            ? (increased ? GlassInk.dayInk.opacity(0.35) : .white.opacity(0.7))
            : increased ? .white.opacity(0.55) : theme["edge"]
    }
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
    public var glassCard: Color { isDay ? .white.opacity(0.55) : .white.opacity(0.08) }
    public var glassCardEdge: Color {
        isDay
            ? (increased ? GlassInk.dayInk.opacity(0.35) : .white.opacity(0.7)) : .white.opacity(increased ? 0.55 : 0.3)
    }
    public var panelStrong: Color { pick("panelGlassStrong", fallback: theme["mRead"]) }
    /// Deep-blue glass tint (day: panelGlass; night: the pane glass).
    public var glassTint: Color { pick("panelGlass", fallback: theme["mGlass"]) }
    public var uDim: Color { isDay ? .white.opacity(0.6) : .white.opacity(0.1) }
    public var uDimHover: Color { isDay ? .white.opacity(0.8) : .white.opacity(0.16) }

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

private struct SolidOnlyKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Reduce Transparency, as `coreTheme()` read it (or forced in a Debug build): glass becomes a solid surface.
    public var coreSolidOnly: Bool {
        get { self[SolidOnlyKey.self] }
        set { self[SolidOnlyKey.self] = newValue }
    }
}

private struct CoreThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.layoutDirection) private var layoutDirection
    #if DEBUG
    /// `CORE_FORCE_A11Y=transparency,contrast,rtl` pretends the Mac asks for Reduce Transparency and/or Increase Contrast and
    /// lays everything out right to left, so those paths can be looked at without changing System Settings.
    private static let forced = ProcessInfo.processInfo.environment["CORE_FORCE_A11Y"] ?? ""
    private var effectiveContrast: ColorSchemeContrast { Self.forced.contains("contrast") ? .increased : contrast }
    private var solidOnly: Bool { reduceTransparency || Self.forced.contains("transparency") }
    #else
    private var effectiveContrast: ColorSchemeContrast { contrast }
    private var solidOnly: Bool { reduceTransparency }
    #endif
    func body(content: Content) -> some View {
        let palette = (scheme == .dark ? Palette.night : Palette.day).contrast(effectiveContrast)
        content
            .environment(\.corePalette, palette)
            .environment(\.coreSolidOnly, solidOnly)
            #if DEBUG
        .environment(\.layoutDirection, Self.forced.contains("rtl") ? .rightToLeft : layoutDirection)
            #endif
            .foregroundStyle(palette.text)
            // System controls (switches, sliders, pickers, glass buttons) follow the app's blue, never the Mac's accent colour.
            .tint(palette.btnPrimary)
            .font(.system(size: MacTextSize.scaled(MacTextSize.body, by: TextSizePrefs.shared.scale)))
            // No focus rings anywhere (Ahmed, 2026-11-05): the system ring and our own both stay off. Keyboard focus
            // still moves; the focused control is the one that answers Space and Return.
            .focusEffectDisabled()
    }
}

extension View {
    /// Apply once near the root: night when the system is dark, day ("Light" to people) otherwise.
    public func coreTheme() -> some View { modifier(CoreThemeModifier()) }

    /// Motion with the Reduce Motion fallback: the animation becomes a 180 ms fade, never nil (motion spec). Movement the
    /// caller draws is dropped with `coreMove`.
    public func coreAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(CoreAnimationModifier(animation: animation, value: value))
    }

    /// The disabled look every control shares.
    public func coreDimWhenDisabled(_ enabled: Bool) -> some View { modifier(DimWhenDisabled(enabled: enabled)) }

    /// Keyboard focus without a ring (Ahmed, 2026-11-05; D6): the lifted fill and a 1 pt lift.
    /// Reduce Motion: no lift. One implementation, so every control that calls it answers focus the same way.
    public func coreFocusRing(_ show: Bool, radius: CGFloat, palette: Palette) -> some View {
        modifier(CoreFocusLook(show: show, radius: radius))
    }
}

/// Disabled dims the control, not its helper text. Day dims less (0.6) so the label stays legible over the glass.
private struct DimWhenDisabled: ViewModifier {
    let enabled: Bool
    @Environment(\.corePalette) private var palette
    func body(content: Content) -> some View { content.opacity(enabled ? 1 : palette.isDay ? 0.6 : 0.45) }
}

private struct CoreFocusLook: ViewModifier {
    let show: Bool
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduce
    func body(content: Content) -> some View {
        content
            .overlay {
                coreShape(radius).fill(.white.opacity(show ? 0.14 : 0)).allowsHitTesting(false)
            }
            .offset(y: show && !reduce ? -1 : 0)
            .animation(Motion.out(Motion.hover), value: show)
    }
}

extension Motion {
    /// Interruptible, no overshoot: for values that can change again before the last change has settled.
    public static func smooth(_ d: Double) -> Animation { .smooth(duration: d) }
    /// Shared modal entrance (opacity + 0.97 scale on the UI ease) and its 150 ms exit.
    public static func modal(_ shown: Bool, _ reduce: Bool) -> Animation {
        calm(shown ? out(ui) : exit(0.15), reduce)
    }
    /// Reduce Motion keeps a fade: the 180 ms hover ease replaces `animation`, so a change is never an instant cut.
    public static func calm(_ animation: Animation, _ reduce: Bool) -> Animation {
        reduce ? out(hover) : animation
    }
}

private struct CoreAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    let animation: Animation
    let value: V
    func body(content: Content) -> some View {
        content.animation(Motion.calm(animation, reduce), value: value)
    }
}

/// Reduce Motion: translate and scale are dropped (opacity stays). One place so every component agrees.
public func coreMove(_ reduce: Bool, _ distance: CGFloat) -> CGFloat { reduce ? 0 : distance }

/// A rounded rectangle at a token radius. The only shape the system draws.
public func coreShape(_ radius: CGFloat) -> RoundedRectangle {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
}

extension Themes {
    /// Day for the Mac: light Liquid Glass with dark ink (Ahmed, 2026-11-12, the approved day mockups: `tf.css`
    /// [data-theme=day] and `ds.css` light). Hand-written over the generated deep-blue `dayMac`, which it replaces.
    /// Status inks are darker than the mockups' fills so they read 4.5:1 on the pale glass.
    public static let dayLight = ThemeColors(
        dayMac.roles.merging(
            [
                "text": GlassInk.dayInk,
                "text2": GlassInk.dayInk.opacity(0.68),
                "disabled": GlassInk.dayInk.opacity(0.4),
                "primary": Color(red: 0.102, green: 0.361, blue: 0.776),
                "primarySoft": Color(red: 0.122, green: 0.42, blue: 0.878),
                "accent": Color(red: 0.122, green: 0.42, blue: 0.878),
                "icon": Color(red: 0.122, green: 0.42, blue: 0.878),
                "success": Color(red: 0.09, green: 0.5, blue: 0.23),
                "warning": Color(red: 0.64, green: 0.345, blue: 0),
                "error": Color(red: 0.784, green: 0.149, blue: 0.11),
                "bg": Color(red: 0.98, green: 0.984, blue: 1),
                "surface": .white,
                "border": GlassInk.dayInk.opacity(0.1),
                "edge": .white.opacity(0.7),
                "edgeSoft": .white.opacity(0.55),
                "hair": GlassInk.dayInk.opacity(0.07),
                "track": GlassInk.dayInk.opacity(0.1),
                "mClear": .white.opacity(0.04),
                "mGlass": .white.opacity(0.46),
                "mElev": .white.opacity(0.58),
                "mRead": .white.opacity(0.86),
                "mRow": .white.opacity(0.55),
                "mRowHover": .white.opacity(0.75),
                "panelGlass": .white.opacity(0.46),
                "panelGlassStrong": Color(red: 0.97, green: 0.98, blue: 1, opacity: 0.94),
                "btnPrimary": Color(red: 0.122, green: 0.42, blue: 0.878),
                "btnPrimaryHover": Color(red: 0.102, green: 0.388, blue: 0.831),
                "btnPrimaryPress": Color(red: 0.102, green: 0.361, blue: 0.776),
                "btnInk": .white,
                "chipRun": Color(red: 0.082, green: 0.502, blue: 0.239),
                "chipRunBg": Color(red: 0.188, green: 0.82, blue: 0.345, opacity: 0.16),
                "chipDone": Color(red: 0.102, green: 0.361, blue: 0.776),
                "chipDoneBg": Color(red: 0.039, green: 0.518, blue: 1, opacity: 0.12),
                "chipFail": Color(red: 0.784, green: 0.149, blue: 0.11),
                "chipFailBg": Color(red: 1, green: 0.231, blue: 0.188, opacity: 0.12),
                "chipQueue": Color(red: 0.278, green: 0.333, blue: 0.412),
                "chipQueueBg": Color(red: 0.392, green: 0.455, blue: 0.545, opacity: 0.14),
                "chipWarn": Color(red: 0.64, green: 0.345, blue: 0),
                "chipWarnBg": Color(red: 1, green: 0.624, blue: 0.039, opacity: 0.18),
                "ink3": GlassInk.dayInk.opacity(0.45),
                "errInk": Color(red: 0.784, green: 0.149, blue: 0.11),
                "uDim": .white.opacity(0.6),
                "uDimHover": .white.opacity(0.8),
                "navActive": .white.opacity(0.8),
                "navActiveEdge": .white.opacity(0.9),
                "navActiveInk": GlassInk.dayInk,
                "skyVeil": Color(red: 0.91, green: 0.945, blue: 0.984, opacity: 0.45),
                "focusRing": GlassInk.dayInk.opacity(0.35),
            ], uniquingKeysWith: { _, new in new }))
}
