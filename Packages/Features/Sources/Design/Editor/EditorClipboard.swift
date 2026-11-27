import AppKit
import Foundation

/// One node as it travels on the pasteboard: what the engine lists about it (`de_node` plus its order).
struct ClipNode: Codable, Equatable {
    var id: String
    var type: String
    var parent: String?
    var order: String
    var name: String
    var props: [String: DJSON]
    var text: String?
}

/// Copied layers: the subtrees of `roots`, parents before children. JSON on the pasteboard, so it also pastes into another
/// design (new ids always).
struct ClipPayload: Codable, Equatable {
    var kind = "ainkrad.design.nodes"
    var version = 1
    var doc: String
    var roots: [String]
    var nodes: [ClipNode]
}

/// Pure clipboard work: layers to a payload, a payload to `add` ops with fresh ids. The edit ops the Core takes are capped
/// at 200 a batch, so a bigger copy is refused up front, in words.
enum EditorClipboard {
    static let maxNodes = 190
    static let tooBig = "That is too many layers to copy at once. Try fewer."

    /// The subtrees of `ids` (a layer inside another selected layer is not a root of its own), nil when a node cannot be
    /// read. Stops growing past `maxNodes + 1`, so a huge frame costs nothing.
    static func collect(
        ids: [String], doc: String, layers: LayerTree, node: (String) -> EditorNode?
    ) -> ClipPayload? {
        let picked = Set(ids)
        let roots = ids.filter { id in
            guard let l = layers[id], l.type != "page" else { return false }
            return !layers.ancestors(of: id).contains(where: picked.contains)
        }
        var nodes: [ClipNode] = []
        func walk(_ id: String) -> Bool {
            guard nodes.count <= maxNodes, let l = layers[id], let n = node(id) else { return false }
            nodes.append(
                ClipNode(
                    id: id, type: n.type, parent: l.parent, order: l.order, name: n.name, props: n.props,
                    text: n.type == "text" ? (n.text ?? "") : nil))
            for c in layers.children(of: id) where !walk(c.id) { return false }
            return true
        }
        for r in roots where !walk(r) {
            return nodes.count > maxNodes ? ClipPayload(doc: doc, roots: roots, nodes: nodes) : nil
        }
        return roots.isEmpty ? nil : ClipPayload(doc: doc, roots: roots, nodes: nodes)
    }

    /// Where a paste goes: into `parent`, after `lo` and before `hi` in its order, moved by `offset`.
    struct Place {
        var parent: String
        var lo: String?
        var hi: String? = nil
        var offset: (dx: Double, dy: Double) = (0, 0)
    }

    struct Pasted {
        var ops: [[String: DJSON]]
        var roots: [String]
    }

    /// `add` ops for every node with a fresh id, the roots in `place`. A prototype link keeps its target only when the
    /// target was copied too, or the paste stays in the design it came from. Nil: too many nodes, or no room in the order.
    static func ops(
        _ p: ClipPayload, place: Place, sameDoc: Bool, newID: () -> String = DesignOptions.nodeID
    ) -> Pasted? {
        guard !p.nodes.isEmpty, p.nodes.count <= maxNodes else { return nil }
        var fresh: [String: String] = [:]
        for n in p.nodes { fresh[n.id] = newID() }
        var lastRoot = place.lo
        var out: [[String: DJSON]] = []
        var roots: [String] = []
        for n in p.nodes {
            guard let id = fresh[n.id] else { return nil }
            var props = n.props
            if let to = props["link"]?["to"]?.string {
                if let mapped = fresh[to] {
                    var link = props["link"]?.object ?? [:]
                    link["to"] = .string(mapped)
                    props["link"] = .object(link)
                } else if !sameDoc {
                    props["link"] = nil
                }
            }
            let isRoot = p.roots.contains(n.id)
            let parent: String
            var order = n.order
            if isRoot {
                parent = place.parent
                guard let o = FractionalOrder.between(lastRoot, place.hi) else { return nil }
                order = o
                lastRoot = o
                roots.append(id)
                for (k, d) in [("x", place.offset.dx), ("y", place.offset.dy)] {
                    if d != 0, let v = props[k]?.double { props[k] = .number(v + d) }
                }
            } else {
                guard let q = n.parent, let mapped = fresh[q] else { return nil }
                parent = mapped
            }
            var op: [String: DJSON] = [
                "op": .string("add"), "id": .string(id), "type": .string(n.type), "parent": .string(parent),
                "order": .string(order), "name": .string(n.name), "props": .object(props),
            ]
            if n.type == "text" { op["text"] = .string(n.text ?? "") }
            out.append(op)
        }
        return Pasted(ops: out, roots: roots)
    }

