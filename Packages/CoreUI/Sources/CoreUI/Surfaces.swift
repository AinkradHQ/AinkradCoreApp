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

    /// The content surface of dialogs, sheets and pop-ups: the one frame (see `coreFrame`).
    public func corePanel(radius: CGFloat = Radius.pane, padding: CGFloat = Space.s4, part: LookPart = .dialogs)
        -> some View
    {
        modifier(PanelModifier(radius: radius, padding: padding, part: part))
    }

    /// The neutral glass-card tint used by rows, banners and toasts. A tint, not a second material.
    public func coreCard(_ fill: Color, radius: CGFloat) -> some View {
        background(fill, in: coreShape(radius))
    }
}

private struct PanelModifier: ViewModifier {
    @Environment(\.coreSolidOnly) private var solid
    @Environment(\.corePalette) private var palette
    let radius: CGFloat
    let padding: CGFloat
    let part: LookPart
    /// Every panel, dialog, sheet and pop-up is the one frame (Ahmed, 2026-11-06): a clear glass rim holding the content
    /// on the Look's background (Settings, Appearance). Reduce Transparency keeps a solid panel.
    func body(content: Content) -> some View {
        if solid {
            content.padding(padding).background(palette.panelStrong, in: coreShape(radius))
        } else {
            content.padding(padding)
                .modifier(
                    FrameModifier(radius: radius, rim: Space.s2, active: false, part: part, fill: true, edge: 0.3))
        }
    }
}

private struct GlassModifier: ViewModifier {
    @Environment(\.corePalette) private var palette
    let radius: CGFloat
    let interactive: Bool
    let tinted: Bool
    let frosted: Bool
    @Environment(\.coreSolidOnly) private var solid
    /// Night glass is always dark; day glass is light.
    private var scheme: ColorScheme { palette.isDay ? .light : .dark }
    func body(content: Content) -> some View {
        let shape = coreShape(radius)
        if solid {
            // Reduce Transparency: a solid panel fill instead of Liquid Glass (glass is not documented to honour the setting).
            content.environment(\.colorScheme, scheme).background(palette.panelStrong, in: shape)
        } else if #available(macOS 26, iOS 26, *) {
            if tinted {
                // The one glass for cards, tiles and dialogs (the launcher's): a dark layer on Apple's frosted glass at
                // night; by day a white layer on light glass (Ahmed, 2026-11-12: day is light Liquid Glass).
                let glass = Glass.regular
                content.environment(\.colorScheme, scheme)
                    .background(palette.isDay ? Color.white.opacity(0.42) : Color.black.opacity(0.32), in: shape)
                    .glassEffect(interactive ? glass.interactive() : glass, in: shape)
            } else {
                let base = frosted ? Glass.regular : Glass.clear
                // Untinted is the widgets' glass: clear, so the sky shows through sharp; darkened a touch at night.
                let glass =
                    palette.isDay
                    ? base.tint(.white.opacity(0.3))
                    : base.tint(.black.opacity(0.32))
                content.environment(\.colorScheme, scheme)
                    .glassEffect(interactive ? glass.interactive() : glass, in: shape)
            }
        } else {
            content.background(shape.fill(.regularMaterial).environment(\.colorScheme, scheme))
                .background(palette.glassTint, in: shape)
        }
    }
}
