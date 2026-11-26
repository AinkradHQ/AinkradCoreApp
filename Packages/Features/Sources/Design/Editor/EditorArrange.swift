import Foundation

/// A node's frame in its parent: all four numbers must be plain values (a token or a missing number has no box).
struct NodeBox: Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
    var maxX: Double { x + w }
    var maxY: Double { y + h }

    init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    init?(_ n: EditorNode?) {
        guard let p = n?.props, let x = p["x"]?.double, let y = p["y"]?.double, let w = p["w"]?.double,
            let h = p["h"]?.double
        else { return nil }
        self.init(x: x, y: y, w: w, h: h)
    }

    static func union(_ boxes: [NodeBox]) -> NodeBox? {
        guard let f = boxes.first else { return nil }
        let minX = boxes.reduce(f.x) { min($0, $1.x) }
        let minY = boxes.reduce(f.y) { min($0, $1.y) }
        let maxX = boxes.reduce(f.maxX) { max($0, $1.maxX) }
        let maxY = boxes.reduce(f.maxY) { max($0, $1.maxY) }
        return NodeBox(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }
}

/// What an arrange command comes to: the ops to apply, the layers to select afterwards, or why it cannot be done.
struct Arranged: Equatable {
    var ops: [[String: DJSON]] = []
    var select: [String] = []
    var why: String?
}

/// Group, ungroup, z-order and select: the op lists, with no engine. A group is a frame at the layers' bounds, so they keep
/// their place on the canvas.
enum Arrange {
    static let maxOps = 200

    // MARK: group

    /// Wraps `ids` (siblings, never a page) in a frame at their bounds. The frame takes the front-most one's place, the
    /// layers keep their order inside it and their position on the canvas. `extra` are more props for the frame.
    static func group(
        _ ids: [String], layers: LayerTree, box: (String) -> NodeBox?, id: String = DesignOptions.nodeID(),
        extra: [String: DJSON] = [:]
    ) -> Arranged {
        let picked = ids.compactMap { layers[$0] }.filter { $0.type != "page" }
        guard let first = picked.first, let parent = first.parent else {
            return Arranged(why: "Select the layers to group first.")
        }
        guard picked.allSatisfy({ $0.parent == parent }) else {
            return Arranged(why: "Layers inside different frames cannot be grouped. Select layers in one frame.")
        }
        let sorted = picked.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
        guard 3 * sorted.count + 1 <= maxOps else { return Arranged(why: "That is too many layers to group at once.") }
        let boxes = sorted.compactMap { box($0.id) }
        guard boxes.count == sorted.count, let u = NodeBox.union(boxes) else {
            return Arranged(why: "Only layers with a set position and size can be grouped. Auto layout sets its own.")
        }
        guard let orders = FractionalOrder.rebalance(sorted.count), let top = sorted.last?.order else {
            return Arranged(why: "There is no room to group these layers.")
        }
        var props: [String: DJSON] = [
            "x": .number(u.x), "y": .number(u.y), "w": .number(u.w), "h": .number(u.h), "fill": .array([]),
        ]
        props.merge(extra) { _, new in new }
        var ops: [[String: DJSON]] = [
            [
                "op": .string("add"), "id": .string(id), "type": .string("frame"), "parent": .string(parent),
                "order": .string(top), "name": .string("Group"), "props": .object(props),
            ]
        ]
        for (l, o) in zip(sorted, orders) {
            ops.append(EditOps.move(l.id, parent: id, order: o))
            if let b = box(l.id) {
                ops.append(EditOps.set(l.id, "x", .number(b.x - u.x)))
                ops.append(EditOps.set(l.id, "y", .number(b.y - u.y)))
            }
        }
        return Arranged(ops: ops, select: [id])
    }

    // MARK: ungroup

    /// Takes the children out of each selected frame into the frame's parent, in the frame's place and order, and removes
    /// the frame. Positions follow the frame's own, so nothing moves on the canvas.
    static func ungroup(_ ids: [String], layers: LayerTree, box: (String) -> NodeBox?) -> Arranged {
        let frames = ids.compactMap { layers[$0] }.filter { $0.type == "frame" }
        guard !frames.isEmpty else { return Arranged(why: "Select a frame or group to ungroup it.") }
        var out = Arranged()
        for f in frames {
            guard let parent = f.parent, layers[parent]?.type != "page" else {
                return Arranged(why: "A screen cannot be ungrouped. Ungroup a frame inside it.")
            }
            let kids = layers.children(of: f.id)
            guard !kids.isEmpty else { return Arranged(why: "“\(f.title)” has nothing inside to ungroup.") }
            guard out.ops.count + 2 * kids.count + 1 <= maxOps else {
                return Arranged(why: "That is too many layers to ungroup at once.")
            }
            let sibs = layers.children(of: parent)
            let hi = sibs.first { ($0.order, $0.id) > (f.order, f.id) && $0.id != f.id }?.order
            let o = box(f.id)
            var lo: String? = f.order
            for k in kids {
                guard let n = FractionalOrder.between(lo, hi) else {
                    return Arranged(why: "There is no room to ungroup here.")
                }
                lo = n
                out.ops.append(EditOps.move(k.id, parent: parent, order: n))
                if let o, let b = box(k.id) {
                    out.ops.append(EditOps.set(k.id, "x", .number(b.x + o.x)))
                    out.ops.append(EditOps.set(k.id, "y", .number(b.y + o.y)))
                }
                out.select.append(k.id)
            }
            out.ops.append(EditOps.delete(f.id))
        }
        return out
    }

