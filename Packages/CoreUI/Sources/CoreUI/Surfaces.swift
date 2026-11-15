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
    @Environment(\.coreLook) private var look
    /// Night glass is always dark; day glass is light.
    private var scheme: ColorScheme { palette.isDay ? .light : .dark }
    func body(content: Content) -> some View {
        // No Liquid Glass (Ahmed, 2026-11-15): the content background, which goes solid under Reduce Transparency.
        content.environment(\.colorScheme, scheme).background(AppSurfaceFill(look, radius: radius))
    }
}
