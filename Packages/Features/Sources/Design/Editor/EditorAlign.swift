import Foundation

/// Align and distribute for the selection, as pure maths (so it is tested without an engine). Boxes are in their parent's
/// space (x, y, w, h). Several layers align to the selection's own bounds, each by its own size; one layer aligns to its
/// parent. Typed values elsewhere are never snapped, and neither are these.
enum EditorAlign {
    enum Edge: Equatable {
        case left, centerX, right, top, centerY, bottom
        var horizontal: Bool { [.left, .centerX, .right].contains(self) }
    }

    struct Box: Equatable {
        let id: String
        var x: Double
        var y: Double
        var w: Double
        var h: Double
    }

    /// `bounds` is the parent's size for one layer; nil takes the union of the boxes. Returns `(id, key, value)` writes for the
    /// boxes that actually move.
    static func align(_ boxes: [Box], _ edge: Edge, in bounds: (w: Double, h: Double)? = nil) -> [(String, String, Double)] {
        guard let first = boxes.first else { return [] }
        let minX = bounds != nil ? 0 : boxes.map(\.x).min() ?? first.x
        let maxX = bounds?.w ?? boxes.map { $0.x + $0.w }.max() ?? first.x
        let minY = bounds != nil ? 0 : boxes.map(\.y).min() ?? first.y
        let maxY = bounds?.h ?? boxes.map { $0.y + $0.h }.max() ?? first.y
        var out: [(String, String, Double)] = []
        for b in boxes {
            let (key, now, to): (String, Double, Double) =
                switch edge {
                case .left: ("x", b.x, minX)
                case .centerX: ("x", b.x, minX + (maxX - minX - b.w) / 2)
                case .right: ("x", b.x, maxX - b.w)
                case .top: ("y", b.y, minY)
                case .centerY: ("y", b.y, minY + (maxY - minY - b.h) / 2)
                case .bottom: ("y", b.y, maxY - b.h)
                }
            if abs(now - to) > 0.0001 { out.append((b.id, key, to)) }
        }
        return out
    }

    /// Equal gaps between three or more boxes along one axis; the outer two stay where they are.
    static func distribute(_ boxes: [Box], horizontal: Bool) -> [(String, String, Double)] {
        guard boxes.count >= 3 else { return [] }
        let pos: (Box) -> Double = { horizontal ? $0.x : $0.y }
        let len: (Box) -> Double = { horizontal ? $0.w : $0.h }
        let sorted = boxes.sorted { pos($0) < pos($1) }
        let span = (pos(sorted.last!) + len(sorted.last!)) - pos(sorted[0])
        let gap = (span - sorted.map(len).reduce(0, +)) / Double(sorted.count - 1)
        var at = pos(sorted[0])
        var out: [(String, String, Double)] = []
        for b in sorted {
            if abs(pos(b) - at) > 0.0001 { out.append((b.id, horizontal ? "x" : "y", at)) }
            at += len(b) + gap
        }
        return out
    }
}
