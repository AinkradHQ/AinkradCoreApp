#if DEBUG
import AppKit
import Foundation

/// Debug only: the editor tools against the real engine (`tools-selftest` in the snapshot walk). Every command runs through
/// the editor, then the tree and nodes are read back from the engine, so the op lists are known to be ones the Core takes.
@MainActor
enum EditorToolsSelfTest {
    static func run(_ e: DesignEditor, log: (String) -> Void) {
        var pass = 0
        var fail = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            if ok { pass += 1 } else { fail += 1 }
            log("TOOLS \(ok ? "PASS" : "FAIL") \(name)\(ok ? "" : " — \(detail())") notice=\(e.notice ?? "-")")
        }
        func box(_ id: String) -> NodeBox? { NodeBox(e.node(of: id)) }
        func kids(_ id: String) -> [String] { e.layers.children(of: id).map(\.id) }
        func count(_ type: String) -> Int { e.layers.layers.filter { $0.type == type }.count }

        guard e.attached, e.insert(InsertPreset.frames[3]), let frame = e.selection.first else {
            return log("TOOLS ABORT no canvas")
        }
        e.insert(InsertPreset.shapes[0])
        let r = e.selection.first ?? ""
        e.insert(InsertPreset.shapes[1])
        let o = e.selection.first ?? ""
        e.insert(InsertPreset.texts[0])
        let t = e.selection.first ?? ""
        let three = [r, o, t]
        check("three layers in the frame", Set(kids(frame)) == Set(three), "\(kids(frame))")
        let before = three.map { box($0) }

        // Copy and paste (the engine's): three new layers in place, one undo step, ids fresh, JSON on the pasteboard.
        e.selectMany(three)
        let board = NSPasteboard.general
        let savedBoard = board.string(forType: .string)
        check("copy", e.copy())
        let clip = board.data(forType: EditorClipboard.pasteboardType)
        check("copy writes the engine's JSON", clip.flatMap(EditorClipboard.types) == ["rect", "ellipse", "text"])
        let n0 = e.layers.layers.count
        check(
            "paste", e.paste() && e.layers.layers.count == n0 + 3 && e.selection.count == 3,
            "n=\(e.layers.layers.count)")
        check("paste is new ids", Set(e.selection).isDisjoint(with: three))
        check(
            "paste keeps its place",
            Set(e.selection.compactMap { box($0) }.map(\.x)) == Set(before.compactMap { $0?.x }))
        e.undo()
        check("paste is one undo step", e.layers.layers.count == n0, "n=\(e.layers.layers.count)")
        e.redo()
        check("redo paste", e.layers.layers.count == n0 + 3)
        e.undo()

