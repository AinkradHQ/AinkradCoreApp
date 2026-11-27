import CoreUI
import SwiftUI

/// A service's last readings as a small calm line (API 110, `run/metrics`): no axes, no numbers, the words say the rest.
/// Projects' own drawing, not a CoreUI component.
struct Sparkline: View {
    let values: [Double]
    /// What it shows, for VoiceOver: "web CPU, last hour".
    let label: String
    var tint: Color = GlassInk.secondary
    /// The scale never shrinks below this, so a service idling at 1 % does not look busy.
    var floor = 1.0

    /// 0...1 per reading against the larger of the biggest reading and `floor`.
    nonisolated static func normalized(_ v: [Double], floor: Double) -> [Double] {
        let top = max(v.max() ?? 0, floor, .leastNonzeroMagnitude)
        return v.map { min(1, max(0, $0 / top)) }
    }

    var body: some View {
        let points = Self.normalized(values, floor: floor)
        Canvas { ctx, size in
            guard points.count > 1 else { return }
            let step = size.width / CGFloat(points.count - 1)
            func at(_ i: Int) -> CGPoint {
                CGPoint(x: CGFloat(i) * step, y: size.height - 1 - CGFloat(points[i]) * (size.height - 2))
            }
            var line = Path()
            line.move(to: at(0))
            for i in 1..<points.count { line.addLine(to: at(i)) }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .color(tint.opacity(0.16)))
            ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
        }
        .frame(width: Space.s8 * 2, height: Space.s4)
        .opacity(points.count > 1 ? 1 : 0)
        .accessibilityElement()
        .accessibilityLabel(points.count > 1 ? label : "")
        .accessibilityHidden(points.count < 2)
    }
}