    /// `x`/`y` of the topmost-left root, for placing a paste beside what is already there.
    static func origin(_ p: ClipPayload) -> (x: Double, y: Double)? {
        let xs = p.nodes.filter { p.roots.contains($0.id) }.compactMap { $0.props["x"]?.double }
        let ys = p.nodes.filter { p.roots.contains($0.id) }.compactMap { $0.props["y"]?.double }
        guard let x = xs.min(), let y = ys.min() else { return nil }
        return (x, y)
    }

    // MARK: pasteboard

    static let pasteboardType = NSPasteboard.PasteboardType("com.ainkrad.design.nodes")

    static func write(_ p: ClipPayload, to pb: NSPasteboard = .general) {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        guard let d = try? e.encode(p), let s = String(data: d, encoding: .utf8) else { return }
        pb.clearContents()
        pb.setData(d, forType: pasteboardType)
        pb.setString(s, forType: .string)
    }

    enum Content: Equatable {
        case nodes(ClipPayload)
        case text(String)
    }

    /// Our nodes (on their own type, or as JSON text), else plain text; nil when the pasteboard holds neither.
    static func read(from pb: NSPasteboard = .general) -> Content? {
        let d = JSONDecoder()
        if let data = pb.data(forType: pasteboardType), let p = try? d.decode(ClipPayload.self, from: data),
            valid(p)
        {
            return .nodes(p)
        }
        guard let s = pb.string(forType: .string), !s.isEmpty else { return nil }
        if let p = try? d.decode(ClipPayload.self, from: Data(s.utf8)), valid(p) { return .nodes(p) }
        return .text(String(s.prefix(10_000)))
    }

    /// Foreign JSON is hostile: our marker, a sane size, every id well formed, every root present.
    static func valid(_ p: ClipPayload) -> Bool {
        p.kind == "ainkrad.design.nodes" && p.version == 1 && !p.nodes.isEmpty && p.nodes.count <= maxNodes
            && p.nodes.allSatisfy { !$0.id.isEmpty && $0.id.count <= 128 && !$0.type.isEmpty }
            && p.roots.allSatisfy { r in p.nodes.contains { $0.id == r } }
    }
}

// MARK: editor

extension DesignEditor {
    /// The layer a paste lands in: the selected container, or the selected layer's parent; nothing selected: the page for
    /// frames, the first frame on the page for anything else.
    private func pasteParent(framesOnly: Bool) -> DesignLayer? {
        if let pick = selection.first.flatMap({ layers[$0] }) {
            let c = pick.isContainer ? pick : pick.parent.flatMap { layers[$0] }
            if let c, c.type != "page" { return c }
        }
        let page = currentPage
        if framesOnly { return page }
        return page.flatMap { p in layers.children(of: p.id).first { $0.type == "frame" } } ?? page
    }

    /// The page being shown.
    var currentPage: DesignLayer? {
        let p = pages
        return p.indices.contains(pageIndex) ? p[pageIndex] : p.first
    }

    /// Every page of the design, in order (the engine's page number is a place in this list).
    var pages: [DesignLayer] { layers.children(of: nil).filter { $0.type == "page" } }

    /// Copies the selected layers (and what is inside them) to the pasteboard. False when nothing could be copied.
    @discardableResult
    func copy() -> Bool {
        guard attached, !selection.isEmpty else { return false }
        guard
            let p = EditorClipboard.collect(ids: selection, doc: doc, layers: layers, node: { node(of: $0) }),
            p.nodes.count <= EditorClipboard.maxNodes
        else {
            notice = EditorClipboard.tooBig
            return false
        }
        EditorClipboard.write(p)
        notice = nil
        return true
    }

    func cut() {
        guard copy() else { return }
        let roots = selection.filter { layers[$0]?.type != "page" }
        apply(roots.map { EditOps.delete($0) })
    }

    /// Pastes what the pasteboard holds: copied layers (new ids, one undo step), or text as a text layer.
    @discardableResult
    func paste() -> Bool {
        guard attached, let content = EditorClipboard.read() else { return false }
        switch content {
        case .nodes(let p): return paste(p)
        case .text(let s): return pasteText(s)
        }
    }

