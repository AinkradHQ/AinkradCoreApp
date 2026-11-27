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

private func seq(_ ids: [String]) -> () -> String {
    var i = 0
    return {
        defer { i += 1 }
        return "n_new\(ids.count > i ? ids[i] : String(i))"
    }
}

@Suite struct ClipboardTests {
    private func payload(_ ids: [String]) -> ClipPayload? {
        EditorClipboard.collect(ids: ids, doc: "dd_1", layers: layers, node: { nodes[$0] })
    }

    @Test func collectsSubtreesParentsFirstAndSkipsNestedSelection() throws {
        let p = try #require(payload(["g", "t", "a"]))  // t is inside g: not a root of its own
        #expect(p.roots == ["g", "a"] && p.nodes.map(\.id) == ["g", "t", "a"])
        #expect(p.nodes[2].text == nil && payload(["c"])?.nodes[0].text == "Hello")
        #expect(payload(["p"]) == nil)  // a page is never copied
    }

    @Test func pasteWritesFreshIdsKeepingTheStructure() throws {
        let p = try #require(payload(["g", "a"]))
        let r = try #require(
            EditorClipboard.ops(p, place: .init(parent: "f", lo: "r", offset: (16, 16)), sameDoc: true, newID: seq([])))
        #expect(r.ops.count == 3 && r.roots == ["n_new0", "n_new2"])
        #expect(r.ops.allSatisfy { $0["op"] == .string("add") })
        let ids = r.ops.compactMap { $0["id"]?.string }
        #expect(Set(ids).count == 3 && Set(ids).isDisjoint(with: ["g", "t", "a"]))
        // the child hangs under the copy of g, not under g
        #expect(r.ops[1]["parent"] == .string(ids[0]) && r.ops[0]["parent"] == .string("f"))
        // roots stack in order after `lo`, offset applied to x and y; the child keeps its own position
        let o0 = try #require(r.ops[0]["order"]?.string)
        let o2 = try #require(r.ops[2]["order"]?.string)
        #expect(o0 > "r" && o2 > o0 && FractionalOrder.isOrder(o0) && FractionalOrder.isOrder(o2))
        #expect(r.ops[0]["props"]?["x"] == .number(216) && r.ops[0]["props"]?["y"] == .number(116))
        #expect(r.ops[1]["props"]?["x"] == .number(10))
        #expect(r.ops[2]["props"]?["x"] == .number(26))
    }

    @Test func textKeepsItsWordsAndOtherNodesGetNone() throws {
        let p = try #require(payload(["c", "a"]))
        let r = try #require(EditorClipboard.ops(p, place: .init(parent: "f", lo: nil), sameDoc: true))
        #expect(r.ops[0]["text"] == .string("Hello") && r.ops[1]["text"] == nil)
        #expect(EditOps.json(r.ops) != nil)
    }

    @Test func aLinkFollowsTheCopyOrDropsWhenItLeavesTheDesign() throws {
        var p = try #require(payload(["a", "b"]))
        p.nodes[0].props["link"] = .object(["to": .string("b")])  // to a copied node
        p.nodes[1].props["link"] = .object(["to": .string("zz")])  // to one that is not copied
        let same = try #require(EditorClipboard.ops(p, place: .init(parent: "f", lo: nil), sameDoc: true))
        let idB = try #require(same.ops[1]["id"]?.string)
        #expect(same.ops[0]["props"]?["link"]?["to"] == .string(idB))
        #expect(same.ops[1]["props"]?["link"]?["to"] == .string("zz"))
        let other = try #require(EditorClipboard.ops(p, place: .init(parent: "f", lo: nil), sameDoc: false))
        #expect(other.ops[1]["props"]?["link"] == nil)
    }

    @Test func refusesWhatTheCoreWouldRefuse() throws {
        var p = try #require(payload(["a"]))
        let node = p.nodes[0]
        p.nodes = Array(repeating: node, count: EditorClipboard.maxNodes + 1)
        #expect(EditorClipboard.ops(p, place: .init(parent: "f", lo: nil), sameDoc: true) == nil)
        #expect(
            EditorClipboard.ops(p, place: .init(parent: "f", lo: String(repeating: "z", count: 32)), sameDoc: true)
                == nil)
    }

    @Test func pasteboardJSONIsValidatedBeforeItIsTrusted() throws {
        let p = try #require(payload(["a"]))
        let data = try JSONEncoder().encode(p)
        #expect(EditorClipboard.valid(try JSONDecoder().decode(ClipPayload.self, from: data)))
        var bad = p
        bad.kind = "something.else"
        #expect(!EditorClipboard.valid(bad))
        bad = p
        bad.roots = ["missing"]
        #expect(!EditorClipboard.valid(bad))
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

    @Test func ungroupMovesChildrenToTheParentInPlaceAndDeletesTheFrame() throws {
        let a = Arrange.ungroup(["g"], layers: layers, box: box)
        #expect(a.why == nil && a.select == ["t"])
        #expect(a.ops.count == 4)
        #expect(a.ops[0]["id"] == .string("t") && a.ops[0]["parent"] == .string("f"))
        let o = try #require(a.ops[0]["order"]?.string)
        #expect(o > "w" && FractionalOrder.isOrder(o))  // g was the front-most: the children take its place
        #expect(a.ops[1] == EditOps.set("t", "x", .number(210)) && a.ops[2] == EditOps.set("t", "y", .number(110)))
        #expect(a.ops[3] == EditOps.delete("g"))
    }

    @Test func ungroupRefusesAScreenAnEmptyFrameAndAShape() {
        #expect(Arrange.ungroup(["f"], layers: layers, box: box).why?.contains("screen") == true)
        let empty = LayerTree([layer("p", "page", nil), layer("f", "frame", "p"), layer("e", "frame", "f")])
        #expect(Arrange.ungroup(["e"], layers: empty, box: box).why?.contains("nothing inside") == true)
        #expect(Arrange.ungroup(["a"], layers: layers, box: box).why != nil)
    }

    @Test func groupThenUngroupRestoresTheOriginalPositions() throws {
        let g = Arrange.group(["a", "b"], layers: layers, box: box, id: "n_group")
        // apply by hand to a model of the nodes, then ungroup it
        var props = nodes.mapValues(\.props)
        var parent = ["a": "f", "b": "f"]
        for op in g.ops {
            switch op["op"]?.string {
            case "add": props["n_group"] = op["props"]?.object
            case "set": props[op["id"]!.string!]?[op["key"]!.string!] = op["value"]
            case "move": parent[op["id"]!.string!] = op["parent"]!.string
            default: break
            }
        }
        #expect(parent["a"] == "n_group" && props["a"]?["x"] == .number(0))
        let back = LayerTree([
            layer("p", "page", nil), layer("f", "frame", "p"), layer("n_group", "frame", "f", "i"),
            layer("a", "rect", "n_group", "g"), layer("b", "rect", "n_group", "q"),
        ])
        let up = Arrange.ungroup(
            ["n_group"], layers: back,
            box: { id in NodeBox(EditorNode(id: id, type: "rect", props: props[id] ?? [:])) })
        #expect(
            up.ops.contains(EditOps.set("a", "x", .number(10))) && up.ops.contains(EditOps.set("a", "y", .number(20))))
        #expect(
            up.ops.contains(EditOps.set("b", "x", .number(100))) && up.ops.contains(EditOps.set("b", "y", .number(30))))
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

