#if DEBUG
import Foundation

/// Debug only: drives every editor action against the real canvas (the engine behind `DesignEditBackend`) and reads back
/// what the engine holds. The snapshot walk runs it (`editor-selftest`) and prints one `SELFTEST` line per check, so an
/// audit sees the whole chain (chrome → edit ops → engine → tree/node) work, not just the views.
@MainActor
enum EditorSelfTest {
    static func run(_ e: DesignEditor, log: (String) -> Void) {
        var pass = 0
        var fail = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            if ok { pass += 1 } else { fail += 1 }
            log("SELFTEST \(ok ? "PASS" : "FAIL") \(name)\(ok ? "" : " — \(detail())") notice=\(e.notice ?? "-")")
        }
        func prop(_ key: String) -> DJSON? { e.node?.props[key] }

        check("canvas attached", e.attached)
        // Every preset goes in and is selected.
        for p in InsertPreset.frames.prefix(1) + InsertPreset.shapes + InsertPreset.texts {
            let before = e.layers.layers.count
            let ok = e.insert(p)
            let sel = e.selection.first.flatMap { e.layers[$0] }
            check(
                "insert \(p.id)", ok && e.layers.layers.count == before + 1 && sel?.type == p.type,
                "ok=\(ok) layers \(before)->\(e.layers.layers.count) sel=\(sel?.type ?? "none")")
        }

        // A rectangle: every inspector write reads back from the engine.
        guard e.insert(InsertPreset.shapes[0]), let rect = e.selection.first else {
            return log("SELFTEST ABORT no rect")
        }
        let writes: [(String, DJSON)] = [
            ("x", .number(24)), ("y", .number(32)), ("w", .number(210)), ("h", .number(90)), ("opacity", .number(0.5)),
            ("radius", .number(12)), ("blend", .string("multiply")), ("material", .string("glass")),
            ("fill", .array([InsertPreset.grey.array![0], InspectorIsland.gradient])),
            ("stroke", .object(["color": .string("#111111"), "width": .number(2)])),
            ("shadow", .array([InspectorIsland.shadow])),
            ("rotation", .number(30)), ("blur", .number(6)), ("backdrop_blur", .number(20)),
            ("sizing", .object(["w": .string("fill"), "h": .string("hug")])),
        ]
        for (k, v) in writes {
            e.set(k, v)
            e.reload()
            check("rect set \(k)", prop(k) == v, "got \(String(describing: prop(k)))")
        }
        // An inner shadow and a list of strokes (alignment, dash) are what the engine now takes.
        let inner = DJSON.object([
            "x": .number(0), "y": .number(2), "blur": .number(6), "color": .string("#00000040"), "inset": .bool(true),
        ])
        e.set("shadow", .array([InspectorIsland.shadow, inner]))
        e.reload()
        check("rect inner shadow", prop("shadow")?.array?.last == inner, "got \(String(describing: prop("shadow")))")
        let strokes: [DJSON] = [
            .object(["color": .string("#111111"), "width": .number(2), "align": .string("outside")]),
            .object([
                "color": .string("#ff0000"), "width": .number(1), "align": .string("center"),
                "dash": .array([.number(4), .number(2)]),
            ]),
        ]
        e.set("stroke", InspectorEdits.strokeValue(strokes))
        e.reload()
        check("rect two strokes", prop("stroke") == .array(strokes), "got \(String(describing: prop("stroke")))")
        e.set("blend", nil)
        e.reload()
        check("rect clear blend", prop("blend") == nil)
        e.setHidden(rect, true)
        e.reload()
        check("hide", e.layers[rect]?.hidden == true)
        e.setHidden(rect, false)
        e.reload()
        check("show", e.layers[rect]?.hidden == false)
        e.rename(rect, to: "Card background")
        e.reload()
        check("rename", e.layers[rect]?.name == "Card background")

        // Undo and redo walk the last change back and forth.
        e.undo()
        check("undo rename", e.layers[rect]?.name != "Card background")
        e.redo()
        check("redo rename", e.layers[rect]?.name == "Card background")

        // Reorder within the frame.
        if let parent = e.layers[rect]?.parent {
            let order = { e.layers.children(of: parent).map(\.id) }
            let before = order()
            e.step(rect, up: false)
            check("move backward", order() != before, "order unchanged")
            e.step(rect, up: true)
            check("move forward", order() == before, "order \(order()) vs \(before)")
        }

        // Text style.
        if e.insert(InsertPreset.texts[1]) {
            let t: DJSON = .object([
                "size": .number(20), "weight": .number(600), "line": .number(28), "tracking": .number(0.02),
                "align": .string("center"), "transform": .string("uppercase"),
            ])
            e.set("type", t)
            e.reload()
            check("text type", prop("type") == t, "got \(String(describing: prop("type")))")
        }

        // A frame: auto layout and clip.
        if e.insert(InsertPreset.frames[3]) {
            let l: DJSON = .object([
                "dir": .string("row"), "gap": .number(8), "pad": InspectorEdits.pad(16), "align": .string("center"),
                "justify": .string("between"),
            ])
            e.set("layout", l)
            e.set("clip", .bool(false))
            e.reload()
            check("frame layout", prop("layout") == l, "got \(String(describing: prop("layout")))")
            check("frame clip", prop("clip") == .bool(false))
            e.set("layout", nil)
            e.reload()
            check("frame layout off", prop("layout") == nil)
        }

        // Delete, then undo brings it back.
        let count = e.layers.layers.count
        e.delete(rect)
        check("delete", e.layers[rect] == nil && e.layers.layers.count == count - 1)
        e.undo()
        check("undo delete", e.layers[rect] != nil)

        // Selecting from the layers.
        check("select from layers", e.select(rect) && e.selection == [rect])
        log("SELFTEST DONE pass=\(pass) fail=\(fail)")
    }
}
#endif
