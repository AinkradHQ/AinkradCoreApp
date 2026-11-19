import SwiftUI

/// A checkbox with a title and an optional plain-words detail beside it. Space toggles it; Tab reaches it.
/// An optional `icon` (SF Symbol) sits between the box and the text. States: off, on, focus (the system checkbox ring), disabled. The title can be monospaced for names like scopes.
public struct CoreCheckbox: View {
    @Environment(\.coreAccent) private var accent
    let title: String
    let detail: String?
    @Binding var isOn: Bool
    let mono: Bool
    let spoken: String?
    let icon: String?
    @Environment(\.corePalette) private var palette

    /// `spoken` replaces the title as the VoiceOver label, for when the detail belongs in it.
    public init(
        _ title: String, detail: String? = nil, isOn: Binding<Bool>, mono: Bool = false, spoken: String? = nil,
        icon: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
        self.mono = mono
        self.spoken = spoken
        self.icon = icon
    }

    public var body: some View {
        // Our own box (Ahmed, 2026-11-15): the same rounded square as the scope tiles, the accent when on, in every layout
        // direction (the system checkbox lost its tick when right to left was forced).
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: Space.s2) {
                coreShape(4)
                    .fill(isOn ? GlassInk.accent(accent) : GlassInk.well)
                    .overlay { if !isOn { coreShape(4).strokeBorder(GlassInk.track, lineWidth: 1.5) } }
                    .overlay {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .opacity(isOn ? 1 : 0)
                    }
                    .frame(width: 16, height: 16)
                    .animation(Motion.out(Motion.hover), value: isOn)
                if let icon { IconTile(icon, hue: GlassInk.blue, size: 28) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).coreFont(
                        size: MacTextSize.body, weight: .semibold, design: mono ? .monospaced : .default)
                    if let detail {
                        Text(detail).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken ?? title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
