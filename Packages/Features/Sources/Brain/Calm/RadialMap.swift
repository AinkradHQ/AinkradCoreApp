import CoreUI
import SwiftUI

/// A source on the home map: what Brain reads, what it read, and whether it reads it now.
struct MapSource: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let line: String
    let live: Bool
    /// The source is switched on (it feeds Brain); off sources stay dark.
    var on = true
}

/// An area on the home map's right: its name, count and what it took in today.
struct MapShelf: Identifiable {
    let page: BrainCalmModel.Page
    let count: Int
    let today: Int
    var id: String { page.rawValue }
}

/// The live map of the Brain redesign: the sources on the left, the Brain in the middle and the four areas on the right,
/// joined by wires. Idle, it is still. While Brain learns, light runs along the wires from the source it reads to the areas
/// that grow, and a halo breathes around the Brain. Reduce Motion: no travelling light, the live wires fade in and out
/// instead and the counts change in place. Off screen or in the background the timeline is paused, not just ignored.
struct BrainMap: View {
    let sources: [MapSource]
    let shelves: [MapShelf]
    let working: Bool
    let line: String
    let open: (BrainCalmModel.Page) -> Void

    @Environment(\.coreAccent) private var accent
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.scenePhase) private var phase
    @State private var onScreen = false

    private static let srcW: CGFloat = 188
    private static let shelfW: CGFloat = 236
    private static let rowH: CGFloat = 50
    private static let gap: CGFloat = 10
    private static let core: CGFloat = 64

    private var ticking: Bool { working && onScreen && phase == .active }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(minimumInterval: reduce ? 1.0 / 10 : 1.0 / 30, paused: !ticking)) { ctx in
                let t = ticking ? ctx.date.timeIntervalSinceReferenceDate : 0
                ZStack(alignment: .topLeading) {
                    Canvas { gc, sz in wires(&gc, sz, t) }
                    ForEach(Array(sources.enumerated()), id: \.element.id) { i, s in
                        source(s).frame(width: Self.srcW, height: Self.rowH)
                            .position(x: Self.srcW / 2 + Space.s8 + Space.s5, y: y(i, of: sources.count, size))
                    }
                    centre(t).position(x: size.width / 2, y: size.height / 2 + Space.s3)
                    ForEach(Array(shelves.enumerated()), id: \.element.id) { i, s in
                        shelf(s).frame(width: Self.shelfW, height: Self.rowH - Space.s1)
                            .position(
                                x: size.width - Self.shelfW / 2 - Space.s8, y: y(i, of: shelves.count, size, step: 48))
                    }
                }
            }
        }
        .frame(height: 224)
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brain-map")
    }

    /// Row `i` of `n`, centred on the map.
    private func y(_ i: Int, of n: Int, _ s: CGSize, step: CGFloat = rowH + gap) -> CGFloat {
        s.height / 2 + (CGFloat(i) - CGFloat(n - 1) / 2) * step
    }

    private func wires(_ gc: inout GraphicsContext, _ sz: CGSize, _ t: Double) {
        let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
        let inX = c.x - Self.core / 2 - Space.s5
        let outX = c.x + Self.core / 2 + Space.s5
        let left = Self.srcW + Space.s8 + Space.s5 + Space.s8
        let right = sz.width - Self.shelfW - Space.s8 - Space.s2
        for (i, s) in sources.enumerated() {
            // While Brain learns, every source that is on feeds it (what it collected earlier is what it is tidying), so
            // their wires run too, not only the one being read this second (2026-11-23: the left side stayed dark).
            draw(
                &gc, from: CGPoint(x: left, y: y(i, of: sources.count, sz)), to: CGPoint(x: inX, y: c.y),
                live: s.live || (working && s.on), t, i)
        }
        for (i, s) in shelves.enumerated() {
            let live = working && s.today > 0
            draw(
                &gc, from: CGPoint(x: outX, y: c.y), to: CGPoint(x: right, y: y(i, of: shelves.count, sz, step: 48)),
                live: live, t, i + 3)
        }
    }

    /// One wire: a soft curve, the accent when live; while learning, a short light runs along it (or, with Reduce
    /// Motion, the whole wire fades in and out).
    private func draw(_ gc: inout GraphicsContext, from a: CGPoint, to b: CGPoint, live: Bool, _ t: Double, _ k: Int) {
        var p = Path()
        p.move(to: a)
        let mx = (a.x + b.x) / 2
        p.addCurve(to: b, control1: CGPoint(x: mx, y: a.y), control2: CGPoint(x: mx, y: b.y))
        let lit = live && working
        let pulse = reduce && ticking ? 0.55 + 0.35 * sin(t * 2 * .pi / 2.4 + Double(k)) : 1
        gc.stroke(
            p, with: .color(lit ? GlassInk.accent(accent).opacity(0.8 * pulse) : palette.track),
            style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        guard lit, ticking, !reduce else { return }
        // A soft comet, not a hard dash: a bright head and a tail that fades in steps, on the wire's own width.
        let u = (t / 2.2 + Double(k) * 0.37).truncatingRemainder(dividingBy: 1)
        let steps = 8
        for j in 0..<steps {
            let to = u - 0.022 * Double(j)
            let from = to - 0.022
            guard to > 0 else { break }
            gc.stroke(
                p.trimmedPath(from: max(0, from), to: min(1, to)),
                with: .color(GlassInk.accent(accent).opacity(1 - Double(j) / Double(steps))),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
    }

    private func source(_ s: MapSource) -> some View {
        HStack(spacing: Space.s3) {
            BrainTile(symbol: s.symbol, lit: working && (s.live || s.on))
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Text(s.line).coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary).lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s3)
        .frame(maxHeight: .infinity)
        .background(GlassInk.well, in: coreShape(Radius.control))
        .accessibilityElement(children: .combine)
    }

    private func centre(_ t: Double) -> some View {
        let u = (t / 3).truncatingRemainder(dividingBy: 1)
        return VStack(spacing: Space.s3) {
            ZStack {
                if ticking {
                    // The halo: a rounded rect that swells and fades; with Reduce Motion it only fades.
                    coreShape(Radius.pane + 4).fill(GlassInk.accent(accent).opacity(0.22 * (1 - u)))
                        .frame(width: Self.core, height: Self.core)
                        .scaleEffect(reduce ? 1.25 : 1 + 0.45 * u)
                }
                Image(systemName: "brain").font(.system(size: 26, weight: .regular)).foregroundStyle(palette.primary)
                    .frame(width: Self.core, height: Self.core)
                    .background(GlassInk.accent(accent).opacity(0.2), in: coreShape(Radius.pane))
            }
            .accessibilityHidden(true)
            HStack(spacing: Space.s1 + 2) {
                if working { coreShape(2).fill(palette.success).frame(width: 6, height: 6).accessibilityHidden(true) }
                Text(line).coreFont(size: MacTextSize.body).foregroundStyle(GlassInk.secondary).lineLimit(1)
                    .contentTransition(.opacity)
            }
            .fixedSize()
        }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: line)
    }

    private func shelf(_ s: MapShelf) -> some View {
        Button {
            open(s.page)
        } label: {
            HStack(spacing: Space.s2) {
                coreShape(2).fill(s.page == .me ? GlassInk.slate : GlassInk.accent(accent)).frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(s.page.title).coreFont(size: MacTextSize.body, weight: .semibold).lineLimit(1)
                Spacer(minLength: Space.s2)
                if s.today > 0 {
                    Text("+\(s.today.formatted())").coreFont(size: MacTextSize.body, weight: .semibold)
                        .foregroundStyle(palette.success).monospacedDigit().contentTransition(.numericText())
                        .frame(minWidth: Space.s8 + Space.s2, alignment: .trailing)
                }
                Text(s.count.formatted()).coreFont(size: MacTextSize.body, weight: .semibold).monospacedDigit()
                    .contentTransition(.numericText()).frame(minWidth: Space.s8 + Space.s5, alignment: .trailing)
            }
            .padding(.horizontal, Space.s3)
            .frame(maxHeight: .infinity)
            .background(GlassInk.well, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: s.count)
        .help("Open \(s.page.title)")
        .accessibilityIdentifier("brain-shelf-\(s.page.rawValue)")
    }
}
