#if DEBUG
import AppKit
import DesignCanvas

/// Debug only (snapshot scene `tools-probe`): drives the real canvas view with the pointer and keys — every drawing
/// tool, the pen, the hand, text typing and double-click editing, the letter keys — and prints one `TOOLPROBE` line
/// per check with what the engine made.
@MainActor
enum ToolProbe {
    static func run(_ log: @escaping @MainActor (String) -> Void) async {
        guard let v = DesignMeasure.view else { return log("TOOLPROBE ABORT no canvas") }
        var pass = 0
        var fail = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if ok { pass += 1 } else { fail += 1 }
            log("TOOLPROBE \(ok ? "PASS" : "FAIL") \(name) \(detail)")
        }
        func nodes() -> [[String: Any]] {
            (v.editorTree().flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]]) ?? []
        }
        func node(_ id: String) -> [String: Any]? {
            v.editorNode(id).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any]
        }
        func drag(_ a: CGPoint, _ b: CGPoint, shift: Bool = false) async {
            v.measurePointer(down: true, at: a, shift: shift)
            for i in 1...8 {
                let t = CGFloat(i) / 8
                v.measurePointer(at: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), shift: shift)
                try? await Task.sleep(for: .milliseconds(16))
            }
            v.measurePointer(down: false, at: b, shift: shift)
            try? await Task.sleep(for: .milliseconds(100))
        }
        func click(_ p: CGPoint) async {
            v.measurePointer(down: true, at: p)
            v.measurePointer(down: false, at: p)
            try? await Task.sleep(for: .milliseconds(80))
        }
        func key(_ c: String, code: UInt16 = 0) {
            guard
                let e = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: v.window?.windowNumber ?? 0,
                    context: nil, characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: code)
            else { return }
            v.keyDown(with: e)
        }
        func made(_ before: Int, _ type: String) -> [String: Any]? {
            let all = nodes()
            guard all.count == before + 1, let id = v.editorSelection().first, let n = node(id),
                n["type"] as? String == type
            else { return nil }
            return n
        }

        v.window?.makeFirstResponder(v)
        let c = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
        // Drawing tools: drag draws one node of the kind, selects it, returns to Move.
        for (tool, type, a, b) in [
            (3, "rect", CGPoint(x: c.x - 160, y: c.y - 80), CGPoint(x: c.x - 60, y: c.y)),
            (4, "ellipse", CGPoint(x: c.x - 40, y: c.y - 80), CGPoint(x: c.x + 40, y: c.y)),
            (5, "vector", CGPoint(x: c.x + 60, y: c.y - 80), CGPoint(x: c.x + 160, y: c.y - 20)),
        ] {
            let before = nodes().count
            v.editorSetTool(tool)
            check("tool \(type) set", v.editorTool == tool, "tool=\(v.editorTool)")
            await drag(a, b)
            let n = made(before, type)
            let props = n?["props"] as? [String: Any]
            check(
                "drag draws \(type)", n != nil, "props=\(props.map { "\($0["w"] ?? "-")x\($0["h"] ?? "-")" } ?? "none")"
            )
            check("\(type) back to Move", v.editorTool == 0, "tool=\(v.editorTool)")
        }
        // Shift keeps a rectangle square.
        let before = nodes().count
        v.editorSetTool(3)
        await drag(CGPoint(x: c.x - 160, y: c.y + 40), CGPoint(x: c.x - 60, y: c.y + 70), shift: true)
        if let p = made(before, "rect")?["props"] as? [String: Any], let w = p["w"] as? Double,
            let h = p["h"] as? Double
        {
            check("shift square", abs(w - h) < 0.5, "\(w)x\(h)")
        } else {
            check("shift square", false, "no rect")
        }
        // Frame tool.
        let fb = nodes().count
        v.editorSetTool(2)
        await drag(CGPoint(x: c.x + 60, y: c.y + 20), CGPoint(x: c.x + 200, y: c.y + 120))
        check("drag draws frame", made(fb, "frame") != nil)
        // Text tool: click, type, Escape.
        let tb = nodes().count
        v.editorSetTool(6)
        await click(CGPoint(x: c.x - 160, y: c.y + 120))
        check("text tool opens editing", v.editorTextActive)
        v.insertText("Hello", replacementRange: NSRange(location: NSNotFound, length: 0))
        v.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        let tid = v.editorSelection().first
        check(
            "typed text kept", tid.flatMap(node)?["text"] as? String == "Hello" && nodes().count == tb + 1,
            "text=\(tid.flatMap(node)?["text"] ?? "nil")")
        check("escape ends editing", !v.editorTextActive)
        // Pen: three points and back to the first closes it.
        let pb = nodes().count
        v.editorSetTool(7)
        for p in [
            CGPoint(x: c.x, y: c.y + 140), CGPoint(x: c.x + 80, y: c.y + 140), CGPoint(x: c.x + 40, y: c.y + 200),
        ] {
            await click(p)
        }
        await click(CGPoint(x: c.x, y: c.y + 140))
        let pen = made(pb, "vector")
        let path = (pen?["props"] as? [String: Any])?["path"] as? String
        check("pen closed path", path?.hasSuffix("Z") == true, "path=\(path ?? "nil")")
        // Hand: a drag pans and draws nothing.
        let hb = nodes().count
        v.editorSetTool(1)
        await drag(c, CGPoint(x: c.x + 40, y: c.y + 40))
        check("hand draws nothing", nodes().count == hb && v.editorTool == 1)
        // Letter keys pick tools; Escape goes back to Move.
        key("r")
        check("key R", v.editorTool == 3)
        key("p")
        check("key P", v.editorTool == 7)
        key("\u{1b}", code: 53)
        check("escape to Move", v.editorTool == 0, "tool=\(v.editorTool)")
        log("TOOLPROBE DONE pass=\(pass) fail=\(fail)")
    }
}
#endif
