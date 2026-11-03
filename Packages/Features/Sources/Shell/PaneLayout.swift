import CoreUI
import SwiftUI

/// Column layout for the pane workspace (`tiles.js`): equal columns while every pane keeps its minimum width,
/// otherwise a Stage-style strip where each pane keeps exactly its minimum and the row scrolls sideways.
struct PaneLayout: Equatable {
    var frames: [CGRect]
    var contentWidth: CGFloat
    var isStrip: Bool

    /// `fractions` are each pane's share of the width left after the gaps (they sum to 1; seam drags change them).
    /// A pane never goes below its minimum width: the shortfall is taken from the panes that have room.
    static func make(
        minWidths: [CGFloat], fractions: [CGFloat] = [], container: CGSize, gap: CGFloat, minHeight: CGFloat
    ) -> PaneLayout {
        let n = minWidths.count
        guard n > 0 else { return PaneLayout(frames: [], contentWidth: container.width, isStrip: false) }
        let need = minWidths.reduce(0, +) + gap * CGFloat(n - 1)
        let height = max(container.height, minHeight)
        let strip = need > container.width + 0.5
        let widths = strip ? minWidths : fitted(minWidths, fractions, available: container.width - gap * CGFloat(n - 1))
        var x: CGFloat = 0
        let frames = widths.map { w in
            defer { x += w + gap }
            return CGRect(x: x, y: 0, width: w, height: height)
        }
        return PaneLayout(frames: frames, contentWidth: strip ? need : container.width, isStrip: strip)
    }

    /// Widths from fractions, with every pane held to its minimum.
    static func fitted(_ mins: [CGFloat], _ fractions: [CGFloat], available: CGFloat) -> [CGFloat] {
        let n = mins.count
        let f =
            fractions.count == n && fractions.allSatisfy({ $0 > 0 })
            ? fractions : Array(repeating: 1 / CGFloat(n), count: n)
        var w = f.map { $0 * available }
        for _ in 0..<n {
            let short = w.indices.filter { w[$0] < mins[$0] - 0.01 }
            if short.isEmpty { break }
            let deficit = short.reduce(0) { $0 + mins[$1] - w[$1] }
            for i in short { w[i] = mins[i] }
            let room = w.indices.filter { !short.contains($0) }.map { w[$0] - mins[$0] }
            let total = room.reduce(0, +)
            guard total > 0 else { break }
            var k = 0
            for i in w.indices where !short.contains(i) {
                w[i] -= deficit * room[k] / total
                k += 1
            }
        }
        return w
    }

    /// The column a dragged pane's centre is nearest to.
    func nearestIndex(toX x: CGFloat) -> Int {
        frames.indices.min { abs(frames[$0].midX - x) < abs(frames[$1].midX - x) } ?? 0
    }
}
