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
        // A small square in the state's colour and the word (Ahmed, 2026-11-15: no tinted fill). `symbol` stays for
        // callers and the gallery; the square carries the colour, the word carries the meaning.
        HStack(spacing: Space.s1 + 2) {
            coreShape(2).fill(colours.ink).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(label).coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(GlassInk.secondary)
        }
        .frame(minHeight: MacSize.chip)
        .fixedSize()
        .layoutPriority(2)  // titles shrink before badges
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("State: \(label)")
    }
}
