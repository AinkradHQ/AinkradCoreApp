import CoreGraphics

/// Tiling as in the prototype (`tiles.js`): an N-ary split tree. Opening a pane appends an equal top-level column; dropping a pane on
/// the near half of another either joins it as an equal sibling (the drop is along the target's container) or wraps the target in a
/// new 50/50 split (across it). Seams resize with a 10 % minimum; closing re-equalises and collapses single-child splits.
enum TileAxis: Equatable, Sendable { case horizontal, vertical }

enum TileEdge: Equatable, Sendable {
    case left, right, top, bottom
    var axis: TileAxis { self == .left || self == .right ? .horizontal : .vertical }
    var leading: Bool { self == .left || self == .top }
}

indirect enum TileNode: Equatable, Sendable {
    case leaf(String)
    case split(TileAxis, fractions: [CGFloat], children: [TileNode])

    var leaves: [String] {
        switch self {
        case .leaf(let id): [id]
        case .split(_, _, let kids): kids.flatMap(\.leaves)
        }
    }

    static func equalSplit(_ axis: TileAxis, _ kids: [TileNode]) -> TileNode {
        .split(axis, fractions: Array(repeating: 1 / CGFloat(kids.count), count: kids.count), children: kids)
    }
}

/// A draggable gap between two siblings. `origin` and `available` are in the split's own axis, so a pointer position maps to a fraction.
struct TileSeam: Equatable, Sendable {
    var path: [Int]
    var index: Int
    var axis: TileAxis
    var frame: CGRect
    var origin: CGFloat
    var available: CGFloat
    /// Smallest share either neighbour may keep: 10 %, or its pane minimum when that is larger.
    var minLeft: CGFloat
    var minRight: CGFloat
}

struct TileLayout: Equatable, Sendable {
    var frames: [String: CGRect] = [:]
    var seams: [TileSeam] = []
    var contentWidth: CGFloat = 0
    /// The columns would be narrower than their minimums: they keep exactly the minimum and the row scrolls sideways.
    var isStrip = false
}

struct TileDrop: Equatable, Sendable {
    var target: String
    var edge: TileEdge
    /// The half of the target that lights up.
    var hint: CGRect
}

struct TileTree: Equatable, Sendable {
    static let minFraction: CGFloat = 0.1
    var root: TileNode?

    var leaves: [String] { root?.leaves ?? [] }
    func contains(_ id: String) -> Bool { leaves.contains(id) }

    // MARK: edits

    /// A new pane is an equal top-level column.
    mutating func open(_ id: String) {
        guard !contains(id) else { return }
        switch root {
        case nil: root = .leaf(id)
        case .split(.horizontal, _, var kids)?:
            kids.append(.leaf(id))
            root = .equalSplit(.horizontal, kids)
        case let other?: root = .equalSplit(.horizontal, [other, .leaf(id)])
        }
    }

    mutating func remove(_ id: String) { root = root.flatMap { Self.removing(id, from: $0) } }

    private static func removing(_ id: String, from node: TileNode) -> TileNode? {
        switch node {
        case .leaf(let l): return l == id ? nil : node
        case .split(let axis, let fractions, let kids):
            let kept = kids.compactMap { removing(id, from: $0) }
            if kept.isEmpty { return nil }
            if kept.count == 1 { return kept[0] }
            return kept.count == kids.count
                ? .split(axis, fractions: fractions, children: kept) : .equalSplit(axis, kept)
        }
    }

    /// Puts `src` (already removed) on `edge` of `target`.
    mutating func insert(_ src: String, beside target: String, edge: TileEdge) {
        guard let root, target != src else { return }
        self.root = Self.inserting(src, beside: target, edge: edge, in: root)
    }

    private static func inserting(
        _ src: String, beside target: String, edge: TileEdge, in node: TileNode
    ) -> TileNode {
        switch node {
        case .leaf(let l):
            guard l == target else { return node }
            let pair: [TileNode] = edge.leading ? [.leaf(src), node] : [node, .leaf(src)]
            return .equalSplit(edge.axis, pair)
        case .split(let axis, let fractions, let kids):
            if axis == edge.axis, let i = kids.firstIndex(of: .leaf(target)) {
                var next = kids
                next.insert(.leaf(src), at: edge.leading ? i : i + 1)
                return .equalSplit(axis, next)
            }
            return .split(
                axis, fractions: fractions,
                children: kids.map { inserting(src, beside: target, edge: edge, in: $0) })
        }
    }

    /// Drop of a dragged pane: take it out of the tree and put it on the edge.
    mutating func drop(_ id: String, on target: String, edge: TileEdge) {
        guard id != target, contains(id), contains(target) else { return }
        remove(id)
        insert(id, beside: target, edge: edge)
    }

    /// Keyboard: one place left or right in reading order (⌃⌥← / →).
    @discardableResult
    mutating func move(_ id: String, step: Int) -> Bool {
        let all = leaves
        guard let i = all.firstIndex(of: id), all.indices.contains(i + step) else { return false }
        let target = all[i + step]
        remove(id)
        insert(id, beside: target, edge: step < 0 ? .left : .right)
        return true
    }

    /// Seam drag: `position` is the pointer along the split's axis, from the split's origin.
    mutating func resize(_ seam: TileSeam, gap: CGFloat, position: CGFloat) {
        guard let root else { return }
        self.root = Self.resizing(root, path: seam.path[...], seam: seam, gap: gap, position: position)
    }

