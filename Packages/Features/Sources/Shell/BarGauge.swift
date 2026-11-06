import CoreUI
import SwiftUI

/// The widget gauge: an icon, one short value, and a horizontal bar that fills from empty when it appears. Rounded
/// rectangles only (Ahmed, 2026-11-06: no rings).
struct BarGauge: View {
    let value: Double
    let symbol: String
    var tint: Color
    var caption: String?
    var sub: String?
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = 0.0

    var body: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: symbol).font(.system(size: MacTextSize.large, weight: .medium))
                .foregroundStyle(GlassInk.primary)
                .symbolEffect(.bounce, value: shown > 0)
                .accessibilityHidden(true)
            if let caption {
                VStack(spacing: 0) {
                    Text(caption).font(.system(size: MacTextSize.title, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(GlassInk.primary)
                        .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
                    if let sub {
                        Text(sub).font(.system(size: MacTextSize.meta, weight: .medium))
                            .foregroundStyle(GlassInk.secondary).lineLimit(1)
                    }
                }
            }
            coreShape(2).fill(GlassInk.track).frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        coreShape(2).fill(tint).frame(width: g.size.width * min(max(shown, 0), 1))
                    }
                }
        }
        .frame(minWidth: 64)
        .onAppear { fill() }
        .onChange(of: value) { _, _ in fill() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([caption, sub].compactMap(\.self).joined(separator: ", "))
    }

    private func fill() {
        withAnimation(Motion.out(reduce ? Motion.hover : Motion.reveal)) { shown = value }
    }
}
