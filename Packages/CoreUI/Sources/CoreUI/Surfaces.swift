import SwiftUI

extension View {
    /// Clear glass control: system Liquid Glass on macOS 26 / iOS 26, regular material below, both tinted with the
    /// theme's deep-blue glass (the prototype's day theme is deep glass, not pale). Never put it on a `corePanel`.
    /// `tinted: false` is the widgets' clear glass: the sky shows through sharp. `frosted: true` keeps that look but blurs
    /// what is behind (inputs such as the launcher).
    public func coreGlass(
        radius: CGFloat = Radius.control, interactive: Bool = true, tinted: Bool = true, frosted: Bool = false
    ) -> some View {
        modifier(GlassModifier(radius: radius, interactive: interactive, tinted: tinted, frosted: frosted))
    }

    /// The content surface: the shared overlay glass (see PanelModifier).
    public func corePanel(radius: CGFloat = Radius.pane, padding: CGFloat = Space.s4) -> some View {
        modifier(PanelModifier(radius: radius, padding: padding))
    }

    /// An input's well: clear Liquid Glass on macOS 26 / iOS 26 (the field reads as cut into the glass card), the
    /// glass-card tint below.
    @ViewBuilder
    public func coreGlassField(radius: CGFloat = Radius.control, fallback: Color) -> some View {
        if #available(macOS 26, iOS 26, *) {
            glassEffect(.clear.interactive(), in: coreShape(radius))
        } else {
            background(fallback, in: coreShape(radius))
        }
    }

    /// The neutral glass-card tint used by rows, banners and toasts. A tint, not a second material.
    public func coreCard(_ fill: Color, radius: CGFloat) -> some View {
        background(fill, in: coreShape(radius))
    }
}

private struct PanelModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var solid
    @Environment(\.corePalette) private var palette
    let radius: CGFloat
    let padding: CGFloat
    /// Every panel, dialog and sheet is the launcher's glass (Ahmed, 2026-11-05: consistent, everything Liquid Glass): a
    /// dark layer on Apple's glass, frosted at night, clear by day, white ink. Reduce Transparency keeps a solid panel.
    func body(content: Content) -> some View {
        let shape = coreShape(radius)
        if solid {
            content.padding(padding).background(palette.panelStrong, in: shape)
        } else {
            content.padding(padding)
                .foregroundStyle(GlassInk.primary)
                .background(Color.black.opacity(palette.isDay ? 0.4 : 0.32), in: shape)
                .coreGlass(radius: radius, interactive: false, tinted: false, frosted: !palette.isDay)
        }
    }
}

private struct GlassModifier: ViewModifier {
    @Environment(\.corePalette) private var palette
    let radius: CGFloat
    let interactive: Bool
    let tinted: Bool
    let frosted: Bool
    func body(content: Content) -> some View {
        let shape = coreShape(radius)
        if #available(macOS 26, iOS 26, *) {
            let base = frosted ? Glass.regular : Glass.clear
            // Untinted is Apple's widget glass: clear, so the sky shows through sharp and only the edges bend the light
            // (Ahmed's macOS widget screenshots, 2026-11-05). Night darkens it a touch, like macOS does on a dark desktop.
            let glass =
                tinted
                ? Glass.regular.tint(palette.glassTint)
                : palette.isDay
                    ? base.tint(Color(red: 0.08, green: 0.22, blue: 0.5).opacity(0.35))
                    : base.tint(.black.opacity(0.32))
            content.environment(\.colorScheme, .dark)
                .glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            content.background(shape.fill(.regularMaterial).environment(\.colorScheme, .dark))
                .background(palette.glassTint, in: shape)
        }
    }
}
