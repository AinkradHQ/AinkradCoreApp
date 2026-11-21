import CoreUI
import SwiftUI

/// One area card on the home map.
struct RadialNode: Identifiable {
    let page: BrainCalmModel.Page
    let count: Int
    let line: String
    let today: Int
    var id: String { page.rawValue }
}

/// The home map of mockup 15: the Brain tile in the middle and the area cards around it, joined by dashed lines. While Brain works,
/// the dashes crawl and small packets flow along each line toward the centre, and the cards float gently. Reduce Motion, a pane
/// that is not on screen, or an idle Brain: lines static, no packets, no float (the timeline is paused, not just ignored).
struct RadialMap: View {
    @Environment(\.coreAccent) private var paneAccent
    let nodes: [RadialNode]
    let working: Bool
    let label: String
    let open: (BrainCalmModel.Page) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.scenePhase) private var phase
    @State private var onScreen = false
    @State private var shown = false

    /// Positions in the mockup's 876 x 740 map, as fractions. `Double` on purpose: as bare literals `190 / 876` picked
    /// `CGPoint(x: Int, y: Int)` and divided as integers to 0, which put every card in the map's top-left corner.
    static let spots: [BrainCalmModel.Page: CGPoint] = [
        .me: CGPoint(x: 190.0 / 876, y: 120.0 / 740), .rules: CGPoint(x: 686.0 / 876, y: 120.0 / 740),
        .knowledge: CGPoint(x: 130.0 / 876, y: 400.0 / 740), .timeline: CGPoint(x: 746.0 / 876, y: 400.0 / 740),
        .places: CGPoint(x: 438.0 / 876, y: 620.0 / 740),
    ]
    private static let centre = CGPoint(x: 0.5, y: 360.0 / 740)

    private var animating: Bool { working && !reduce && onScreen && phase == .active }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animating)) { ctx in
                let t = animating ? ctx.date.timeIntervalSinceReferenceDate : 0
                ZStack {
                    Canvas { gc, sz in draw(&gc, sz, t) }
                    centre(size, t)
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { i, node in
                        let p = point(node.page, size)
                        card(node)
                            .frame(width: cardWidth(size), height: Self.cardHeight)
                            .position(x: p.x, y: p.y + float(t, i))
                            .coreRise(shown, i)
                    }
                }
            }
        }
        .frame(minHeight: Space.s8 * 18)
        .onAppear {
            onScreen = true
            shown = true
        }
        .onDisappear { onScreen = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-map")
    }

    private static let cardHeight = Space.s8 * 4
    private func cardWidth(_ s: CGSize) -> CGFloat { min(250, max(170, s.width * 0.28)) }
    /// A card's centre, kept inside the map so a narrow or short pane never pushes a card over the title or the edge.
    private func point(_ p: BrainCalmModel.Page, _ s: CGSize) -> CGPoint {
        let f = Self.spots[p] ?? Self.centre
        let w = cardWidth(s) / 2
        let h = Self.cardHeight / 2
        return CGPoint(
            x: min(max(f.x * s.width, w), max(s.width - w, w)), y: min(max(f.y * s.height, h), max(s.height - h, h)))
    }
    private func middle(_ s: CGSize) -> CGPoint { CGPoint(x: Self.centre.x * s.width, y: Self.centre.y * s.height) }
    /// Where the line from the centre meets the card's edge: the line stops there instead of running under the glass card.
    private func edge(_ p: CGPoint, to c: CGPoint, half: CGSize) -> CGPoint {
        let dx = c.x - p.x
        let dy = c.y - p.y
        let k = min(dx == 0 ? .infinity : half.width / abs(dx), dy == 0 ? .infinity : half.height / abs(dy))
        guard k < 1 else { return p }
        return CGPoint(x: p.x + dx * k, y: p.y + dy * k)
    }
    /// Each card floats up and down a few points on its own seven-second loop.
    private func float(_ t: Double, _ i: Int) -> CGFloat { CGFloat(sin(t * 2 * .pi / 7 + Double(i) * 1.3) * 3) }

    private func draw(_ gc: inout GraphicsContext, _ sz: CGSize, _ t: Double) {
        let c = middle(sz)
        for (i, n) in nodes.enumerated() {
            let p = edge(point(n.page, sz), to: c, half: CGSize(width: cardWidth(sz) / 2, height: Self.cardHeight / 2))
            var path = Path()
            path.move(to: p)
            path.addLine(to: c)
            let phase = CGFloat(t * 6)
            gc.stroke(
                path, with: .color(.secondary.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 7], dashPhase: -phase))
            guard animating else { continue }
            // Two packets per line, a few seconds apart, flowing toward the centre.
            for k in 0..<2 {
                let u = (t / 5.0 + Double(i) * 0.19 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                let pt = CGPoint(x: p.x + (c.x - p.x) * u, y: p.y + (c.y - p.y) * u)
                let fade = sin(u * .pi)
                gc.fill(
                    Path(roundedRect: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6), cornerRadius: 2),
                    with: .color(GlassInk.accent(paneAccent).opacity(0.9 * fade)))
            }
        }
    }

    /// Two halo rings around the tile: they swell and fade on a four-second loop, half a loop apart. Static (fixed size and
    /// strength) when nothing animates.
    private func halo(_ t: Double, _ k: Int) -> some View {
        let u = animating ? (t / 4 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1) : 0.3 + Double(k) * 0.35
        return coreShape(Radius.cardMac + 4)
            .stroke(GlassInk.accent(paneAccent).opacity(animating ? 0.45 * (1 - u) : 0.16), lineWidth: 1.5)
            .frame(width: Space.s8 * 2, height: Space.s8 * 2)
            .scaleEffect(1 + 0.7 * u)
            .accessibilityHidden(true)
    }

    private func centre(_ s: CGSize, _ t: Double) -> some View {
        let c = middle(s)
        return VStack(spacing: Space.s2) {
            ZStack {
                halo(t, 0)
                halo(t, 1)
                Image(systemName: "brain").font(.system(size: 28)).frame(width: Space.s8 * 2, height: Space.s8 * 2)
                    .background(GlassInk.accent(paneAccent).opacity(0.18), in: coreShape(Radius.cardMac))
                    .accessibilityHidden(true)
            }
            HStack(spacing: Space.s1) {
                RoundedRectangle(cornerRadius: 2).fill(working ? Color.green : Color.secondary).frame(
                    width: 6, height: 6)
                Text(label).coreFont(size: MacTextSize.meta, weight: .semibold)
            }
        }
        .position(c)
    }

    private func card(_ node: RadialNode) -> some View {
        Button {
            open(node.page)
        } label: {
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack {
                    Image(systemName: node.page.symbol).accessibilityHidden(true)
                    Text(node.page == .rules ? "Rules" : node.page.title)
                        .coreFont(size: MacTextSize.headline, weight: .semibold)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(GlassInk.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text("\(node.count)").coreFont(size: MacTextSize.title, weight: .semibold).monospacedDigit()
                        .contentTransition(.numericText())
                    if node.today > 0 {
                        Text("+\(node.today) today").coreFont(size: MacTextSize.meta).foregroundStyle(
                            GlassInk.accent(paneAccent))
                    }
                }
                Text(node.line).lineLimit(2).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
                Spacer(minLength: 0)
            }
            .padding(Space.s3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).coreWell()
            // An empty area stays on the map, quiet (mockup 15, fresh Brain).
            .opacity(node.count == 0 ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("brain-node-\(node.page.rawValue)")
    }
}
