import SwiftUI

/// A switch drawn as rounded rectangles (track and knob), never a pill or a circle. The knob slides on the UI ease; under
/// Reduce Motion it jumps. Space or a click flips it. On is the theme blue (a setting, not a status).
public struct CoreSwitch: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.coreForcedInteraction) private var forced
    @State private var hovering = false

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
        Button(action: flip) {
            HStack(spacing: Space.s2) {
                track
                if !title.isEmpty { Text(title).coreFont(size: MacTextSize.body, weight: .medium) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CoreQuietPressStyle(radius: Radius.chip, scale: 0.97))
        .onHover { hovering = $0 }
        .coreDimWhenDisabled(enabled)
        .accessibilityLabel(title.isEmpty ? "Switch" : title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }

    private var track: some View {
        let lit = hovering || forced == .hover
        let pad = (Self.trackH - Self.knob) / 2
        return coreShape(Radius.chip)
            .fill(isOn ? GlassInk.blue.opacity(lit ? 0.95 : 0.8) : Color.white.opacity(lit ? 0.32 : 0.24))
            .overlay { coreShape(Radius.chip).strokeBorder(.white.opacity(isOn ? 0.3 : 0.2), lineWidth: 1) }
            .overlay(alignment: .leading) {
                coreShape(4).fill(.white).frame(width: Self.knob, height: Self.knob)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .offset(x: isOn ? Self.trackW - Self.knob - pad : pad)
            }
            .frame(width: Self.trackW, height: Self.trackH)
            .animation(reduce ? nil : Motion.out(Motion.ui), value: isOn)
            .animation(Motion.out(Motion.hover), value: lit)
    }
}
