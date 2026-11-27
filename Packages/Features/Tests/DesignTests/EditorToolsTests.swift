import AppKit
import Foundation
import Testing

@testable import Design

private func layer(
    _ id: String, _ type: String = "rect", _ parent: String? = "f", _ order: String = "i", name: String = ""
)
    -> DesignLayer
{
    DesignLayer(id: id, type: type, parent: parent, order: order, name: name)
}

private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ extra: [String: DJSON] = [:]) -> [String: DJSON]
{
    ["x": .number(x), "y": .number(y), "w": .number(w), "h": .number(h)].merging(extra) { _, n in n }
}

/// Page `p` > frame `f` > a (back), b, c (front) and a frame `g` holding t.
private let layers = LayerTree([
    layer("p", "page", nil, "i"), layer("f", "frame", "p", "i"), layer("a", "rect", "f", "d"),
    layer("b", "rect", "f", "i"), layer("c", "text", "f", "r"), layer("g", "frame", "f", "w"),
    layer("t", "rect", "g", "i"),
])

private let nodes: [String: EditorNode] = [
    "f": EditorNode(id: "f", type: "frame", props: rect(0, 0, 400, 400)),
    "a": EditorNode(id: "a", type: "rect", name: "A", props: rect(10, 20, 50, 40)),
    "b": EditorNode(id: "b", type: "rect", name: "B", props: rect(100, 30, 60, 60)),
    "c": EditorNode(id: "c", type: "text", name: "C", props: rect(5, 200, 80, 20), text: "Hello"),
    "g": EditorNode(id: "g", type: "frame", name: "G", props: rect(200, 100, 120, 120)),
    "t": EditorNode(id: "t", type: "rect", name: "T", props: rect(10, 10, 20, 20)),
]

@Suite struct ClipboardTests {
    private let clip = Data(
        #"{"format":"ainkrad-design/1","doc":"dd_1","nodes":[{"type":"frame","name":"A","props":{},"at":[0,0],"children":[]},{"type":"rect","name":"B","props":{},"at":[1,1],"children":[]}]}"#
            .utf8)

    @Test func theClipboardIsTheEnginesJSONAndNothingElse() {
        #expect(EditorClipboard.types(clip) == ["frame", "rect"])
        #expect(EditorClipboard.types(Data("hello".utf8)) == nil)
        #expect(EditorClipboard.types(Data(#"{"format":"other/1","nodes":[{"type":"rect"}]}"#.utf8)) == nil)
        #expect(EditorClipboard.types(Data(#"{"format":"ainkrad-design/1","nodes":[]}"#.utf8)) == nil)
    }

    @Test func thePasteboardKeepsItsTypeAndPlainTextPasteWorks() {
        let pb = NSPasteboard(name: NSPasteboard.Name("design-test-\(UUID().uuidString)"))
        EditorClipboard.write(clip, to: pb)
        #expect(pb.data(forType: EditorClipboard.pasteboardType) == clip)
        #expect(EditorClipboard.read(from: pb) == .nodes(clip))
        pb.clearContents()
        pb.setString(String(decoding: clip, as: UTF8.self), forType: .string)  // as JSON text: still ours
        #expect(EditorClipboard.read(from: pb) == .nodes(clip))
        pb.clearContents()
        pb.setString("Hello there", forType: .string)
        #expect(EditorClipboard.read(from: pb) == .text("Hello there"))
        pb.clearContents()
        #expect(EditorClipboard.read(from: pb) == nil)
    }
}

@Suite struct ArrangeTests {
    private func box(_ id: String) -> NodeBox? { NodeBox(nodes[id]) }

