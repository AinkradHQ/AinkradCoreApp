import CoreUI
import SwiftUI

/// The clock widget's face, after the macOS clock widget (Ahmed, 2026-11-05): a white dial with 60 ticks and the hour
/// numbers, black hour and minute hands, and an orange second hand that sweeps. Round is the one exception to the
/// rounded-rectangle rule, because a clock dial is round. Reduce Motion: the second hand steps once a second.
struct AnalogClock: View {
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// The dial is drawn once; only the three hands move, as rotated layers, ticking once a second with a short spring
    /// like a quartz clock. A continuous sweep kept an animation running every frame and cost about 30% CPU at idle.
    @Environment(\.homeLive) private var live
    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2
            ZStack {
                Canvas { c, size in dial(c, size) }
                TimelineView(homeTicks(1, live: live)) { ctx in
                    let t =
                        ctx.date.timeIntervalSinceReferenceDate + Double(TimeZone.current.secondsFromGMT(for: ctx.date))
                    // Angles from a running count of seconds, so 59 → 0 keeps turning forward.
                    let sec = t.rounded(.down)
                    ZStack {
                        hand(width: r * 0.07, length: r * 0.5, color: .black).rotationEffect(.degrees(sec / 120))
                        hand(width: r * 0.05, length: r * 0.78, color: .black).rotationEffect(.degrees(sec / 10))
                        hand(width: r * 0.015, length: r * 0.86, color: Self.orange, tail: r * 0.16)
                            .rotationEffect(.degrees(sec * 6))
                    }
                    .animation(Motion.out(Motion.hover), value: sec)
                }
                coreShape(r * 0.02).fill(Self.orange).frame(width: r * 0.09, height: r * 0.09)
                coreShape(r * 0.01).fill(.white).frame(width: r * 0.04, height: r * 0.04)
            }
            .frame(width: 2 * r, height: 2 * r)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text(Date.now, format: .dateTime.hour().minute()))
    }

    static let orange = Color(red: 1, green: 0.58, blue: 0)

    /// A hand pointing at 12 from the centre, with an optional tail past it; rotation turns it about the centre.
    private func hand(width: CGFloat, length: CGFloat, color: Color, tail: CGFloat = 0) -> some View {
        coreShape(width / 4).fill(color).frame(width: width, height: length + tail)
            .offset(y: -(length - tail) / 2)
    }

    /// Face, 60 ticks and the hour numbers.
    private func dial(_ c: GraphicsContext, _ size: CGSize) {
        let r = min(size.width, size.height) / 2
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        c.fill(Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: 2 * r, height: 2 * r)), with: .color(.white))
        for i in 0..<60 {
            let a = Double(i) / 60 * 2 * .pi
            let major = i % 5 == 0
            var p = Path()
            p.move(to: point(mid, r * (major ? 0.84 : 0.88), a))
            p.addLine(to: point(mid, r * 0.94, a))
            c.stroke(p, with: .color(major ? .black : .gray.opacity(0.6)), lineWidth: major ? r * 0.025 : r * 0.015)
        }
        for h in 1...12 {
            let a = Double(h) / 12 * 2 * .pi
            c.draw(
                Text("\(h)").font(.system(size: r * 0.2, weight: .semibold, design: .rounded)).foregroundStyle(.black),
                at: point(mid, r * 0.68, a))
        }
    }

    /// A point `distance` from the centre at `angle` (0 = 12 o'clock, clockwise).
    private func point(_ mid: CGPoint, _ distance: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: mid.x + distance * CGFloat(sin(angle)), y: mid.y - distance * CGFloat(cos(angle)))
    }
}
