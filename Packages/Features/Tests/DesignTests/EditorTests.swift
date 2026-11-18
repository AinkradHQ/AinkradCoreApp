import Foundation
import Testing

@testable import Design

private func layer(
    _ id: String, _ type: String = "rect", _ parent: String? = "p", _ order: String = "i", hidden: Bool = false
)
    -> DesignLayer
{
    DesignLayer(id: id, type: type, parent: parent, order: order, name: id.uppercased(), hidden: hidden)
}

private func text(_ ops: [[String: DJSON]]?) -> String { ops.flatMap(EditOps.json) ?? "nil" }

@Suite struct FractionalOrderTests {
    @Test func betweenIsStrictlyBetweenAndValid() {
        let m = FractionalOrder.between("a", "b")
        #expect(m.map(FractionalOrder.isOrder) == true && m! > "a" && m! < "b")
        #expect(FractionalOrder.between(nil, nil).map(FractionalOrder.isOrder) == true)
        #expect(FractionalOrder.between("a", "a") == nil)
        #expect(FractionalOrder.between("b", "a") == nil)
        #expect(FractionalOrder.between("a0", nil) == nil)  // not an order: ends in 0
    }

    @Test func repeatedInsertionsStayOrdered() {
        var lo = "i"
        for _ in 0..<20 {
            guard let n = FractionalOrder.between(lo, nil) else { return #expect(Bool(false)) }
            #expect(n > lo && FractionalOrder.isOrder(n))
            lo = n
        }
    }

    @Test func overflowAsksForARebalance() {
        #expect(FractionalOrder.between(String(repeating: "z", count: 32), nil) == nil)
        let r = FractionalOrder.rebalance(6)!
        #expect(r.count == 6 && r == r.sorted() && r.allSatisfy(FractionalOrder.isOrder) && Set(r).count == 6)
    }
}

@Suite struct LayerTreeTests {
    let all = [
        layer("p", "page", nil), layer("f", "frame", "p", "i"), layer("t", "text", "f", "i"),
        layer("r", "rect", "f", "r"),
        layer("e", "ellipse", "p", "r"),
    ]

    @Test func rowsListTheFrontFirstAndHideCollapsedChildren() {
        let tree = LayerTree(all)
        #expect(tree.rows(expanded: ["p"]).map(\.layer.id) == ["p", "e", "f"])
        let open = tree.rows(expanded: ["p", "f"])
        #expect(open.map(\.layer.id) == ["p", "e", "f", "r", "t"] && open.map(\.depth) == [0, 1, 1, 2, 2])
        #expect(tree.ancestors(of: "t") == ["f", "p"])
    }

    @Test func aDetachedNodeShowsAtTheTopLevel() {
        let tree = LayerTree([layer("x", "rect", "gone")])
        #expect(tree.rows(expanded: []).map(\.layer.id) == ["x"])
    }

    @Test func movingAboveTheFrontLayerWritesAnOrderAfterIt() throws {
        let ops = try #require(LayerTree(all).moveOps("f", .above("e")))
        #expect(ops.count == 1 && ops[0]["op"] == .string("move") && ops[0]["parent"] == .string("p"))
        let o = try #require(ops[0]["order"]?.string)
        #expect(o > "r" && FractionalOrder.isOrder(o))
    }

    @Test func movingBelowWritesAnOrderBeforeIt() throws {
        let ops = try #require(LayerTree(all).moveOps("e", .below("f")))  // e is front (r); below f (i): before i
        let o = try #require(ops[0]["order"]?.string)
        #expect(o < "i" && FractionalOrder.isOrder(o))
    }

    @Test func movingIntoAContainerNestsAtTheFront() throws {
        let ops = try #require(LayerTree(all).moveOps("e", .into("f")))
        #expect(ops[0]["parent"] == .string("f") && (ops[0]["order"]?.string ?? "") > "r")
    }

    @Test func refusesWhatTheCoreWouldRefuse() {
        let tree = LayerTree(all)
        #expect(tree.moveOps("f", .into("t")) == nil)  // into a leaf
        #expect(tree.moveOps("f", .into("f")) == nil)  // into itself
        #expect(tree.moveOps("p", .into("f")) == nil)  // the page never moves
        #expect(tree.moveOps("f", .above("t")) == nil)  // into its own subtree
        #expect(tree.moveOps("f", .above("p")) == nil)  // beside the page
        #expect(tree.moveOps("e", .above("e")) == nil)
    }

    @Test func droppingWhereItAlreadyIsChangesNothing() {
        #expect(LayerTree(all).moveOps("f", .below("e")) == nil)  // f is already just behind e
    }