    @discardableResult
    func paste(_ p: ClipPayload) -> Bool {
        let rootNodes = p.nodes.filter { p.roots.contains($0.id) }
        let framesOnly = rootNodes.allSatisfy { ["frame", "component"].contains($0.type) }
        guard let parent = pasteParent(framesOnly: framesOnly) else {
            notice = "There is nowhere to paste yet. Draw a frame first."
            return false
        }
        let siblings = layers.children(of: parent.id)
        let sameDoc = p.doc == doc
        var offset = (dx: 0.0, dy: 0.0)
        if parent.type == "page" {
            // Screens go to the right of the last one.
            let right = siblings.compactMap { s -> Double? in
                guard let n = node(of: s.id), let x = n.props["x"]?.double else { return nil }
                return x + (n.props["w"]?.double ?? 0)
            }.max()
            if let right, let o = EditorClipboard.origin(p) { offset = (right + 80 - o.x, -o.y) }
        } else if sameDoc, p.roots.contains(where: { r in p.nodes.first { $0.id == r }?.parent == parent.id }) {
            offset = (16, 16)  // beside the original, so it is seen
        }
        let place = EditorClipboard.Place(parent: parent.id, lo: siblings.last?.order, offset: offset)
        guard let r = EditorClipboard.ops(p, place: place, sameDoc: sameDoc) else {
            notice =
                p.nodes.count > EditorClipboard.maxNodes ? EditorClipboard.tooBig : "There is no room to paste here."
            return false
        }
        guard apply(r.ops) else { return false }
        selectMany(r.roots)
        return true
    }

    private func pasteText(_ s: String) -> Bool {
        guard let parent = pasteParent(framesOnly: false), parent.type != "page" else {
            notice = "Select a frame to paste text into."
            return false
        }
        let siblings = layers.children(of: parent.id)
        guard let order = FractionalOrder.between(siblings.last?.order, nil) else { return false }
        let body = InsertPreset.texts[1]
        var props = body.props
        let step = Double(siblings.count % 10) * 24
        props["x"] = .number(40 + step)
        props["y"] = .number(40 + step)
        props["w"] = .number(body.w)
        props["h"] = .number(body.h)
        let id = DesignOptions.nodeID()
        let words = String(s.prefix(2000))
        guard
            apply([
                [
                    "op": .string("add"), "id": .string(id), "type": .string("text"), "parent": .string(parent.id),
                    "order": .string(order), "name": .string(String(words.prefix(30))),
                    "props": .object(props), "text": .string(words),
                ]
            ])
        else { return false }
        selectMany([id])
        return true
    }

    /// A copy right above each selected layer, a little to the side; the copies become the selection. One undo step.
    @discardableResult
    func duplicate() -> Bool {
        guard attached, !selection.isEmpty else { return false }
        var ops: [[String: DJSON]] = []
        var made: [String] = []
        let byParent = Dictionary(grouping: selection.compactMap { layers[$0] }.filter { $0.type != "page" }) {
            $0.parent ?? ""
        }
        for (parentID, group) in byParent.sorted(by: { $0.key < $1.key }) {
            let ids = group.sorted { $0.order < $1.order }
            guard
                let p = EditorClipboard.collect(ids: ids.map(\.id), doc: doc, layers: layers, node: { node(of: $0) }),
                p.nodes.count <= EditorClipboard.maxNodes
            else {
                notice = EditorClipboard.tooBig
                return false
            }
            let sibs = layers.children(of: parentID)
            let top = ids.last?.order
            let hi = sibs.first { top != nil && $0.order > top! }?.order
            let place = EditorClipboard.Place(parent: parentID, lo: top, hi: hi, offset: (16, 16))
            guard let r = EditorClipboard.ops(p, place: place, sameDoc: true) else {
                notice = "There is no room to duplicate here."
                return false
            }
            ops += r.ops
            made += r.roots
        }
        guard !ops.isEmpty, apply(ops) else { return false }
        selectMany(made)
        return true
    }

    /// Selects several layers at once (false when the canvas does not have one of them yet).
    @discardableResult
    func selectMany(_ ids: [String]) -> Bool {
        guard let b = backend else { return false }
        let ok = b.select(ids)
        reload()
        return ok
    }
}
