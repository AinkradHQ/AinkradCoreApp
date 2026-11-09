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
    func body(content: Content) -> some View {
        let shape = coreShape(radius)
        if solid {
            // Reduce Transparency: a solid panel fill instead of Liquid Glass (glass is not documented to honour the setting).
            content.environment(\.colorScheme, .dark).background(palette.panelStrong, in: shape)
        } else if #available(macOS 26, iOS 26, *) {
            if tinted {
                // The one glass for cards, tiles and dialogs (the launcher's): a dark layer on Apple's glass, clear by
                // day and frosted at night. The older deep-blue tint is gone (Ahmed, 2026-11-05: latest style everywhere).
                let glass = palette.isDay ? Glass.clear : Glass.regular
                content.environment(\.colorScheme, .dark)
                    .background(Color.black.opacity(palette.isDay ? 0.4 : 0.32), in: shape)
                    .glassEffect(interactive ? glass.interactive() : glass, in: shape)
            } else {
                let base = frosted ? Glass.regular : Glass.clear
                // Untinted is the widgets' glass: clear, so the sky shows through sharp; darkened a touch at night.
                let glass =
                    palette.isDay
                    ? base.tint(Color(red: 0.08, green: 0.22, blue: 0.5).opacity(0.35))
                    : base.tint(.black.opacity(0.32))
                content.environment(\.colorScheme, .dark)
                    .glassEffect(interactive ? glass.interactive() : glass, in: shape)
            }
        } else {
            content.background(shape.fill(.regularMaterial).environment(\.colorScheme, .dark))
                .background(palette.glassTint, in: shape)
        }
    }
}