    @Test func renumbersSiblingsWhenOrdersRanOut() throws {
        let z = String(repeating: "z", count: 32)
        let tree = LayerTree([layer("p", "page", nil), layer("a", "rect", "p", z), layer("b", "rect", "p", "i")])
        let ops = try #require(tree.moveOps("b", .above("a")))
        let orders = Dictionary(
            uniqueKeysWithValues: ops.compactMap { o in
                o["id"]?.string.flatMap { id in o["order"]?.string.map { (id, $0) } }
            })
        #expect(orders.count == 2 && orders.values.allSatisfy(FractionalOrder.isOrder))
        #expect(try #require(orders["a"]) < (try #require(orders["b"])))
    }

    @Test func stepsMoveOneSiblingTowardTheFrontOrBack() throws {
        let tree = LayerTree(all)
        let up = try #require(tree.step("t", up: true))
        #expect((up[0]["order"]?.string ?? "") > "r")
        #expect(tree.step("r", up: true) == nil)  // already the front
        #expect(tree.step("t", up: false) == nil)  // already the back
        #expect(tree.step("p", up: true) == nil)
    }
}

@Suite struct EditOpsTests {
    @Test func opsEncodeWithSortedKeysAndIntegerNumbers() {
        #expect(
            text([EditOps.set("n_a", "visible", .bool(false))])
                == #"[{"id":"n_a","key":"visible","op":"set","value":false}]"#)
        #expect(text([EditOps.set("n_a", "weight", .number(600))]).contains(#""value":600}"#))
        #expect(text([EditOps.set("n_a", "opacity", .number(0.5))]).contains(#""value":0.5}"#))
        #expect(text([EditOps.set("n_a", "visible", nil)]).contains(#""value":null"#))  // null removes the prop
        #expect(text([EditOps.name("n_a", "Pay")]) == #"[{"id":"n_a","name":"Pay","op":"name"}]"#)
    }

    @Test func aBatchOverTheCoreCapIsNotSent() {
        #expect(EditOps.json([]) == nil)
        #expect(EditOps.json(Array(repeating: EditOps.delete("n_a"), count: 201)) == nil)
        #expect(EditOps.json(Array(repeating: EditOps.delete("n_a"), count: 200)) != nil)
    }
}

@Suite struct InspectorEditsTests {
    let node = EditorNode(
        id: "n_a", type: "frame",
        props: [
            "fill": .array([
                .object(["type": .string("linear"), "angle": .number(90)])
            ]),
            "layout": .object(["dir": .string("row"), "pad": .array(Array(repeating: .number(8), count: 4))]),
            "overrides": .object([".": .object(["opacity": .number(0.5)]), "n_b": .object([:])]),
        ])

    @Test func aGradientFillIsKeptNotReplaced() {
        #expect(InspectorEdits.firstSolid(node) == nil)
        let f = InspectorEdits.fill(node, color: .string("#ffffff"))
        #expect(f.array?.count == 1 && f.array?[0]["type"]?.string == "linear")
    }

    @Test func aSolidFillIsReplacedAndRemoved() {
        let n = EditorNode(
            id: "n_a", type: "rect",
            props: [
                "fill": .array([
                    .object(["type": .string("solid"), "color": .string("#000000")]),
                    .object(["type": .string("linear")]),
                ])
            ])
        #expect(InspectorEdits.firstSolid(n) == .string("#000000"))
        #expect(InspectorEdits.fill(n, color: .token("color.accent")).array?[0]["color"]?.tokenName == "color.accent")
        #expect(InspectorEdits.removingFirstFill(n)?.array?.count == 1)
        #expect(
            InspectorEdits.removingFirstFill(
                EditorNode(
                    id: "n_a", type: "rect",
                    props: ["fill": .array([.object(["type": .string("solid"), "color": .string("#000000")])])])) == nil
        )
        #expect(InspectorEdits.fill(EditorNode(id: "n_a", type: "rect"), color: .string("#808080")).array?.count == 1)
    }