    @Test func groupWrapsAtTheBoundsAndKeepsEveryVisualPosition() throws {
        let a = Arrange.group(["b", "a"], layers: layers, box: box, id: "n_group")
        #expect(a.why == nil && a.select == ["n_group"])
        let add = a.ops[0]
        #expect(add["op"] == .string("add") && add["type"] == .string("frame") && add["parent"] == .string("f"))
        #expect(add["order"] == .string("i"))  // the front-most one's place
        let p = try #require(add["props"])
        #expect(p["x"] == .number(10) && p["y"] == .number(20) && p["w"] == .number(150) && p["h"] == .number(70))
        #expect(p["fill"] == .array([]))
        // a (back) then b inside, each moved by the group's corner
        #expect(a.ops[1]["id"] == .string("a") && a.ops[1]["parent"] == .string("n_group"))
        #expect(a.ops[2] == EditOps.set("a", "x", .number(0)) && a.ops[3] == EditOps.set("a", "y", .number(0)))
        #expect(a.ops[4]["id"] == .string("b") && a.ops[5] == EditOps.set("b", "x", .number(90)))
        #expect(a.ops[6] == EditOps.set("b", "y", .number(10)))
        let o1 = try #require(a.ops[1]["order"]?.string)
        let o2 = try #require(a.ops[4]["order"]?.string)
        #expect(o1 < o2 && EditOps.json(a.ops) != nil)
    }

    @Test func groupSaysWhyInWords() {
        #expect(Arrange.group([], layers: layers, box: box).why != nil)
        #expect(Arrange.group(["a", "t"], layers: layers, box: box).why?.contains("different frames") == true)
        #expect(Arrange.group(["a"], layers: layers, box: { _ in nil }).why?.contains("position and size") == true)
        #expect(Arrange.group(["p"], layers: layers, box: box).why != nil)
    }

    @Test func autoLayoutGuessesTheDirection() {
        let row = [
            NodeBox(x: 0, y: 0, w: 10, h: 10), NodeBox(x: 20, y: 2, w: 10, h: 10), NodeBox(x: 40, y: 0, w: 10, h: 10),
        ]
        let col = [
            NodeBox(x: 0, y: 0, w: 10, h: 10), NodeBox(x: 3, y: 20, w: 10, h: 10), NodeBox(x: 0, y: 40, w: 10, h: 10),
        ]
        #expect(
            Arrange.direction(row) == "row" && Arrange.direction(col) == "column" && Arrange.direction([]) == "column")
        let l = Arrange.layout(direction: "row")
        #expect(l["dir"] == .string("row") && l["gap"] == .number(8))
    }

    @Test func selectKeysWalkTheTree() {
        #expect(Arrange.selectAll(selection: ["b"], layers: layers, page: "p") == ["g", "c", "b", "a"].reversed())
        #expect(Arrange.selectAll(selection: [], layers: layers, page: "p") == ["f"])
        #expect(
            Arrange.children(of: ["g"], layers: layers) == ["t"] && Arrange.children(of: ["a"], layers: layers) == nil)
        #expect(Arrange.parents(of: ["t"], layers: layers) == ["g"])
        #expect(Arrange.parents(of: ["f"], layers: layers) == nil)  // the page is not a parent to select
        #expect(Arrange.parents(of: ["a", "b"], layers: layers) == ["f"])
    }
}

@Suite struct ZOrderTests {
    // a d, b i, c r, g w (back to front)
    @Test func sequencesMoveTheSelectedBlock() {
        let all = ["a", "b", "c", "d"]
        #expect(Arrange.sequence(all, ["b"], .forward) == ["a", "c", "b", "d"])
        #expect(Arrange.sequence(all, ["b", "c"], .forward) == ["a", "d", "b", "c"])
        #expect(Arrange.sequence(all, ["d"], .forward) == all)  // already in front
        #expect(Arrange.sequence(all, ["c"], .backward) == ["a", "c", "b", "d"])
        #expect(Arrange.sequence(all, ["a"], .backward) == all)
        #expect(Arrange.sequence(all, ["a", "c"], .front) == ["b", "d", "a", "c"])
        #expect(Arrange.sequence(all, ["b", "d"], .back) == ["b", "d", "a", "c"])
        #expect(Arrange.sequence(all, ["a", "c"], .forward) == ["b", "a", "d", "c"])
    }

    @Test func bringForwardWritesOneMoveBetweenTheNewNeighbours() throws {
        let ops = Arrange.zOrder(["b"], .forward, layers: layers)  // b over c
        #expect(ops.count == 1 && ops[0]["id"] == .string("b") && ops[0]["parent"] == .string("f"))
        let o = try #require(ops[0]["order"]?.string)
        #expect(o > "r" && o < "w" && FractionalOrder.isOrder(o))
    }

