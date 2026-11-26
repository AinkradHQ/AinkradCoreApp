import CoreUI
import SwiftUI

/// The canvas while the AI works, drawn over the engine's view in its own coordinates (the camera maps document rects to
/// view points every display frame, so it follows pan and zoom):
/// - an edit: the screen being redrawn glows round its edge, a light sweeps down it, a label says what is happening;
/// - a new drawing: ghost screens stand where the Core will place the new frames, dashed edges marching, contents shimmering.
/// It never takes a click. Reduce Motion keeps the shapes still.
struct CanvasAIOverlay: View {
    let editor: DesignEditor
    /// Document rects: the frame being redrawn (edit) or where new frames will land.
    let rects: [CGRect]
    let editing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    @Environment(\.coreAccent) private var paneAccent
    @State private var shown = false
    /// The camera, read a few times a second (not every frame: a read takes the engine's lock the renderer holds).
    @State private var cam: CanvasCamera?

    private var ink: Color { GlassInk.accent(paneAccent) }

    var body: some View {
        TimelineView(.animation(paused: reduce)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            if let cam {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(rects.enumerated()), id: \.offset) { i, r in
                        let v = CGRect(
                            x: r.minX * cam.zoom + cam.pan.x, y: r.minY * cam.zoom + cam.pan.y,
                            width: r.width * cam.zoom, height: r.height * cam.zoom)
                        Group {
                            if editing { redraw(v, t: t) } else { ghost(v, t: t, index: i) }
                        }
                        .opacity(shown ? 1 : 0)
                        .scaleEffect(shown || reduce ? 1 : 0.96, anchor: .center)
                        .animation(Motion.out(Motion.ui).delay(reduce ? 0 : Double(i) * 0.12), value: shown)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { shown = true }
        .task {
            while !Task.isCancelled {
                let now = editor.camera()
                if now != cam { cam = now }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    // MARK: edit

    private func redraw(_ v: CGRect, t: Double) -> some View {
        let r = max(4, min(v.width, v.height) * 0.02)
        let angle = reduce ? 0 : (t.truncatingRemainder(dividingBy: 2.4) / 2.4) * 360
        let sweep = reduce ? 0.5 : (t.truncatingRemainder(dividingBy: 2.2) / 2.2)
        return ZStack(alignment: .topLeading) {
            // The light sweeping down the screen.
            LinearGradient(colors: [.clear, ink.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)
                .frame(width: v.width, height: v.height * 0.3)
                .offset(y: -v.height * 0.3 + (v.height * 1.3) * sweep)
                .frame(width: v.width, height: v.height, alignment: .top)
                .clipShape(coreShape(r))
            // A soft tint so the screen reads as busy.
            coreShape(r).fill(ink.opacity(0.06)).frame(width: v.width, height: v.height)
            // The glowing edge, its light running round.
            coreShape(r)
                .strokeBorder(
                    AngularGradient(
                        colors: [ink.opacity(0.15), ink, .white.opacity(0.9), ink, ink.opacity(0.15)],
                        center: .center, angle: .degrees(angle)),
                    lineWidth: 2.5
                )
                .frame(width: v.width, height: v.height)
            // A wider, fainter edge for the glow (a shadow re-rendered every frame over the Metal canvas stalled the window).
            coreShape(r + 3).strokeBorder(ink.opacity(0.25), lineWidth: 6)
                .frame(width: v.width + 6, height: v.height + 6)
                .offset(x: -3, y: -3)
            label("AI is redrawing…")
                .offset(y: -30)
        }
        .offset(x: v.minX, y: v.minY)
    }

    // MARK: new

    private func ghost(_ v: CGRect, t: Double, index: Int) -> some View {
        let r = max(4, min(v.width, v.height) * 0.04)
        let march = reduce ? 0 : -(t * 24).truncatingRemainder(dividingBy: 16)
        let shimmer = reduce ? 0.5 : ((t + Double(index) * 0.3).truncatingRemainder(dividingBy: 1.8) / 1.8)
        let pad = v.width * 0.08
        return ZStack(alignment: .topLeading) {
            coreShape(r).fill(GlassInk.adaptive(.white.opacity(0.05), day: .black.opacity(0.04)))
            // Skeleton contents: a header, a few lines, the main button.
            VStack(alignment: .leading, spacing: v.height * 0.03) {
                coreShape(r * 0.6).fill(ink.opacity(0.22)).frame(height: v.height * 0.06)
                ForEach(0..<5, id: \.self) { i in
                    coreShape(r * 0.4).fill(GlassInk.secondary.opacity(0.16))
                        .frame(width: v.width * (i.isMultiple(of: 2) ? 0.7 : 0.5), height: v.height * 0.022)
                }
                Spacer(minLength: 0)
                coreShape(r * 0.6).fill(ink.opacity(0.28)).frame(height: v.height * 0.07)
            }
            .padding(pad)
            .frame(width: v.width, height: v.height, alignment: .topLeading)
            // The shimmer crossing it.
            LinearGradient(colors: [.clear, .white.opacity(0.12), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: v.width * 0.5, height: v.height)
                .offset(x: -v.width * 0.5 + v.width * 1.5 * shimmer)
                .frame(width: v.width, height: v.height, alignment: .leading)
                .clipShape(coreShape(r))
                .blendMode(.plusLighter)
            coreShape(r)
                .strokeBorder(ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [8, 8], dashPhase: march))
            label(rects.count > 1 ? "Direction \(["A", "B", "C"][min(index, 2)])" : "New screen")
                .offset(y: -30)
        }
        .frame(width: v.width, height: v.height)
        .offset(x: v.minX, y: v.minY)
    }

    private func label(_ words: String) -> some View {
        HStack(spacing: Space.s1) {
            Image(systemName: "sparkles").symbolEffect(.pulse, options: .repeating, isActive: !reduce)
            Text(words)
        }
        .coreFont(size: MacTextSize.meta, weight: .semibold)
        .foregroundStyle(.white)
        .padding(.horizontal, Space.s2).frame(height: 22)
        .background(ink, in: coreShape(Radius.chip))
        .fixedSize()
    }
}

extension DesignComposer {
    /// Where the Core puts new frames (`compose.rs`): right of the rightmost top-level node, 60 apart, `size` each.
    static func landing(count: Int, size: CGSize, in editor: DesignEditor) -> [CGRect] {
        guard let page = editor.layers.children(of: nil).first else { return [] }
        let right = editor.layers.children(of: page.id).compactMap { l -> Double? in
            guard let n = editor.node(of: l.id) else { return nil }
            return (n.props["x"]?.double ?? 0) + (n.props["w"]?.double ?? 0)
        }.max()
        let x0 = right.map { $0 + 60 } ?? 0
        return (0..<count).map {
            CGRect(x: x0 + Double($0) * (size.width + 60), y: 0, width: size.width, height: size.height)
        }
    }

    /// A frame's document rect, from its props.
    static func rect(of id: String, in editor: DesignEditor) -> CGRect? {
        guard let n = editor.node(of: id), let w = n.props["w"]?.double, let h = n.props["h"]?.double else {
            return nil
        }
        return CGRect(x: n.props["x"]?.double ?? 0, y: n.props["y"]?.double ?? 0, width: w, height: h)
    }
}