    @Test func layoutKeepsItsOtherKeysAndPadIsFourNumbers() {
        let l = InspectorEdits.layout(node, "gap", .number(12))
        #expect(l["dir"]?.string == "row" && l["gap"]?.double == 12 && l["pad"]?.array?.count == 4)
        #expect(InspectorEdits.padValue(node) == 8)
        #expect(InspectorEdits.pad(4).array?.count == 4)
        #expect(
            InspectorEdits.layout(EditorNode(id: "n_a", type: "frame"), "gap", .number(4))["dir"]?.string == "column")
        #expect(InspectorEdits.layout(node, "gap", nil)["gap"] == nil)
    }

    @Test func aTokenStyleBecomesALiteralWhenEdited() {
        let n = EditorNode(id: "n_t", type: "text", props: ["type": .token("type.title")])
        let t = InspectorEdits.type(n, "size", .number(20))
        #expect(t.tokenName == nil && t["size"]?.double == 20)
        #expect(InspectorEdits.literal(kind: "type")["weight"]?.double == 400)
    }

    @Test func overridesAreListedAndRemovedOneAtATime() {
        #expect(InspectorEdits.overridePaths(node).map(\.path) == [".", "n_b"])
        #expect(InspectorEdits.overrides(node, removing: "n_b")?.object?.keys.sorted() == ["."])
        let one = EditorNode(id: "n_i", type: "instance", props: ["overrides": .object(["n_b": .object([:])])])
        #expect(InspectorEdits.overrides(one, removing: "n_b") == nil)
    }

    @Test func colourFieldAcceptsOnlyHex() {
        #expect(ColorRow.valid("#a1B2c3") && ColorRow.valid("#a1b2c3ff"))
        #expect(!ColorRow.valid("a1b2c3") && !ColorRow.valid("#12345") && !ColorRow.valid("#gggggg"))
    }
}

@Suite struct PeerTests {
    @Test func decodesDevicesAndAIAndSkipsGarbage() {
        let json = """
            {"7": {"label": "Mac Studio", "selection": ["n_a", "n_b"]},
             "9": {"label": "Claude", "session": "as_1", "selection": []},
             "11": "nope",
             "12": {"selection": [1, "n_c"]}}
            """
        let p = DesignPeer.decode(json.data(using: .utf8))
        #expect(p.map(\.id) == ["9", "7", "12"])  // the AI first
        #expect(p[0].isAI && p[0].label == "Claude")
        #expect(p[1].selection == ["n_a", "n_b"])
        #expect(p[2].label == "Someone" && p[2].selection == ["n_c"])
        #expect(DesignPeer.decode(nil).isEmpty && DesignPeer.decode(Data("[1]".utf8)).isEmpty)
    }

    @Test func aHugeLabelIsClipped() {
        let json = #"{"1": {"label": "\#(String(repeating: "x", count: 500))"}}"#
        #expect(DesignPeer.decode(json.data(using: .utf8))[0].label.count == 40)
    }
}

@MainActor
final class FakeBackend: DesignEditBackend {
    var treeJSON = "[]"
    var nodes: [String: String] = [:]
    var sel: [String] = []
    var edits: [String] = []
    var presence: [String] = []
    var refuse = false
    var canSelect = true
    var peerJSON: String?
    func tree() -> Data? { treeJSON.data(using: .utf8) }
    func node(_ id: String) -> String? { nodes[id] }
    func selection() -> [String] { sel }
    func select(_ ids: [String]) -> Bool {
        guard canSelect else { return false }
        sel = ids
        return true
    }
    func edit(_ json: String) -> Bool {
        if refuse { return false }
        edits.append(json)
        return true
    }
    func undo() { edits.append("undo") }
    func redo() { edits.append("redo") }
    func fitSelection() {}
    func peers() -> Data? { peerJSON?.data(using: .utf8) }
    func setPresence(_ json: String) { presence.append(json) }
    func tokens() -> Data? { #"[{"name": "radius.control", "kind": "radius"}]"#.data(using: .utf8) }
}

@MainActor
@Suite struct DesignEditorTests {
    private func make() -> (DesignEditor, FakeBackend) {
        let b = FakeBackend()
        b.treeJSON = """
            [{"id":"p","type":"page","parent":null,"order":"i","name":"Page"},
             {"id":"f","type":"frame","parent":"p","order":"i","name":"Card"},
             {"id":"t","type":"text","parent":"f","order":"i","name":"Title"},
             {"id":"u","type":"text","parent":"f","order":"r","name":"Body"}]
            """
        b.nodes["t"] =
            #"{"id":"t","type":"text","parent":"f","order":"i","name":"Title","props":{"opacity":1},"text":"Hi"}"#
        b.nodes["u"] = #"{"id":"u","type":"text","parent":"f","order":"r","name":"Body","props":{},"text":"Yo"}"#
        let e = DesignEditor(doc: "dd_1")
        e.attach(b)
        return (e, b)
    }

    @Test func attachingReadsLayersAndTokens() {
        let (e, _) = make()
        #expect(e.layers.layers.count == 4 && e.attached)
        #expect(e.tokens.map(\.name) == ["radius.control"])
        #expect(e.node == nil)
    }

    @Test func selectingOnTheCanvasRevealsAndInspectsTheNode() {
        let (e, b) = make()
        b.sel = ["t"]
        e.reload()
        #expect(e.node?.name == "Title" && e.expanded.isSuperset(of: ["f", "p"]))
        #expect(b.presence.count == 1 && b.presence[0].contains(#""selection":["t"]"#))
        e.reload()
        #expect(b.presence.count == 1)  // unchanged selection: presence not re-sent
    }