    @Test func toFrontAndToBack() throws {
        let front = Arrange.zOrder(["a"], .front, layers: layers)
        #expect(try #require(front[0]["order"]?.string) > "w")
        let back = Arrange.zOrder(["g"], .back, layers: layers)
        #expect(try #require(back[0]["order"]?.string) < "d")
    }

    @Test func nothingToDoWritesNothing() {
        #expect(Arrange.zOrder(["g"], .front, layers: layers).isEmpty)
        #expect(Arrange.zOrder(["a"], .back, layers: layers).isEmpty)
        #expect(Arrange.zOrder(["p"], .front, layers: layers).isEmpty)  // pages have no stack
    }

    @Test func aSelectionInTwoFramesMovesEachInItsOwn() {
        let ops = Arrange.zOrder(["a", "t"], .front, layers: layers)
        let parents = Set(ops.compactMap { $0["parent"]?.string })
        #expect(parents == ["f"])  // t is alone in g: already in front, so only a moves
        #expect(ops.count == 1)
    }

    @Test func whenTheOrderRunsOutTheSiblingsAreRenumbered() {
        let tight = LayerTree([
            layer("p", "page", nil), layer("f", "frame", "p"), layer("a", "rect", "f", "a"),
            layer("b", "rect", "f", "a1"), layer("c", "rect", "f", String(repeating: "z", count: 32)),
        ])
        let ops = Arrange.zOrder(["c"], .back, layers: tight)
        #expect(!ops.isEmpty && ops.allSatisfy { FractionalOrder.isOrder($0["order"]?.string ?? "") })
        let final = Dictionary(
            uniqueKeysWithValues: ["a", "b", "c"].map { id in
                (id, ops.first { $0["id"]?.string == id }?["order"]?.string ?? tight[id]!.order)
            })
        #expect(final["c"]! < final["a"]! && final["a"]! < final["b"]!)
    }
}

/// Group, ungroup, components, copy, paste and lock go to the engine in one call each (the engine's own tests cover the
/// geometry); the editor's part is what it asks for, what it says when the engine says no, and what it reloads.
@MainActor
@Suite struct EngineCallTests {
    private func make() -> (DesignEditor, FakeBackend) {
        let b = FakeBackend()
        b.treeJSON = """
            [{"id":"p","type":"page","parent":null,"order":"i","name":"Page"},
             {"id":"f","type":"frame","parent":"p","order":"i","name":"Card"},
             {"id":"g","type":"frame","parent":"f","order":"i","name":"Group"},
             {"id":"a","type":"rect","parent":"f","order":"r","name":"A","locked":true,"rotation":30},
             {"id":"i","type":"instance","parent":"f","order":"w","name":"Inst"}]
            """
        let e = DesignEditor(doc: "dd_1")
        e.attach(b)
        return (e, b)
    }

    @Test func groupUngroupAndComponentsAreOneEngineCallEach() {
        let (e, b) = make()
        b.sel = ["a", "g"]
        e.reload()
        e.perform(.group)
        e.perform(.ungroup)
        e.perform(.createComponent)
        b.sel = ["i"]
        e.reload()
        e.perform(.detachInstance)
        #expect(b.calls == ["group", "ungroup", "createComponent", "detachInstance"])
        #expect(b.edits.isEmpty)  // no op list from the app
        #expect(e.notice == nil)
    }

    @Test func whenTheEngineSaysNoTheEditorSaysWhy() {
        let (e, b) = make()
        b.engineOK = false
        b.sel = ["a", "g"]
        e.reload()
        e.group()
        #expect(e.notice?.contains("different frames") == true)
        e.ungroup()
        #expect(e.notice?.contains("Ungroup a frame") == true)
        e.createComponent()
        #expect(e.notice?.contains("page") == true)
        b.sel = []
        e.reload()
        e.group()
        #expect(e.notice == "Select the layers to group first.")
        e.detachInstance()
        #expect(e.notice == "Select an instance to detach it.")
    }

    @Test func anInstanceIsPlacedByTheComponentsReference() {
        let (e, b) = make()
        #expect(e.insertInstance(DesignLayer(id: "k", type: "component", parent: "p", order: "i")))
        #expect(b.calls == ["instance dd_1/k"])
    }