@Suite struct ComponentTests {
    private func node(_ id: String) -> EditorNode? { nodes[id] }

    @Test func createTurnsAFrameIntoAComponentInPlace() throws {
        let a = Components.create("g", doc: "dd_1", layers: layers, node: node)
        #expect(a.why == nil && a.ops.count == 3)
        #expect(a.ops[0]["type"] == .string("component") && a.ops[0]["order"] == .string("w"))
        #expect(a.ops[0]["parent"] == .string("f") && a.ops[2] == EditOps.delete("g"))
        #expect(a.ops[1]["type"] == .string("rect") && a.ops[1]["parent"] == a.ops[0]["id"])
        #expect(a.select == [a.ops[0]["id"]!.string!])
        #expect(Components.create("a", doc: "dd_1", layers: layers, node: node).why != nil)  // not a frame
    }

    @Test func anInstanceCarriesOnlyItsPlaceAndTheReference() throws {
        let comp = layer("k", "component", "p", "i", name: "Button")
        let op = try #require(
            Components.instance(of: comp, doc: "dd_1", parent: "f", lo: "r", at: (40, 40), id: "n_inst"))
        #expect(op["type"] == .string("instance") && op["name"] == .string("Button"))
        #expect(op["props"] == .object(["component": .string("dd_1/k"), "x": .number(40), "y": .number(40)]))
        #expect(EditOps.json([op]) != nil)
    }

    @Test func detachFoldsTheInstanceIntoAFrame() throws {
        let tree = LayerTree([
            layer("p", "page", nil), layer("k", "component", "p", "i"), layer("kt", "text", "k", "i"),
            layer("f", "frame", "p", "r"), layer("inst", "instance", "f", "i"),
        ])
        let table: [String: EditorNode] = [
            "k": EditorNode(
                id: "k", type: "component", name: "Card", props: rect(0, 0, 100, 50, ["radius": .number(8)])),
            "kt": EditorNode(id: "kt", type: "text", props: rect(4, 4, 90, 20), text: "Title"),
            "inst": EditorNode(
                id: "inst", type: "instance", name: "Card 2",
                props: [
                    "component": .string("dd_1/k"), "x": .number(30), "y": .number(60),
                    "overrides": .object(["kt": .object(["text": .string("Pay now")])]),
                ]),
        ]
        let a = Components.detach(["inst"], doc: "dd_1", layers: tree, node: { table[$0] })
        #expect(a.why == nil && a.ops.count == 3)
        #expect(a.ops[0]["type"] == .string("frame") && a.ops[0]["order"] == .string("i"))
        #expect(a.ops[0]["parent"] == .string("f") && a.ops[0]["name"] == .string("Card 2"))
        let p = try #require(a.ops[0]["props"])
        #expect(p["x"] == .number(30) && p["y"] == .number(60) && p["radius"] == .number(8) && p["component"] == nil)
        #expect(a.ops[1]["text"] == .string("Pay now"))  // the override is folded in
        #expect(a.ops[2] == EditOps.delete("inst"))
        // an instance of a design-system component cannot be detached here
        var other = table
        other["inst"]?.props["component"] = .string("dd_sys/k")
        #expect(Components.detach(["inst"], doc: "dd_1", layers: tree, node: { other[$0] }).why != nil)
        #expect(Components.detach(["f"], doc: "dd_1", layers: tree, node: { table[$0] }).why != nil)
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
