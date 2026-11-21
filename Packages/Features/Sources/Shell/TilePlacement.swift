import CoreGraphics

/// Where a newly opened app goes (Ahmed, 2026-11-21: "open new apps in the active workspace, not in a new one; only if the app
/// cannot fit will it be opened in a new workspace"). The fit is the real layout: every pane, old and new, must get at least its
/// minimum width and height in the workspace's area.
extension TileTree {
    /// True when the tiling gives every pane at least its minimum. A pane never needs more height than the area has: a short
    /// window scrolls nothing and squeezes nobody further by sitting side by side. With the height not measured yet (0), one
    /// row of panes fits and a stack does not.
    func fits(in area: CGSize, gap: CGFloat, min: (String) -> CGSize) -> Bool {
        guard area.width > 0 else { return true }
        let tallest = leaves.map { min($0).height }.max() ?? 0
        let height = area.height > 0 ? area.height : tallest
        let out = layout(
            minWidth: { min($0).width }, container: CGSize(width: area.width, height: height), gap: gap, minHeight: 0)
        guard !out.isStrip else { return false }
        return out.frames.allSatisfy { id, r in
            let need = min(id)
            return r.width >= need.width - 0.5 && r.height >= Swift.min(need.height, height) - 0.5
        }
    }

    /// The tiling with `id` added the first way that fits: a new column beside the others, else stacked under the pane with
    /// the most room (the biggest tile). Nil when no way fits and the app needs a workspace of its own.
    func placing(_ id: String, in area: CGSize, gap: CGFloat, min: (String) -> CGSize) -> TileTree? {
        var beside = self
        beside.open(id)
        if beside.fits(in: area, gap: gap, min: min) { return beside }
        guard area.height > 0 else { return nil }
        let frames = layout(minWidth: { min($0).width }, container: area, gap: gap, minHeight: 0).frames
        // Biggest tile first; on a tie the later one, so the new app lands toward the end of the reading order.
        let order = leaves.enumerated().sorted {
            let a = frames[$0.element].map { $0.width * $0.height } ?? 0
            let b = frames[$1.element].map { $0.width * $0.height } ?? 0
            return a != b ? a > b : $0.offset > $1.offset
        }
        for (_, leaf) in order {
            var below = self
            below.insert(id, beside: leaf, edge: .bottom)
            if below.fits(in: area, gap: gap, min: min) { return below }
        }
        return nil
    }
}