    @Test func anInstanceThatLandedInsideItsOwnComponentIsUndoneAndPlacedBeside() {
        let (e, b) = make()
        b.treeJSON =
            String(b.treeJSON.dropLast()) + #",{"id":"k","type":"component","parent":"p","order":"m","name":"Btn"}]"#
        b.nodes["k"] =
            #"{"id":"k","type":"component","parent":"p","order":"m","name":"Btn","props":{"x":100,"y":50,"w":200,"h":80}}"#
        b.instanceParent = "k"
        e.reload()
        #expect(e.insertInstance(DesignLayer(id: "k", type: "component", parent: "p", order: "m")))
        // beside it: right edge 300 + 40 gap, top 50, in view points at zoom 2 with pan (10, 20)
        #expect(b.calls == ["instance dd_1/k", "instance dd_1/k at 690,120"])
        #expect(b.edits.contains("undo") && e.layers["n_inst"]?.parent == "p")
    }

    @Test func copyPutsTheEnginesJSONOnThePasteboardAndPasteTakesItBack() {
        let (e, b) = make()
        b.sel = ["a"]
        e.reload()
        b.clip = Data(#"{"format":"ainkrad-design/1","doc":"dd_1","nodes":[{"type":"rect"}]}"#.utf8)
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        defer {
            pb.clearContents()
            if let saved { pb.setString(saved, forType: .string) }
        }
        #expect(e.copy())
        #expect(pb.data(forType: EditorClipboard.pasteboardType) == b.clip)
        b.sel = ["f"]
        e.reload()  // a frame is selected: it goes in, where it was
        #expect(e.paste())
        #expect(b.calls == ["copy", "paste into f"])
        b.sel = []
        e.reload()  // nothing selected: a rectangle goes in the first frame
        b.calls = []
        #expect(e.paste() && b.calls == ["paste into f"])
        b.clip = nil
        b.sel = ["p"]
        e.reload()
        #expect(!e.copy() && e.notice == "A page cannot be copied.")
    }

    @Test func screensArePastedOnThePageWhereTheCanvasIsLooking() {
        let (e, b) = make()
        #expect(e.paste(Data(#"{"format":"ainkrad-design/1","nodes":[{"type":"frame"}]}"#.utf8)))
        #expect(b.calls == ["paste on the page at the centre"])
    }

    @Test func lockReadsTheTreeAndWritesTheProp() {
        let (e, b) = make()
        #expect(e.layers["a"]?.locked == true && e.layers["a"]?.rotation == 30 && e.layers["g"]?.locked == false)
        b.sel = ["a"]
        e.reload()
        e.reload()
        e.perform(.toggleLock)  // all locked: unlock
        #expect(b.edits.last?.contains("\"locked\"") == true && b.edits.last?.contains("true") == false)
        b.sel = ["a", "g"]
        e.reload()
        e.perform(.toggleLock)  // a mix: lock
        #expect(b.edits.last?.contains("true") == true)
        e.setLocked(["g"], true)
        #expect(b.edits.last?.contains("\"g\"") == true)
        b.sel = []
        e.reload()
        e.reload()
        #expect(!e.canPerform(.toggleLock).ok && e.canPerform(.toggleLock).why == "Select a layer first.")
    }
}

@Suite struct InspectorEffectEditTests {
    private func node(_ stroke: DJSON?) -> EditorNode {
        EditorNode(id: "n", type: "rect", props: stroke.map { ["stroke": $0] } ?? [:])
    }

    @Test func strokesAreAListWhetherStoredAsOneObjectOrMany() {
        let one = DJSON.object(["color": .string("#111111"), "width": .number(2)])
        #expect(InspectorEdits.strokes(node(nil)).isEmpty)
        #expect(InspectorEdits.strokes(node(one)) == [one])
        #expect(InspectorEdits.strokes(node(.array([one, one]))).count == 2)
        #expect(InspectorEdits.strokeValue([]) == nil)
        #expect(InspectorEdits.strokeValue([one]) == one)  // one stays an object, as the Core's AI writes it
        #expect(InspectorEdits.strokeValue([one, one]) == .array([one, one]))
        #expect(InspectorEdits.maxStrokes == 8)
    }