    // MARK: z-order

    enum ZMove { case forward, backward, front, back }

    /// The siblings (back to front) after the move; the selected ones keep their order among themselves.
    static func sequence(_ ids: [String], _ sel: Set<String>, _ move: ZMove) -> [String] {
        var s = ids
        switch move {
        case .front: return ids.filter { !sel.contains($0) } + ids.filter(sel.contains)
        case .back: return ids.filter(sel.contains) + ids.filter { !sel.contains($0) }
        case .forward:
            var i = s.count - 2
            while i >= 0 {
                if sel.contains(s[i]), !sel.contains(s[i + 1]) { s.swapAt(i, i + 1) }
                i -= 1
            }
        case .backward:
            var i = 1
            while i < s.count {
                if sel.contains(s[i]), !sel.contains(s[i - 1]) { s.swapAt(i, i - 1) }
                i += 1
            }
        }
        return s
    }

    /// `move` ops that put the selected layers where `move` says, among their siblings. Only the layers that changed place
    /// get an op; when the order ran out of room the siblings are renumbered in the same batch. Empty: nothing to do.
    static func zOrder(_ ids: [String], _ move: ZMove, layers: LayerTree) -> [[String: DJSON]] {
        let sel = Set(ids)
        let parents = Set(ids.compactMap { layers[$0] }.filter { $0.type != "page" }.compactMap(\.parent))
        var ops: [[String: DJSON]] = []
        for parent in parents.sorted() {
            let sibs = layers.children(of: parent)
            let chosen = Set(sibs.map(\.id)).intersection(sel)
            let before = sibs.map(\.id)
            let after = sequence(before, chosen, move)
            if after == before { continue }
            let order = Dictionary(uniqueKeysWithValues: sibs.map { ($0.id, $0.order) })
            var batch: [[String: DJSON]] = []
            var last: String?
            var ok = true
            for (i, id) in after.enumerated() {
                if !chosen.contains(id) {
                    last = order[id]
                    continue
                }
                let hi = after[(i + 1)...].first { !chosen.contains($0) }.flatMap { order[$0] }
                if let cur = order[id], cur > (last ?? ""), hi.map({ cur < $0 }) ?? true {
                    last = cur  // already fits in the gap
                    continue
                }
                guard let o = FractionalOrder.between(last, hi) else {
                    ok = false
                    break
                }
                batch.append(EditOps.move(id, parent: parent, order: o))
                last = o
            }
            if !ok, let fresh = FractionalOrder.rebalance(after.count) {
                batch = zip(after, fresh).compactMap { id, o in
                    order[id] == o ? nil : EditOps.move(id, parent: parent, order: o)
                }
            }
            ops += batch
        }
        return ops
    }

    // MARK: select

    /// ⌘A: the layers beside the selection (its parent's children), else the page's top level.
    static func selectAll(selection: [String], layers: LayerTree, page: String?) -> [String] {
        let parent = selection.first.flatMap { layers[$0] }.flatMap { $0.type == "page" ? nil : $0.parent } ?? page
        return layers.children(of: parent).filter { $0.type != "page" }.map(\.id)
    }

    /// ⏎: what is inside the selected containers; nil when none has anything inside.
    static func children(of selection: [String], layers: LayerTree) -> [String]? {
        let kids = selection.flatMap { layers.children(of: $0) }.map(\.id)
        return kids.isEmpty ? nil : kids
    }

    /// ⇧⏎: the parents of the selection, never a page; nil when there is none to go to.
    static func parents(of selection: [String], layers: LayerTree) -> [String]? {
        var seen = Set<String>()
        let ps = selection.compactMap { layers[$0]?.parent }.filter {
            layers[$0]?.type != "page" && seen.insert($0).inserted
        }
        return ps.isEmpty ? nil : ps
    }

    // MARK: auto layout

    /// Row when the layers sit side by side more than one under the other, else column.
    static func direction(_ boxes: [NodeBox]) -> String {
        let byX = boxes.sorted { $0.x < $1.x }
        let byY = boxes.sorted { $0.y < $1.y }
        func apart(_ s: [NodeBox], _ end: (NodeBox) -> Double, _ start: (NodeBox) -> Double) -> Int {
            zip(s, s.dropFirst()).filter { end($0) <= start($1) }.count
        }
        let across = apart(byX, \.maxX, \.x)
        let down = apart(byY, \.maxY, \.y)
        return across > down ? "row" : "column"
    }

    static func layout(direction: String) -> DJSON { .object(["dir": .string(direction), "gap": .number(8)]) }
}
