import SwiftUI

/// The switch (Ahmed, 2026-11-15): Apple's own, for its Liquid Glass knob, tinted with the accent. The word beside it is
/// ours. Space or a click flips it.
public struct CoreSwitch: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var enabled

    /// `title` is the word beside the switch and the VoiceOver label; pass "" when the row names it elsewhere.
    public init(_ title: String = "", isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    /// What a press does to the bound value.
    func flip() { isOn.toggle() }

    public var body: some View {
        HStack(spacing: Space.s2) {
            Toggle(title.isEmpty ? "Switch" : title, isOn: $isOn)
                .toggleStyle(.switch).labelsHidden().tint(GlassInk.blue)
            if !title.isEmpty {
                Text(title).coreFont(size: MacTextSize.body, weight: .medium)
                    .onTapGesture { if enabled { flip() } }
                    .accessibilityHidden(true)
            }
        }
        .coreDimWhenDisabled(enabled)
    }
}