    @Test func oneStrokeChangesWithoutTouchingTheOthers() {
        let a = DJSON.object(["color": .string("#111111"), "width": .number(2)])
        let b = DJSON.object(["color": .string("#ff0000"), "width": .number(4)])
        let next = InspectorEdits.stroking([a, b], 1, "align", .string("outside"))
        #expect(next[0] == a && next[1]["align"] == .string("outside") && next[1]["width"] == .number(4))
        #expect(InspectorEdits.stroking(next, 1, "align", nil)[1]["align"] == nil)
        #expect(InspectorEdits.stroking([a], 3, "width", .number(1)) == [a])
    }

    @Test func dashesAreNamedByTheirShape() {
        #expect(InspectorEdits.dash("solid", width: 2) == nil)
        let dashed = InspectorEdits.dash("dashed", width: 2)
        let dotted = InspectorEdits.dash("dotted", width: 2)
        #expect(dashed == .array([.number(8), .number(4)]) && dotted == .array([.number(2), .number(4)]))
        func name(_ d: DJSON?, _ w: Double) -> String {
            InspectorEdits.dashName(.object(["width": .number(w), "dash": d ?? .null]))
        }
        #expect(name(dashed, 2) == "dashed" && name(dotted, 2) == "dotted" && name(nil, 2) == "solid")
    }

    @Test func anInnerShadowIsAShadowWithInset() {
        #expect(InspectorEdits.isInset(.object(["inset": .bool(true)])))
        #expect(!InspectorEdits.isInset(InspectorIsland.shadow))
    }
}

@Suite struct ScrubTests {
    @Test func draggingChangesByOnePerPointAndTenWithShift() {
        #expect(Scrub.value(start: 100, dx: 5, shift: false) == 105)
        #expect(Scrub.value(start: 100, dx: -7.4, shift: false) == 93)
        #expect(Scrub.value(start: 100, dx: 5, shift: true) == 150)
        #expect(Scrub.value(start: 0.5, dx: 2, shift: false) == 2.5)
    }

    @Test func arrowsStepByOneAndTen() {
        #expect(Scrub.step(10, up: true, shift: false) == 11 && Scrub.step(10, up: false, shift: false) == 9)
        #expect(Scrub.step(10, up: true, shift: true) == 20 && Scrub.step(3, up: false, shift: true) == -7)
        #expect(Scrub.step(0.1, up: true, shift: false) == 1.1)  // no float noise
    }

    @Test func fontFamiliesAreWhatTheModelAccepts() {
        #expect(FontChoice.family("Lanterna Serif Bold.ttf") == "Lanterna Serif Bold")
        #expect(FontChoice.family("Harbor/Sans_2-b!") == "Harbor Sans_2-b")
        #expect(FontChoice.family("🙂🙂") == "Font")
        #expect(FontChoice.family(String(repeating: "a", count: 300)).count == 100)
        #expect(FontChoice.value(sha: nil) == .string("system"))
        let v = FontChoice.value(sha: String(repeating: "a", count: 64), name: "Harbor Sans.otf")
        #expect(v["asset"] == .string(String(repeating: "a", count: 64)) && v["family"] == .string("Harbor Sans"))
        #expect(
            FontChoice.sha(of: v) == String(repeating: "a", count: 64) && FontChoice.sha(of: .string("system")) == nil)
    }
}

