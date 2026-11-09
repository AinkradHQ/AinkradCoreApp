import SwiftUI

/// A checkbox with a title and an optional plain-words detail beside it. Space toggles it; Tab reaches it.
/// States: off, on, focus (the system checkbox ring), disabled. The title can be monospaced for names like scopes.
public struct CoreCheckbox: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool
    let mono: Bool
    let spoken: String?
    @Environment(\.corePalette) private var palette

    /// `spoken` replaces the title as the VoiceOver label, for when the detail belongs in it.
    public init(
        _ title: String, detail: String? = nil, isOn: Binding<Bool>, mono: Bool = false, spoken: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
        self.mono = mono
        self.spoken = spoken
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).coreFont(size: MacTextSize.body, weight: .semibold, design: mono ? .monospaced : .default)
                if let detail {
                    Text(detail).coreFont(size: MacTextSize.meta).foregroundStyle(palette.text2)
                }
            }
        }
        .toggleStyle(.checkbox)
        .tint(palette.primary)
        .accessibilityLabel(spoken ?? title)
    }
}