        // Cross-design paste: the same JSON from another design.
        if var obj = clip.flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any] {
            obj["doc"] = "dd_elsewhere"
            if let d = try? JSONSerialization.data(withJSONObject: obj) {
                e.select(frame)
                check("paste from another design", e.paste(d) && e.layers.layers.count == n0 + 3)
                e.undo()
            }
        }
        // Plain text becomes a text layer.
        board.clearContents()
        board.setString("Pasted words", forType: .string)
        e.select(frame)
        check("paste plain text", e.paste() && e.node(of: e.selection.first ?? "")?.text == "Pasted words")
        e.undo()
        board.clearContents()
        if let savedBoard { board.setString(savedBoard, forType: .string) }

        // Duplicate.
        e.selectMany([r])
        check("duplicate", e.duplicate() && e.layers.layers.count == n0 + 1 && e.selection != [r])
        e.undo()

        // Group and ungroup keep every position; each is one undo step.
        e.selectMany(three)
        e.group()
        check("group", e.selection.count == 1 && e.layers[e.selection[0]]?.type == "frame", "sel=\(e.selection)")
        let g = e.selection.first ?? ""
        check("group holds the three", Set(kids(g)) == Set(three), "\(kids(g))")
        let g0 = box(g)
        let inGroup = three.map { id in box(id).flatMap { b in g0.map { (b.x + $0.x, b.y + $0.y) } } }
        check(
            "group keeps positions",
            zip(inGroup, before).allSatisfy { $0?.0 == $1?.x && $0?.1 == $1?.y }, "\(inGroup) vs \(before)")
        e.ungroup()
        check("ungroup", Set(e.selection) == Set(three) && e.layers[g] == nil, "sel=\(e.selection)")
        check("ungroup keeps positions", three.map { box($0) } == before)
        e.undo()
        check("ungroup is one undo step", e.layers[g] != nil)
        e.undo()
        check("group is one undo step", e.layers[g] == nil && Set(kids(frame)) == Set(three))

        // Rotation and lock: written, read back from the engine's tree.
        e.select(r)
        e.set("rotation", .number(30))
        check("rotate", e.node(of: r)?.props["rotation"] == .number(30) && e.layers[r]?.rotation == 30)
        e.set("rotation", nil)
        check("rotation cleared", e.layers[r]?.rotation == 0)
        e.toggleLock()
        check("lock", e.layers[r]?.locked == true && e.node(of: r)?.props["locked"] == .bool(true))
        e.toggleLock()
        check("unlock", e.layers[r]?.locked == false)
        e.undo()
        e.undo()

        // Z-order.
        e.select(r)
        e.zOrder(.front)
        check("bring to front", kids(frame).last == r, "\(kids(frame))")
        e.zOrder(.back)
        check("send to back", kids(frame).first == r, "\(kids(frame))")
        e.zOrder(.forward)
        check("bring forward", kids(frame).first != r && kids(frame).last != r, "\(kids(frame))")

        // Select all / children / parent.
        e.select(r)
        e.selectAll()
        check("select all", Set(e.selection) == Set(kids(frame)))
        e.select(frame)
        check("enter selects children", e.perform(.selectChildren) && Set(e.selection) == Set(kids(frame)))
        check("shift-enter selects the parent", e.perform(.selectParent) && e.selection == [frame])

        // Hide and show.
        e.select(r)
        e.toggleHidden()
        check("hide", e.layers[r]?.hidden == true)
        e.toggleHidden()
        check("show", e.layers[r]?.hidden == false)

        // Auto layout on a frame.
        e.select(frame)
        e.addAutoLayout()
        check("auto layout", e.node(of: frame)?.hasLayout == true)
        e.undo()

        // Components: create, instance, detach (the engine's calls).
        let comps = count("component")
        e.select(frame)
        e.createComponent()
        let comp = e.selection.first ?? ""
        check(
            "create component",
            count("component") == comps + 1 && e.layers[comp]?.type == "component" && e.layers[frame] == nil,
            "sel=\(e.selection)")
        check("component keeps its children", kids(comp).count == 3, "\(kids(comp))")
        if let c = e.layers[comp] {
            check("insert instance", e.insertInstance(c) && e.layers[e.selection.first ?? ""]?.type == "instance")
            let inst = e.selection.first ?? ""
            check(
                "instance names the component",
                e.node(of: inst)?.props["component"]?.string == "\(e.doc)/\(comp)",
                "\(String(describing: e.node(of: inst)?.props["component"]))")
            e.detachInstance()
            let d = e.selection.first ?? ""
            check("detach", e.layers[inst] == nil && e.layers[d]?.type == "frame" && kids(d).count == 3, "\(kids(d))")
            e.undo()
            check("detach is one undo step", e.layers[inst] != nil)
        }

        // Pages: add, show, rename target, delete (and undo).
        let pages0 = e.pages.count
        e.addPage()
        check(
            "add page", e.pages.count == pages0 + 1 && e.pageIndex == pages0, "pages=\(e.pages.count) at \(e.pageIndex)"
        )
        e.insert(InsertPreset.frames[3])
        check("a frame goes on the shown page", e.layers[e.selection.first ?? ""]?.parent == e.currentPage?.id)
        e.showPage(0)
        check("show first page", e.pageIndex == 0 && e.selection.isEmpty)
        e.deletePage(e.pages[pages0].id)
        check("delete page", e.pages.count == pages0)
        e.undo()
        check("undo delete page", e.pages.count == pages0 + 1)
        log("TOOLS DONE pass=\(pass) fail=\(fail)")
    }
}
#endif
