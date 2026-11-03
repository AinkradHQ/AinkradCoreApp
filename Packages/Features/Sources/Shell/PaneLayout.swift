import CoreUI
import SwiftUI

/// Column layout for the pane workspace (`tiles.js`): equal columns while every pane keeps its minimum width,
/// otherwise a Stage-style strip where each pane keeps exactly its minimum and the row scrolls sideways.
struct PaneLayout: Equatable {
    var frames: [CGRect]
    var contentWidth: CGFloat
    var isStrip: Bool

    static func make(minWidths: [CGFloat], container: CGSize, gap: CGFloat, minHeight: CGFloat) -> PaneLayout {
        let n = minWidths.count
        guard n > 0 else { return PaneLayout(frames: [], contentWidth: container.width, isStrip: false) }
        let need = minWidths.reduce(0, +) + gap * CGFloat(n - 1)
        let height = max(container.height, minHeight)
        let strip = need > container.width + 0.5
        // Fitting: every pane gets its minimum plus an equal share of what is left, so equal minimums give equal columns.
        let extra = strip ? 0 : (container.width - need) / CGFloat(n)
        var x: CGFloat = 0
        let frames = minWidths.map { min in
            defer { x += min + extra + gap }
            return CGRect(x: x, y: 0, width: min + extra, height: height)
        }
        return PaneLayout(frames: frames, contentWidth: strip ? need : container.width, isStrip: strip)
    }

    /// The column a dragged pane's centre is nearest to.
    func nearestIndex(toX x: CGFloat) -> Int {
        frames.indices.min { abs(frames[$0].midX - x) < abs(frames[$1].midX - x) } ?? 0
    }
}