    @Test func pickingALayerSelectsThroughTheEngineOrSaysItCannot() {
        let (e, b) = make()
        e.select("u")
        #expect(b.sel == ["u"] && e.node?.name == "Body")
        b.canSelect = false
        e.select("t")
        #expect(e.notice?.contains("cannot select") == true)
    }

    @Test func renameWritesANameOpOnlyWhenItChanged() {
        let (e, b) = make()
        e.renaming = "t"
        e.rename("t", to: "  Heading  ")
        #expect(e.renaming == nil && b.edits == [#"[{"id":"t","name":"Heading","op":"name"}]"#])
        e.rename("t", to: "Title")  // same as the layer's name
        #expect(b.edits.count == 1)
    }

    @Test func hideSetsVisibleFalseAndShowRemovesIt() {
        let (e, b) = make()
        e.setHidden("t", true)
        e.setHidden("t", false)
        #expect(b.edits[0].contains(#""value":false"#) && b.edits[1].contains(#""value":null"#))
    }

    @Test func theInspectorWritesToEverySelectedNodeOfTheSameType() {
        let (e, b) = make()
        b.sel = ["t", "u", "f"]
        e.reload()
        e.set("opacity", .number(0.5))
        let json = b.edits.last ?? ""
        #expect(json.contains(#""id":"t""#) && json.contains(#""id":"u""#) && !json.contains(#""id":"f""#))
    }

    @Test func aRefusedWriteSaysSoAndChangesNothing() {
        let (e, b) = make()
        b.refuse = true
        #expect(!e.apply([EditOps.delete("t")]))
        #expect(e.notice != nil && b.edits.isEmpty)
        b.refuse = false
        #expect(e.apply([EditOps.delete("t")]) && e.notice == nil)
    }

    @Test func droppingALayerWritesOneMoveAndClearsTheDrag() {
        let (e, b) = make()
        e.dragging = "t"
        e.drop("t", .above("u"))
        #expect(e.dragging == nil && b.edits.count == 1 && b.edits[0].contains(#""op":"move""#))
        e.drop("p", .into("f"))  // the page never moves
        #expect(b.edits.count == 1)
    }

    @Test func thePageCannotBeDeleted() {
        let (e, b) = make()
        e.delete("p")
        #expect(b.edits.isEmpty)
    }

    @Test func peersComeFromTheEngine() {
        let (e, b) = make()
        b.peerJSON = #"{"3": {"label": "Claude", "session": "as_1"}}"#
        e.reload()
        #expect(e.peers.map(\.label) == ["Claude"] && e.peers[0].isAI)
    }

    @Test func detachingEmptiesTheChrome() {
        let (e, _) = make()
        e.attach(nil)
        #expect(e.layers.layers.isEmpty && e.selection.isEmpty && !e.attached)
    }

    @Test func askNeedsAnAIAndKeepsTheWordsWhenItFails() async {
        let (e, b) = make()
        b.sel = ["t"]
        e.reload()
        e.askText = "Make it bigger"
        #expect(!e.canAsk)
        await e.submitAsk()
        #expect(e.askText == "Make it bigger")
        var got: AskRequest?
        e.ask = { r in
            got = r
            return false
        }
        await e.submitAsk()
        #expect(
            got == AskRequest(doc: "dd_1", text: "Make it bigger", selection: ["t"]) && e.askText == "Make it bigger")
        e.ask = { _ in true }
        await e.submitAsk()
        #expect(e.askText.isEmpty)
    }

    @Test func versionsWithoutARouteSayWhy() async {
        let e = DesignEditor(doc: "dd_1", service: FakeService())
        await e.loadVersions()
        #expect(e.versionsNote == "This Core does not keep versions yet.")
        await e.saveVersion(named: "Before pay")
        #expect(e.versionsNote == "This Core does not keep versions yet.")
        let none = DesignEditor(doc: "dd_1")
        await none.loadVersions()
        #expect(none.versionsNote == "Versions need a connection to the Core.")
    }
}

@Suite struct VersionWireTests {
    @Test func decodesTheCoresShape() throws {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let w = try d.decode(
            [VersionWire].self,
            from: Data(
                #"[{"id":"v7","kind":"approval","name":"B","created_by":"device:d_1","created_at":"2026-11-18T10:02:00Z"}]"#
                    .utf8))
        #expect(w[0].version.kind == .approval && w[0].version.createdAt != nil && w[0].version.id == "v7")
        #expect(VersionWire(id: "v1", kind: "weird", name: "", createdBy: "", createdAt: "").version.kind == .auto)
    }
}
