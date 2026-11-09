import SwiftUI

/// State badge: symbol plus a word, always. Colour is the third cue, never the only one.
public struct StateBadge: View {
    let label: String
    let tone: Tone
    let symbol: String
    @Environment(\.corePalette) private var palette

    public init(_ label: String, tone: Tone, symbol: String) {
        self.label = label
        self.tone = tone
        self.symbol = symbol
    }

    public init<S: CoreState>(_ state: S) { self.init(state.label, tone: state.tone, symbol: state.symbol) }

    public var body: some View {
        let colours = palette.tone(tone)
        HStack(spacing: Space.s1) {
            Image(systemName: symbol).font(.system(size: MacTextSize.meta - 1)).accessibilityHidden(true)
            Text(label).font(.system(size: MacTextSize.meta, weight: .medium))
        }
        .foregroundStyle(colours.ink)
        .padding(.horizontal, Space.s2)
        .frame(minHeight: MacSize.chip)
        .background(colours.fill, in: coreShape(Radius.chip))
        .fixedSize()
        .layoutPriority(2)  // titles shrink before badges
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("State: \(label)")
    }
}
