import SwiftUI

extension View {
    /// Clear glass control: system Liquid Glass on macOS 26 / iOS 26, regular material below, both tinted with the
    /// theme's deep-blue glass (the prototype's day theme is deep glass, not pale). Never put it on a `corePanel`.
    /// `tinted: false` is Apple's own regular glass with only a breath of the theme blue: the sky shows through (widgets).
    public func coreGlass(radius: CGFloat = Radius.control, interactive: Bool = true, tinted: Bool = true) -> some View
    {
        modifier(GlassModifier(radius: radius, interactive: interactive, tinted: tinted))
    }

    /// Regular material panel: the content surface. Material only, never glass.
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
    func body(content: Content) -> some View {
        let shape = coreShape(radius)
        content
            .padding(padding)
            .background {
                if solid {
                    shape.fill(palette.panelStrong)
                } else {
                    shape.fill(.regularMaterial).environment(\.colorScheme, .dark)
                    // Day is deep blue glass (the prototype's `panelGlass`), not a grey material.
                    if palette.isDay { shape.fill(palette.glassTint.opacity(0.5)) }
                }
            }
    }
}

private struct GlassModifier: ViewModifier {
    @Environment(\.corePalette) private var palette
    let radius: CGFloat
    let interactive: Bool
    let tinted: Bool
    func body(content: Content) -> some View {
        let shape = coreShape(radius)
        if #available(macOS 26, iOS 26, *) {
            // Untinted keeps a breath of blue at night; the day sky is bright, so day glass stays deep blue (the
            // prototype's day theme) or white text on it washes out.
            let glass = Glass.regular.tint(
                tinted || palette.isDay ? palette.glassTint : palette.glassTint.opacity(0.25))
            content.environment(\.colorScheme, .dark)
                .glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            content.background(shape.fill(.regularMaterial).environment(\.colorScheme, .dark))
                .background(palette.glassTint, in: shape)
        }
    }
}
