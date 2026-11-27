import CoreUI
import SwiftUI

/// Components, the app's way: a component is a node of its own type (T1), an instance names it as `<design>/<node>` and
/// follows it, `overrides` aside. Creating one turns a frame into a component in place; detaching turns an instance back
/// into a plain frame. Pure op lists, so the model's own rules (what a component holds, what an instance may carry) are
/// tested without an engine.
enum Components {
    /// The frame becomes a component: the same props and children (new ids), in the frame's place and order.
    static func create(
        _ id: String, doc: String, layers: LayerTree, node: (String) -> EditorNode?
    ) -> Arranged {
        guard let l = layers[id], l.type == "frame", let parent = l.parent else {
            return Arranged(why: "Select a frame to make it a component.")
        }
        guard let p = EditorClipboard.collect(ids: [id], doc: doc, layers: layers, node: node),
            p.nodes.count <= EditorClipboard.maxNodes,
            var r = EditorClipboard.ops(p, place: .init(parent: parent, lo: nil), sameDoc: true)
        else { return Arranged(why: EditorClipboard.tooBig) }
        r.ops[0]["type"] = .string("component")
        r.ops[0]["order"] = .string(l.order)
        r.ops.append(EditOps.delete(id))
        return Arranged(ops: r.ops, select: r.roots)
    }

    /// The component an instance names, when it is in this design.
    static func ownComponent(_ n: EditorNode, doc: String) -> String? {
        guard let ref = n.props["component"]?.string else { return nil }
        let parts = ref.split(separator: "/", maxSplits: 1).map(String.init)
        return parts.count == 2 && parts[0] == doc ? parts[1] : nil
    }

    /// `add` for an instance of `component` in `parent`, after `lo`, at (x, y): it carries only its place, so it follows the
    /// component's size and looks.
    static func instance(
        of component: DesignLayer, doc: String, parent: String, lo: String?, at p: (x: Double, y: Double),
        id: String = DesignOptions.nodeID()
    ) -> [String: DJSON]? {
        guard let order = FractionalOrder.between(lo, nil) else { return nil }
        return [
            "op": .string("add"), "id": .string(id), "type": .string("instance"), "parent": .string(parent),
            "order": .string(order), "name": .string(component.name),
            "props": .object(["component": .string("\(doc)/\(component.id)"), "x": .number(p.x), "y": .number(p.y)]),
        ]
    }

    /// Instances back to frames: the component's subtree (new ids) with the instance's own props and the overrides folded
    /// in, in the instance's place. An instance of a component from the design system cannot be detached here (its
    /// children are not in this design).
    static func detach(
        _ ids: [String], doc: String, layers: LayerTree, node: (String) -> EditorNode?
    ) -> Arranged {
        var out = Arranged()
        for id in ids {
            guard let inst = layers[id], inst.type == "instance", let n = node(id), let parent = inst.parent else {
                continue
            }
            guard let cid = ownComponent(n, doc: doc), layers[cid]?.type == "component" else {
                return Arranged(
                    why: "That instance follows a component from another design, so it cannot be detached here.")
            }
            guard let p = EditorClipboard.collect(ids: [cid], doc: doc, layers: layers, node: node),
                p.nodes.count <= EditorClipboard.maxNodes,
                var r = EditorClipboard.ops(p, place: .init(parent: parent, lo: nil), sameDoc: true)
            else { return Arranged(why: EditorClipboard.tooBig) }
            var rootProps = r.ops[0]["props"]?.object ?? [:]
            rootProps["x"] = nil
            rootProps["y"] = nil
            for (k, v) in n.props where k != "component" && k != "overrides" { rootProps[k] = v }
            r.ops[0]["type"] = .string("frame")
            r.ops[0]["order"] = .string(inst.order)
            if !n.name.isEmpty { r.ops[0]["name"] = .string(n.name) }
            r.ops[0]["props"] = .object(rootProps)
            // Overrides on the instance itself ("."), or on one child by its id.
            for (path, change) in n.props["overrides"]?.object ?? [:] {
                guard let m = change.object else { continue }
                let at = path == "." ? 0 : p.nodes.firstIndex { $0.id == path }
                guard let at else { continue }
                var props = r.ops[at]["props"]?.object ?? [:]
                for (k, v) in m {
                    if k == "text" { r.ops[at]["text"] = v } else { props[k] = v == .null ? nil : v }
                }
                r.ops[at]["props"] = .object(props)
            }
            guard out.ops.count + r.ops.count + 1 <= Arrange.maxOps else {
                return Arranged(why: "That is too much to detach at once.")
            }
            out.ops += r.ops + [EditOps.delete(id)]
            out.select += r.roots
        }
        return out.ops.isEmpty ? Arranged(why: "Select an instance to detach it.") : out
    }
}

extension DesignEditor {
    /// The components of this design, for the insert menu.
    var components: [DesignLayer] { layers.layers.filter { $0.type == "component" } }

    func createComponent() {
        guard let id = selection.first else { return notify("Select a frame to make it a component.") }
        run(Components.create(id, doc: doc, layers: layers, node: { node(of: $0) }))
    }

    func detachInstance() {
        run(Components.detach(selection, doc: doc, layers: layers, node: { node(of: $0) }))
    }

    /// Places an instance of `component`: inside the selected frame, else the first screen, else the page.
    @discardableResult
    func insertInstance(_ component: DesignLayer) -> Bool {
        guard attached else { return false }
        let picked = selection.first.flatMap { layers[$0] }
        var parent = (picked?.isContainer == true ? picked : picked?.parent.flatMap { layers[$0] })
        if parent?.type == "page" || parent == nil {
            parent = currentPage.flatMap { p in layers.children(of: p.id).first { $0.type == "frame" } } ?? currentPage
        }
        // Never inside the component itself: an instance of it there would repeat forever.
        if let p = parent, layers.isInside(p.id, of: component.id) { parent = currentPage }
        guard let p = parent else { return false }
        let sibs = layers.children(of: p.id)
        let step = Double(sibs.count % 10) * 24
        guard
            let op = Components.instance(
                of: component, doc: doc, parent: p.id, lo: sibs.last?.order, at: (40 + step, 40 + step)),
            apply([op]), let id = op["id"]?.string
        else { return false }
        selectMany([id])
        return true
    }
}

/// The Components menu next to Image in the canvas toolbar: this design's components, placed as instances.
struct ComponentsMenu: View {
    @Bindable var editor: DesignEditor

    var body: some View {
        Menu {
            let list = editor.components
            if list.isEmpty {
                Text("No components yet. Select a frame and press ⌥⌘K.")
            }
            ForEach(list.prefix(40)) { c in
                Button {
                    editor.insertInstance(c)
                } label: {
                    Label(c.title, systemImage: "diamond")
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "diamond").coreFont(size: MacTextSize.title).foregroundStyle(GlassInk.primary)
                Image(systemName: "chevron.down").coreFont(size: 9, weight: .semibold).foregroundStyle(
                    GlassInk.secondary)
            }
            .frame(height: MacSize.controlLg + Space.s1).padding(.horizontal, Space.s2)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .modifier(ToolHover())
        .help("Components: place an instance of one of this design's components")
        .accessibilityLabel("Components")
        .accessibilityIdentifier("design-components")
    }
}