    private static func resizing(
        _ node: TileNode, path: ArraySlice<Int>, seam: TileSeam, gap: CGFloat, position: CGFloat
    ) -> TileNode {
        guard case .split(let axis, var f, let kids) = node else { return node }
        if let head = path.first {
            var next = kids
            next[head] = resizing(kids[head], path: path.dropFirst(), seam: seam, gap: gap, position: position)
            return .split(axis, fractions: f, children: next)
        }
        let i = seam.index
        guard f.indices.contains(i + 1) else { return node }
        let before = f[..<i].reduce(0, +)
        let pair = f[i] + f[i + 1]
        let raw = (position - gap / 2 - CGFloat(i) * gap) / seam.available - before
        let lo = min(seam.minLeft, pair - seam.minRight)
        f[i] = min(max(raw, lo), pair - seam.minRight)
        f[i + 1] = pair - f[i]
        return .split(axis, fractions: f, children: kids)
    }

    // MARK: geometry

    /// Gaps come out first, the rest is shared by the fractions. A pane never goes below its minimum width: when the top-level
    /// columns cannot all keep theirs, each column gets exactly its minimum and the row scrolls sideways.
    func layout(minWidth: (String) -> CGFloat, container: CGSize, gap: CGFloat, minHeight: CGFloat) -> TileLayout {
        guard let root else { return TileLayout(contentWidth: container.width) }
        let height = max(container.height, minHeight)
        let columns: [TileNode]
        var fractions: [CGFloat]?
        if case .split(.horizontal, let f, let kids) = root {
            columns = kids
            fractions = f
        } else {
            columns = [root]
        }
        let mins = columns.map { $0.leaves.map(minWidth).max() ?? 0 }
        let need = mins.reduce(0, +) + gap * CGFloat(max(columns.count - 1, 0))
        let strip = need > container.width + 0.5
        let width = max(container.width, need)
        var out = TileLayout(contentWidth: width, isStrip: strip)
        let avail = width - gap * CGFloat(max(columns.count - 1, 0))
        let widths: [CGFloat]
        if strip {
            widths = mins
        } else if let fractions, fractions.count == columns.count {
            widths = Self.fitted(mins, fractions, available: avail)
        } else {
            widths = Self.fitted(mins, [], available: avail)
        }
        var x: CGFloat = 0
        for (i, col) in columns.enumerated() {
            let cell = CGRect(x: x, y: 0, width: widths[i], height: height)
            Self.place(col, cell, gap: gap, path: root == col && columns.count == 1 ? [] : [i], into: &out)
            if i < columns.count - 1 {
                let share = avail > 0 ? 1 / avail : 0
                out.seams.append(
                    TileSeam(
                        path: [], index: i, axis: .horizontal,
                        frame: CGRect(x: x + widths[i], y: 0, width: gap, height: height), origin: 0,
                        available: avail, minLeft: max(Self.minFraction, mins[i] * share),
                        minRight: max(Self.minFraction, mins[i + 1] * share)))
            }
            x += widths[i] + gap
        }
        return out
    }

    private static func place(_ node: TileNode, _ r: CGRect, gap: CGFloat, path: [Int], into out: inout TileLayout) {
        switch node {
        case .leaf(let id): out.frames[id] = r
        case .split(let axis, let f, let kids):
            let horizontal = axis == .horizontal
            let total = horizontal ? r.width : r.height
            let avail = total - gap * CGFloat(kids.count - 1)
            var p = horizontal ? r.minX : r.minY
            for (i, kid) in kids.enumerated() {
                let len = avail * f[i]
                let cell =
                    horizontal
                    ? CGRect(x: p, y: r.minY, width: len, height: r.height)
                    : CGRect(x: r.minX, y: p, width: r.width, height: len)
                place(kid, cell, gap: gap, path: path + [i], into: &out)
                p += len
                if i < kids.count - 1 {
                    out.seams.append(
                        TileSeam(
                            path: path, index: i, axis: axis,
                            frame: horizontal
                                ? CGRect(x: p, y: r.minY, width: gap, height: r.height)
                                : CGRect(x: r.minX, y: p, width: r.width, height: gap),
                            origin: horizontal ? r.minX : r.minY, available: avail, minLeft: minFraction,
                            minRight: minFraction))
                    p += gap
                }
            }
        }
    }

    /// Widths from fractions, every column held to its minimum (the shortfall comes from columns with room).
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

    // MARK: drag and drop

    /// Which half of which pane the pointer is over; nil over a gap or over the dragged pane itself.
    static func dropTarget(at p: CGPoint, frames: [String: CGRect], excluding id: String) -> TileDrop? {
        for (other, r) in frames where other != id && r.contains(p) {
            let ux = (p.x - r.minX) / r.width - 0.5
            let uy = (p.y - r.minY) / r.height - 0.5
            let edge: TileEdge = abs(ux) > abs(uy) ? (ux < 0 ? .left : .right) : (uy < 0 ? .top : .bottom)
            let side = edge.axis == .horizontal
            let hint = CGRect(
                x: edge == .right ? r.midX : r.minX, y: edge == .bottom ? r.midY : r.minY,
                width: side ? r.width / 2 : r.width, height: side ? r.height : r.height / 2)
            return TileDrop(target: other, edge: edge, hint: hint)
        }
        return nil
    }
}
