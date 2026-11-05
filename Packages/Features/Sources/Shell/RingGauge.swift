import CoreUI
import SwiftUI

/// The Apple widget gauge (the macOS Batteries widget): a thick ring on a faint track, an SF Symbol in the middle and one
/// short value under it. The ring fills from empty when it appears. Rings are allowed inside widgets only (Ahmed,
/// 2026-11-05); everywhere else stays rounded rectangles.
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
            GeometryReader { g in
                let side = min(g.size.width, g.size.height)
                let line = max(5, side * 0.1)
                ZStack {
                    Circle().stroke(WidgetInk.track, lineWidth: line)
                    Circle().trim(from: 0, to: min(max(shown, 0), 1))
                        .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: symbol).font(.system(size: side * 0.3, weight: .medium))
                        .foregroundStyle(WidgetInk.primary)
                        .symbolEffect(.bounce, value: shown > 0)
                }
                .padding(line / 2)
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            if let caption {
                VStack(spacing: 0) {
                    Text(caption).font(.system(size: MacTextSize.headline + 2, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(WidgetInk.primary)
                        .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
                    if let sub {
                        Text(sub).font(.system(size: MacTextSize.meta, weight: .medium)).foregroundStyle(
                            WidgetInk.secondary
                        )
                        .lineLimit(1)
                    }
                }
            }
        }
        .onAppear { fill() }
        .onChange(of: value) { _, _ in fill() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([caption, sub].compactMap(\.self).joined(separator: ", "))
    }

    private func fill() {
        withAnimation(reduce ? .easeOut(duration: 0.2) : .spring(duration: 1.1, bounce: 0.15)) { shown = value }
    }
}
