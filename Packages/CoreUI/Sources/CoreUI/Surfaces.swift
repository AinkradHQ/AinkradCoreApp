import SwiftUI

extension View {
    /// Clear glass control: system Liquid Glass on macOS 26 / iOS 26, regular material below, both tinted with the
    /// theme's deep-blue glass (the prototype's day theme is deep glass, not pale). Never put it on a `corePanel`.
    public func coreGlass(radius: CGFloat = Radius.control) -> some View {
        modifier(GlassModifier(radius: radius))
    }

    /// Regular material panel: the content surface. Material only, never glass.
    public func corePanel(radius: CGFloat = Radius.pane, padding: CGFloat = Space.s4) -> some View {
        modifier(PanelModifier(radius: radius, padding: padding))
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
                }
            }
    }
}

private struct GlassModifier: ViewModifier {
    @Environment(\.corePalette) private var palette
    let radius: CGFloat
    func body(content: Content) -> some View {
        let shape = coreShape(radius)
        if #available(macOS 26, iOS 26, *) {
            content.environment(\.colorScheme, .dark)
                .glassEffect(.regular.tint(palette.glassTint).interactive(), in: shape)
        } else {
            content.background(shape.fill(.regularMaterial).environment(\.colorScheme, .dark))
                .background(palette.glassTint, in: shape)
        }
    }
}
