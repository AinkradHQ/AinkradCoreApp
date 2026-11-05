import CoreUI
import SwiftUI

/// The clock widget's face, after the macOS clock widget (Ahmed, 2026-11-05): a white dial with 60 ticks and the hour
/// numbers, black hour and minute hands, and an orange second hand that sweeps. Round is the one exception to the
/// rounded-rectangle rule, because a clock dial is round. Reduce Motion: the second hand steps once a second.
struct AnalogClock: View {
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        // Paused animation schedule under Reduce Motion would freeze it, so it ticks at 1 fps instead of sweeping.
        TimelineView(.animation(minimumInterval: reduce ? 1 : nil)) { ctx in
            Canvas { c, size in draw(c, size, ctx.date) }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text(Date.now, format: .dateTime.hour().minute()))
    }

    private func draw(_ c: GraphicsContext, _ size: CGSize, _ date: Date) {
        let r = min(size.width, size.height) / 2
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        let dial = Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: 2 * r, height: 2 * r))
        c.fill(dial, with: .color(.white))

        // 60 ticks: the five-minute ones longer and black.
        for i in 0..<60 {
            let a = Double(i) / 60 * 2 * .pi
            let major = i % 5 == 0
            let outer = r * 0.94
            let inner = r * (major ? 0.84 : 0.88)
            var p = Path()
            p.move(to: point(mid, inner, a))
            p.addLine(to: point(mid, outer, a))
            c.stroke(p, with: .color(major ? .black : .gray.opacity(0.6)), lineWidth: major ? r * 0.025 : r * 0.015)
        }
        // Hour numbers.
        for h in 1...12 {
            let a = Double(h) / 12 * 2 * .pi
            c.draw(
                Text("\(h)").font(.system(size: r * 0.2, weight: .semibold, design: .rounded)).foregroundStyle(.black),
                at: point(mid, r * 0.68, a))
        }

        let cal = Calendar.current
        let parts = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let sec = Double(parts.second ?? 0) + (reduce ? 0 : Double(parts.nanosecond ?? 0) / 1e9)
        let min = Double(parts.minute ?? 0) + sec / 60
        let hour = Double((parts.hour ?? 0) % 12) + min / 60

        hand(c, mid, angle: hour / 12 * 2 * .pi, length: r * 0.5, width: r * 0.07, color: .black)
        hand(c, mid, angle: min / 60 * 2 * .pi, length: r * 0.78, width: r * 0.05, color: .black)
        let orange = Color(red: 1, green: 0.58, blue: 0)
        hand(c, mid, angle: sec / 60 * 2 * .pi, length: r * 0.86, width: r * 0.015, color: orange, tail: r * 0.16)
        let hub = r * 0.045
        c.fill(
            Path(ellipseIn: CGRect(x: mid.x - hub, y: mid.y - hub, width: 2 * hub, height: 2 * hub)),
            with: .color(orange))
        let dot = hub * 0.45
        c.fill(
            Path(ellipseIn: CGRect(x: mid.x - dot, y: mid.y - dot, width: 2 * dot, height: 2 * dot)),
            with: .color(.white))
    }

    private func hand(
        _ c: GraphicsContext, _ mid: CGPoint, angle: Double, length: CGFloat, width: CGFloat, color: Color,
        tail: CGFloat = 0
    ) {
        var p = Path()
        p.move(to: point(mid, -tail, angle))
        p.addLine(to: point(mid, length, angle))
        c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    /// A point `distance` from the centre at `angle` (0 = 12 o'clock, clockwise).
    private func point(_ mid: CGPoint, _ distance: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: mid.x + distance * CGFloat(sin(angle)), y: mid.y - distance * CGFloat(cos(angle)))
    }
}