@Suite struct ZoomAndKeysTests {
    @Test func zoomStepsGoToTheNextStop() {
        #expect(ZoomSteps.next(1, up: true) == 2 && ZoomSteps.next(1, up: false) == 0.5)
        #expect(ZoomSteps.next(0.7, up: true) == 1 && ZoomSteps.next(0.7, up: false) == 0.5)
        #expect(ZoomSteps.next(32, up: true) == 32 && ZoomSteps.next(0.0625, up: false) == 0.0625)
        #expect(
            ZoomSteps.percent(1) == "100%" && ZoomSteps.percent(0.125) == "12.5%" && ZoomSteps.percent(2.5) == "250%")
    }

    private func k(_ c: String, _ code: UInt16, cmd: Bool = false, shift: Bool = false, opt: Bool = false) -> EditorKey
    {
        EditorKey(chars: c, keyCode: code, command: cmd, shift: shift, option: opt)
    }

    @Test func theKeyMapIsFigmas() {
        #expect(EditorCommand.from(k("c", 8, cmd: true)) == .copy && EditorCommand.from(k("x", 7, cmd: true)) == .cut)
        #expect(
            EditorCommand.from(k("v", 9, cmd: true)) == .paste && EditorCommand.from(k("d", 2, cmd: true)) == .duplicate
        )
        #expect(EditorCommand.from(k("g", 5, cmd: true)) == .group)
        #expect(EditorCommand.from(k("g", 5, cmd: true, shift: true)) == .ungroup)
        #expect(
            EditorCommand.from(k("]", 30, cmd: true)) == .bringForward
                && EditorCommand.from(k("[", 33, cmd: true)) == .sendBackward)
        #expect(EditorCommand.from(k("]", 30, cmd: true, opt: true)) == .bringToFront)
        #expect(EditorCommand.from(k("[", 33, cmd: true, opt: true)) == .sendToBack)
        #expect(EditorCommand.from(k("a", 0, cmd: true)) == .selectAll)
        #expect(EditorCommand.from(k("k", 40, cmd: true, opt: true)) == .createComponent)
        #expect(EditorCommand.from(k("a", 0, shift: true)) == .autoLayout)
        #expect(EditorCommand.from(k("h", 4, cmd: true, shift: true)) == .toggleHidden)
        #expect(EditorCommand.from(k("l", 37, cmd: true, shift: true)) == .toggleLock)
        #expect(EditorCommand.from(k("r", 15, cmd: true)) == .renameLayer)
        #expect(
            EditorCommand.from(k("0", 29, cmd: true)) == .zoom100
                && EditorCommand.from(k("=", 24, cmd: true)) == .zoomIn)
        #expect(EditorCommand.from(k("-", 27, cmd: true)) == .zoomOut)
        #expect(
            EditorCommand.from(k("!", 18, shift: true)) == .fitAll
                && EditorCommand.from(k("@", 19, shift: true)) == .fitSelection)
        #expect(EditorCommand.from(k("1", 18, cmd: true)) == .fitSelection)  // as before
        #expect(
            EditorCommand.from(k("\r", 36)) == .selectChildren
                && EditorCommand.from(k("\r", 36, shift: true)) == .selectParent)
        #expect(EditorCommand.from(k("?", 44, shift: true)) == .shortcuts)
    }

    @Test func otherKeysAreLeftToTheEngine() {
        #expect(EditorCommand.from(k("z", 6, cmd: true)) == nil)  // undo is the engine's
        #expect(EditorCommand.from(k("r", 15)) == nil)  // the rectangle tool letter
        #expect(EditorCommand.from(k("a", 0)) == nil)
        #expect(EditorCommand.from(EditorKey(chars: "c", keyCode: 8, command: true, control: true)) == nil)
    }

    @Test func everyCommandIsListedForTheShortcutSheet() {
        let listed = Set(ShortcutList.groups.flatMap(\.rows).map(\.keys))
        for c in EditorCommand.allCases { #expect(listed.contains(c.keys), "\(c.title) is not in the sheet") }
    }
}

@Suite struct CollaboratorTests {
    @Test func decodesAndGuardsAgainstHostileText() {
        let json = """
            [{"peer":"person:d_a","label":"Maya","kind":"person","following":true},
             {"peer":"session:as_1","label":"","kind":"ai","following":false},
             {"label":"no peer"}, {"peer":"","label":"x"}]
            """
        let list = Collaborator.decode(Data(json.utf8))
        #expect(list.count == 2)
        #expect(list[0].label == "Maya" && list[0].following && !list[0].isAI)
        #expect(list[1].label == "An AI session" && list[1].isAI)
        let long = #"[{"peer":"person:d_a","label":"\#(String(repeating: "x", count: 500))"}]"#
        #expect(Collaborator.decode(Data(long.utf8))[0].label.count == 40)
        #expect(Collaborator.decode(Data("nope".utf8)).isEmpty && Collaborator.decode(nil).isEmpty)
    }
}
