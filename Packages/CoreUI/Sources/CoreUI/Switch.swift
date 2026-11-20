import SwiftUI

/// A switch drawn as rounded rectangles (track and knob), never a pill or a circle. The knob slides on the UI ease; under
/// Reduce Motion it jumps. Space or a click flips it. On is the theme blue (a setting, not a status).
public struct CoreSwitch: View {
    @Environment(\.coreAccent) private var accent
    let title: String
    @Binding var isOn: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.coreForcedInteraction) private var forced
    @State private var hovering = false
    @State private var pressing = false
    @State private var flipping = false
    /// How far the knob has been slid while held, in points.
    @State private var drag: CGFloat = 0

    private static let trackW: CGFloat = 36
    private static let trackH: CGFloat = 20
    private static let knob: CGFloat = 14

    /// `title` is the word beside the switch and the VoiceOver label; pass "" when the row names it elsewhere.
    public init(_ title: String = "", isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    /// What a press does to the bound value.
    func flip() { isOn.toggle() }

    public var body: some View {
        HStack(spacing: Space.s2) {
            track
            if !title.isEmpty { Text(title).coreFont(size: MacTextSize.body, weight: .medium) }
        }
        .contentShape(Rectangle())
        // Press, hold and slide, as Apple's switch (Ahmed, 2026-11-15): the knob follows the pointer and lands on the
        // side it is let go on. A press that barely moves, however long, flips it on release.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { d in
                    pressing = true
                    drag = d.translation.width
                }
                .onEnded { d in
                    pressing = false
                    if abs(d.translation.width) < Self.slop {
                        flip()
                    } else {
                        let on = knobX > Self.mid
                        if on != isOn { isOn = on }
                    }
                    drag = 0
                },
            isEnabled: enabled
        )
        .focusable(enabled).focusEffectDisabled()
        .onKeyPress(.space) {
            flip()
            return .handled
        }
        .onChange(of: isOn) { flipping = CoreGlassKnob.flash { flipping = false } }
        .onHover { hovering = $0 }
        .coreDimWhenDisabled(enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.isEmpty ? "Switch" : title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction { if enabled { flip() } }
    }

    private static var pad: CGFloat { (trackH - knob) / 2 }
    private static var maxX: CGFloat { trackW - knob - pad }
    private static var mid: CGFloat { (pad + maxX) / 2 }
    /// Movement below this is a press, not a slide.
    private static let slop: CGFloat = 3
    /// Where the knob is drawn: its side, plus the drag while held, kept inside the track.
    private var knobX: CGFloat { min(max((isOn ? Self.maxX : Self.pad) + drag, Self.pad), Self.maxX) }
    private var sliding: Bool { pressing && abs(drag) >= Self.slop }

    private var track: some View {
        let lit = hovering || forced == .hover
        // While sliding, the track already shows the side the knob would land on.
        let on = sliding ? knobX > Self.mid : isOn
        return coreShape(Radius.chip)
            .fill(
                on
                    ? GlassInk.accent(accent).opacity(lit ? 0.9 : 1)
                    : GlassInk.adaptive(
                        .white.opacity(lit ? 0.32 : 0.24), day: GlassInk.dayInk.opacity(lit ? 0.22 : 0.16))
            )
            .overlay(alignment: .leading) {
                CoreGlassKnob(
                    width: Self.knob, height: Self.knob, radius: 4, active: pressing || flipping || forced == .pressed
                )
                .offset(x: knobX)
                // The knob follows the pointer with no easing; letting go glides it to its side.
                .transaction { if sliding { $0.animation = nil } }
            }
            .frame(width: Self.trackW, height: Self.trackH)
            .animation(reduce ? nil : Motion.out(Motion.ui), value: isOn)
            .animation(reduce ? nil : Motion.out(Motion.ui), value: drag == 0)
            .animation(Motion.out(Motion.hover), value: on)
            .animation(Motion.out(Motion.hover), value: lit)
    }
}

/// The knob of a switch or slider (Ahmed, 2026-11-15): our rounded rectangle with Apple's Liquid Glass response. At rest
/// a solid white knob; while pressed, dragged or flipping it swells into a clear glass lens over the track, then settles.
/// Reduce Motion: it stays the same size and only turns to glass.
struct CoreGlassKnob: View {
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        knob
            .frame(width: width, height: height)
            .scaleEffect(x: active && !reduce ? 1.4 : 1, y: active && !reduce ? 1.25 : 1)
            .animation(reduce ? Motion.out(Motion.hover) : .spring(response: 0.3, dampingFraction: 0.6), value: active)
    }

    @ViewBuilder private var knob: some View {
        let shape = coreShape(radius)
        if #available(macOS 26, iOS 26, *) {
            shape.fill(.white.opacity(active ? 0.1 : 1))
                .glassEffect(active ? .clear : .regular, in: shape)
                .shadow(color: GlassInk.shade(active ? 0.18 : 0.25), radius: active ? 4 : 1, y: 1)
        } else {
            shape.fill(.white.opacity(active ? 0.7 : 1)).shadow(color: GlassInk.shade(0.25), radius: 1, y: 1)
        }
    }

    /// Turns the lens on for a flip (a click or a key, not a drag) and back off after it: returns true, calls `off` later.
    @MainActor static func flash(_ off: @escaping @MainActor () -> Void) -> Bool {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            off()
        }
        return true
    }
}
