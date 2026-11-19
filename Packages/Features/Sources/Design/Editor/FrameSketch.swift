import CoreUI
import SwiftUI

/// A small picture of one canvas frame for the composer's direction cards: the frame's background and its direct children
/// (rectangles and text) at their own positions, read from the engine's node list. The engine has no export op, so this
/// draws the common cases (solid fills, radius, text size and weight); a gradient, image or token fill is left plain.
struct FrameSketch: Equatable, Sendable {
    struct Shape: Equatable, Sendable {
        let x, y, w, h: Double
        let radius: Double
        let color: String?
        /// Text only: its size in the frame's points.
        let textSize: Double?
        let text: String?
        let weight: Double
    }
    let w: Double
    let h: Double
    let radius: Double
    let background: String?
    let shapes: [Shape]

    /// `nil` when the frame is not in the tree or has no size.
    @MainActor static func make(frame id: String, layers: LayerTree, node: (String) -> EditorNode?) -> FrameSketch? {
        guard let f = node(id), let w = f.props["w"]?.double, let h = f.props["h"]?.double, w > 0, h > 0 else { return nil }
        let kids = layers.children(of: id).filter { !$0.hidden }.prefix(40).compactMap { l -> Shape? in
            guard let n = node(l.id), ["rect", "text", "ellipse", "frame"].contains(n.type) else { return nil }
            let kw = n.props["w"]?.double ?? 0
            let kh = n.props["h"]?.double ?? 0
            guard kw > 0, kh > 0 else { return nil }
            return Shape(
                x: n.props["x"]?.double ?? 0, y: n.props["y"]?.double ?? 0, w: kw, h: kh,
                radius: n.type == "ellipse" ? max(kw, kh) : n.props["radius"]?.double ?? 0, color: hex(n),
                textSize: n.type == "text" ? n.props["type"]?["size"]?.double ?? 14 : nil, text: n.text,
                weight: n.props["type"]?["weight"]?.double ?? 400)
        }
        return FrameSketch(w: w, h: h, radius: f.props["radius"]?.double ?? 0, background: hex(f), shapes: Array(kids))
    }

    /// The first solid fill as `#RRGGBB`, when it is a literal.
    static func hex(_ n: EditorNode) -> String? {
        guard let c = InspectorEdits.firstSolid(n)?.string, c.hasPrefix("#"), [4, 7, 9].contains(c.count) else { return nil }
        return c
    }

    /// `#RGB`, `#RRGGBB` or `#RRGGBBAA`.
    static func color(_ hex: String?, fallback: Color) -> Color {
        guard var s = hex?.dropFirst().description else { return fallback }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return fallback }
        let a = s.count == 8 ? Double(v & 0xFF) / 255 : 1
        let rgb = s.count == 8 ? v >> 8 : v
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255,
            opacity: a)
    }
}

struct FrameSketchView: View {
    let sketch: FrameSketch

    var body: some View {
        GeometryReader { g in
            let k = min(g.size.width / sketch.w, g.size.height / sketch.h)
            ZStack(alignment: .topLeading) {
                coreShape(sketch.radius * k).fill(FrameSketch.color(sketch.background, fallback: .white))
                ForEach(Array(sketch.shapes.enumerated()), id: \.offset) { _, s in
                    shape(s, k)
                }
            }
            .frame(width: sketch.w * k, height: sketch.h * k)
            .clipShape(coreShape(sketch.radius * k))
            .frame(width: g.size.width, height: g.size.height)
        }
        .aspectRatio(sketch.w / sketch.h, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func shape(_ s: FrameSketch.Shape, _ k: Double) -> some View {
        if let size = s.textSize, let t = s.text {
            Text(t).font(.system(size: max(size * k, 1), weight: Font.Weight(weight: s.weight)))
                .foregroundStyle(FrameSketch.color(s.color, fallback: .black)).lineLimit(2)
                .frame(width: s.w * k, height: s.h * k, alignment: .topLeading).offset(x: s.x * k, y: s.y * k)
        } else {
            coreShape(s.radius * k).fill(FrameSketch.color(s.color, fallback: .clear))
                .frame(width: s.w * k, height: s.h * k).offset(x: s.x * k, y: s.y * k)
        }
    }
}

extension Font.Weight {
    init(weight: Double) {
        switch weight {
        case ..<250: self = .thin
        case ..<450: self = .regular
        case ..<550: self = .medium
        case ..<650: self = .semibold
        case ..<750: self = .bold
        default: self = .heavy
        }
    }
}
