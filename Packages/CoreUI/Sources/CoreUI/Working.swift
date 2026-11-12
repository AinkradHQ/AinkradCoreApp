import SwiftUI

/// Thinking and running tools: a short blue bar whose segment slides along its track, never a spinner or bouncing dots.
/// Under Reduce Motion the segment rests in the middle. Decorative: put the words ("Thinking") beside it.
public struct CoreWorkingBar: View {
    let width: CGFloat
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    public init(width: CGFloat = Space.s8 + Space.s6) { self.width = width }

    public var body: some View {
        let seg = width * 0.4
        TimelineView(.animation(paused: reduce)) { ctx in
            // A 1.2 s sweep eased at both ends: calm travel, not a tick. No pointer input anywhere.
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2) / 1.2
            let p = reduce ? 0.5 : (1 - cos(t * 2 * .pi)) / 2
            coreShape(Space.s1 / 2).fill(palette.track)
                .overlay(alignment: .leading) {
                    coreShape(Space.s1 / 2).fill(GlassInk.blue).frame(width: seg).offset(x: (width - seg) * p)
                }
        }
        .frame(width: width, height: Space.s1)
        .clipShape(coreShape(Space.s1 / 2))
        .accessibilityHidden(true)
    }
}

/// The press for card and row buttons: a slight scale on the press curve; Reduce Motion darkens the card instead.
/// `hoverFill` adds the quiet row hover (the tile itself keeps its own well when false).
public struct CoreQuietPressStyle: ButtonStyle {
    let radius: CGFloat
    let scale: CGFloat
    let hoverFill: Bool
    public init(radius: CGFloat = Radius.cardMac, scale: CGFloat = 0.98, hoverFill: Bool = false) {
        self.radius = radius
        self.scale = scale
        self.hoverFill = hoverFill
    }
    public func makeBody(configuration: Configuration) -> some View {
        QuietPressBody(configuration: configuration, radius: radius, scale: scale, hoverFill: hoverFill)
    }
}

extension ButtonStyle where Self == CoreQuietPressStyle {
    public static var coreQuietPress: CoreQuietPressStyle { CoreQuietPressStyle() }
}

private struct QuietPressBody: View {
    let configuration: ButtonStyleConfiguration
    let radius: CGFloat
    let scale: CGFloat
    let hoverFill: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.coreForcedInteraction) private var forced
    @State private var hovering = false
    private var pressed: Bool { configuration.isPressed || forced == .pressed }
    var body: some View {
        configuration.label
            .background { coreShape(radius).fill(hoverFill && (hovering || forced == .hover) ? GlassInk.well : .clear) }
            .overlay { coreShape(radius).fill(.black.opacity(pressed && reduce ? 0.18 : 0)).allowsHitTesting(false) }
            .scaleEffect(pressed && !reduce ? scale : 1)
            .animation(Motion.press(Motion.press), value: pressed)
            .animation(Motion.out(Motion.hover), value: hovering)
            .onHover { hovering = $0 }
    }
}
