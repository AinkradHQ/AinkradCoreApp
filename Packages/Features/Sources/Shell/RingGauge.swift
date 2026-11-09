import CoreUI
import SwiftUI

/// The widget gauge: an SF Symbol, one short value and a progress bar on a faint track (rounded rectangles only; no rings,
/// Ahmed 2026-11-09). The bar fills from empty when it appears. The type keeps its old name; every widget already calls it.
struct RingGauge: View {
    let value: Double
    let symbol: String
    var tint: Color
    var caption: String?
    var sub: String?
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = 0.0

    var body: some View {
        VStack(spacing: Space.s2) {
            Spacer(minLength: 0)
            Image(systemName: symbol).coreFont(size: MacTextSize.large + 6, weight: .medium)
                .foregroundStyle(tint).coreBounce(shown > 0)
            if let caption {
                VStack(spacing: 0) {
                    Text(caption).coreFont(size: MacTextSize.headline + 2, weight: .semibold).monospacedDigit()
                        .foregroundStyle(WidgetInk.primary)
                        .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
                    if let sub {
                        Text(sub).coreFont(size: MacTextSize.meta, weight: .medium).foregroundStyle(
                            WidgetInk.secondary
                        )
                        .lineLimit(1)
                    }
                }
            }
            GeometryReader { g in
                coreShape(Radius.chip / 2).fill(WidgetInk.track)
                    .overlay(alignment: .leading) {
                        coreShape(Radius.chip / 2).fill(tint).frame(width: g.size.width * min(max(shown, 0), 1))
                    }
            }
            .frame(height: Space.s2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s2)
        .onAppear { fill() }
        .onChange(of: value) { _, _ in fill() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([caption, sub].compactMap(\.self).joined(separator: ", "))
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) percent")
    }

    private func fill() {
        withAnimation(Motion.calm(Motion.out(Motion.reveal), reduce)) { shown = value }
    }
}
