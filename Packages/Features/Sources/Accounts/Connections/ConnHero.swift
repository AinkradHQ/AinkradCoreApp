import CoreUI
import SwiftUI

/// Where the services sit around the Core, and the one light that runs along a wire. Plain numbers, so it is a test.
enum ConnHeroGeometry {
    static let size = CGSize(width: 700, height: 240)
    static let core = CGPoint(x: 350, y: 150)
    /// Offsets from the Core, and how far the wire bows (positive is up), by kind.
    static let nodes: [(kind: String, dx: CGFloat, dy: CGFloat, bow: CGFloat)] = [
        ("github", -300, 26, 40), ("jira", -170, -86, 10), ("linear", 0, -127, 0), ("slack", 170, -86, 10),
        ("teams", 300, 26, 40),
    ]
    static let lightPeriod = 2.6
    static let lightTravel = 1.2

    static func point(_ n: (kind: String, dx: CGFloat, dy: CGFloat, bow: CGFloat)) -> CGPoint {
        CGPoint(x: core.x + n.dx, y: core.y + n.dy)
    }

    /// The wire from a node to the Core as one quad curve.
    static func wire(_ n: (kind: String, dx: CGFloat, dy: CGFloat, bow: CGFloat)) -> (
        a: CGPoint, c: CGPoint, b: CGPoint
    ) {
        let a = point(n)
        return (a, CGPoint(x: (a.x + core.x) / 2, y: min(a.y, core.y) - n.bow), core)
    }

    /// A point on the wire at `t` in 0...1.
    static func along(_ w: (a: CGPoint, c: CGPoint, b: CGPoint), _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * w.a.x + 2 * u * t * w.c.x + t * t * w.b.x, y: u * u * w.a.y + 2 * u * t * w.c.y + t * t * w.b.y)
    }

    /// Which of `count` wires carries the light at time `t`, and how far along it is; nil between runs and under Reduce Motion.
    static func light(at t: Double, count: Int, reduce: Bool) -> (wire: Int, progress: Double)? {
        guard !reduce, count > 0 else { return nil }
        let cycle = Int((t / lightPeriod).rounded(.down))
        let into = t - Double(cycle) * lightPeriod
        guard into < lightTravel else { return nil }
        let x = into / lightTravel
        // Eased at both ends, like the working bar.
        return ((cycle % count + count) % count, (1 - cos(x * .pi)) / 2)
    }
}

/// The Core in the middle with the services around it, joined by wires: dashed when idle, solid accent when connected or
/// when its card is under the pointer. A light runs along one wire every 2.6 s. Time-driven; the pointer only lights a wire.
struct ConnHero: View {
    let kinds: [String]
    let connected: Set<String>
    let hovered: String?
    let names: [String: String]
    @Environment(\.coreAccent) private var paneAccent
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var nodes: [(kind: String, dx: CGFloat, dy: CGFloat, bow: CGFloat)] {
        ConnHeroGeometry.nodes.filter { kinds.contains($0.kind) }
    }

    var body: some View {
        let accent = GlassInk.accentInk(paneAccent)
        let nodes = nodes
        let running = nodes.filter { connected.isEmpty || connected.contains($0.kind) }
        ZStack {
            Canvas { ctx, _ in
                for n in nodes {
                    let w = ConnHeroGeometry.wire(n)
                    var p = Path()
                    p.move(to: w.a)
                    p.addQuadCurve(to: w.b, control: w.c)
                    let on = connected.contains(n.kind) || hovered == n.kind
                    if on {
                        ctx.stroke(p, with: .color(accent.opacity(0.7)), lineWidth: 1.5)
                    } else {
                        ctx.stroke(
                            p, with: .color(GlassInk.secondary.opacity(0.5)),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    }
                }
            }
            TimelineView(.animation(paused: reduce || running.isEmpty)) { tl in
                Canvas { ctx, _ in
                    guard
                        let l = ConnHeroGeometry.light(
                            at: tl.date.timeIntervalSinceReferenceDate, count: running.count, reduce: reduce)
                    else { return }
                    let at = ConnHeroGeometry.along(ConnHeroGeometry.wire(running[l.wire]), l.progress)
                    ctx.fill(
                        Path(roundedRect: CGRect(x: at.x - 3, y: at.y - 3, width: 6, height: 6), cornerRadius: 2),
                        with: .color(accent))
                }
            }
            coreTile
            ForEach(nodes, id: \.kind) { n in node(n) }
        }
        .frame(width: ConnHeroGeometry.size.width, height: ConnHeroGeometry.size.height)
        .animation(Motion.calm(Motion.out(Motion.hover), reduce), value: hovered)
        .accessibilityHidden(true)
    }

    private var coreTile: some View {
        ZStack {
            coreShape(Radius.pane).fill(GlassInk.well).frame(width: 108, height: 108)
            ConnCoreTile(size: 88)
        }
        .position(ConnHeroGeometry.core)  // grid: ok hero composition
    }

    private func node(_ n: (kind: String, dx: CGFloat, dy: CGFloat, bow: CGFloat)) -> some View {
        let on = connected.contains(n.kind) || hovered == n.kind
        let lifted = hovered == n.kind
        return VStack(spacing: Space.s2) {
            ConnLogo(kind: n.kind, size: 56, lit: on)
            Text(names[n.kind] ?? n.kind).coreFont(size: MacTextSize.meta)
                .foregroundStyle(on ? GlassInk.primary : GlassInk.secondary).lineLimit(1).fixedSize()
        }
        .offset(y: reduce ? 0 : lifted ? -3 : 0)  // grid: ok motion only, a lift on hover
        .position(x: ConnHeroGeometry.point(n).x, y: ConnHeroGeometry.point(n).y + 11)  // grid: ok hero composition
    }
}
