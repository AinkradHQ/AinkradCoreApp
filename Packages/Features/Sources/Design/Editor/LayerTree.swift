import Foundation

/// Where a dragged layer lands, in the panel's terms: the panel lists the front layer first (highest order on top).
enum LayerDrop: Equatable {
    case above(String)
    case below(String)
    /// Inside a container, in front of its other children.
    case into(String)
}

struct LayerRow: Identifiable, Equatable {
    var id: String { layer.id }
    let layer: DesignLayer
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
}

/// The document's nodes as the layers panel shows them. Pure: no engine, so drag and reorder are tested without one.
struct LayerTree: Equatable {
    let layers: [DesignLayer]
    private let byID: [String: DesignLayer]
    private let kids: [String: [DesignLayer]]  // ascending by order, ties by id
    private let roots: [DesignLayer]

    init(_ layers: [DesignLayer]) {
        self.layers = layers
        byID = Dictionary(layers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func sorted(_ l: [DesignLayer]) -> [DesignLayer] { l.sorted { ($0.order, $0.id) < ($1.order, $1.id) } }
        var k: [String: [DesignLayer]] = [:]
        var r: [DesignLayer] = []
        for l in layers {
            // A node whose parent is missing (detached) shows at the top level.
            if let p = l.parent, byID[p] != nil { k[p, default: []].append(l) } else { r.append(l) }
        }
        kids = k.mapValues(sorted)
        roots = sorted(r)
    }

    subscript(id: String) -> DesignLayer? { byID[id] }

    func children(of id: String?) -> [DesignLayer] { id.map { kids[$0] ?? [] } ?? roots }

    /// Rows top to bottom: a parent, then its children front first, when expanded. Bounded by the layer count and a depth cap.
    func rows(expanded: Set<String>) -> [LayerRow] {
        var out: [LayerRow] = []
        func walk(_ l: DesignLayer, _ depth: Int) {
            let k = kids[l.id] ?? []
            let open = expanded.contains(l.id)
            out.append(LayerRow(layer: l, depth: depth, hasChildren: !k.isEmpty, expanded: open))
            if open, depth < 64 { for c in k.reversed() { walk(c, depth + 1) } }
        }
        for l in roots.reversed() { walk(l, 0) }
        return out
    }

    /// Every ancestor of `id`, nearest first (for revealing a selection).
    func ancestors(of id: String) -> [String] {
        var out: [String] = []
        var cur = byID[id]?.parent
        while let p = cur, byID[p] != nil, out.count < 64 {
            out.append(p)
            cur = byID[p]?.parent
        }
        return out
    }

    func isInside(_ id: String, of ancestor: String) -> Bool { id == ancestor || ancestors(of: id).contains(ancestor) }

    /// Whether `id` may land at `drop`: never the page itself, never inside itself, never into a leaf.
    func canMove(_ id: String, _ drop: LayerDrop) -> Bool {
        guard let me = byID[id], me.type != "page" else { return false }
        switch drop {
        case .above(let t), .below(let t):
            guard let target = byID[t], t != id, target.parent != nil, !isInside(t, of: id) else { return false }
            return true
        case .into(let c):
            guard let c = byID[c], c.isContainer, c.id != id, !isInside(c.id, of: id) else { return false }
            return true
        }
    }

    /// The `move` ops (T12) that put `id` at `drop`, or nil when that is not allowed or nothing would change. Gives the one
    /// order `between` finds; when siblings ran out of room, renumbers them all in the same batch (one undo step).
    func moveOps(_ id: String, _ drop: LayerDrop) -> [[String: DJSON]]? {
        guard canMove(id, drop) else { return nil }
        let parent: String
        var index: Int  // position in the parent's ascending children without `id`
        switch drop {
        case .into(let c):
            parent = c
            index = children(of: c).filter { $0.id != id }.count
        case .above(let t), .below(let t):
            guard let target = byID[t], let p = target.parent else { return nil }
            parent = p
            let sibs = children(of: p).filter { $0.id != id }
            guard let at = sibs.firstIndex(where: { $0.id == t }) else { return nil }
            if case .above = drop { index = at + 1 } else { index = at }
        }
        let sibs = children(of: parent).filter { $0.id != id }
        let lo = index > 0 ? sibs[index - 1].order : nil
        let hi = index < sibs.count ? sibs[index].order : nil
        if byID[id]?.parent == parent, children(of: parent).firstIndex(where: { $0.id == id }) == index { return nil }
        if let o = FractionalOrder.between(lo, hi) { return [EditOps.move(id, parent: parent, order: o)] }
        guard let fresh = FractionalOrder.rebalance(sibs.count + 1) else { return nil }
        var ordered = sibs.map(\.id)
        ordered.insert(id, at: index)
        return zip(ordered, fresh).compactMap { sid, o in
            sid == id || byID[sid]?.order != o ? EditOps.move(sid, parent: parent, order: o) : nil
        }
    }

    /// Move one step toward the front (`up`) or the back among the same siblings: the keyboard and VoiceOver way to reorder.
    func step(_ id: String, up: Bool) -> [[String: DJSON]]? {
        guard let me = byID[id], let p = me.parent else { return nil }
        let sibs = children(of: p)
        guard let at = sibs.firstIndex(where: { $0.id == id }) else { return nil }
        let to = up ? at + 1 : at - 1
        guard sibs.indices.contains(to) else { return nil }
        return moveOps(id, up ? .above(sibs[to].id) : .below(sibs[to].id))
    }
}
