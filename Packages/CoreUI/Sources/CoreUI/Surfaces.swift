import SwiftUI

extension View {
    /// Clear glass control: system Liquid Glass on macOS 26 / iOS 26, regular material below.
    /// Glass is for controls floating over content. Never put it on a `corePanel` (no glass on glass).
    @ViewBuilder
    public func coreGlass(radius: CGFloat = Radius.control) -> some View {
        if #available(macOS 26, iOS 26, *) {
            // Always the deep (dark) glass: day is white text over deep blue glass, not pale glass.
            environment(\.colorScheme, .dark).glassEffect(.regular.interactive(), in: coreShape(radius))
        } else {
            background(coreShape(radius).fill(.regularMaterial).environment(\.colorScheme, .dark))
        }
    }

    /// Regular material panel: the content surface. Material only, never glass.
    public func corePanel(radius: CGFloat = Radius.pane, padding: CGFloat = Space.s4) -> some View {
        modifier(PanelModifier(radius: radius, padding: padding))
    }

    /// The neutral glass-card tint used by rows, banners and toasts. A tint, not a second material.
    func coreCard(_ fill: Color, radius: CGFloat) -> some View {
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
