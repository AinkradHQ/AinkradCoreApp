import Foundation
import Testing

@testable import Design

@MainActor
@Suite struct EditorFixesTests {
    private func make(readOnly: Bool = false) -> (DesignEditor, FakeBackend) {
        let b = FakeBackend()
        b.treeJSON = """
            [{"id":"p","type":"page","parent":null,"order":"i","name":"Page"},
             {"id":"f","type":"frame","parent":"p","order":"i","name":"Card"},
             {"id":"t","type":"text","parent":"f","order":"i","name":"A"},
             {"id":"u","type":"text","parent":"f","order":"r","name":"B"},
             {"id":"v","type":"text","parent":"f","order":"z","name":"C"}]
            """
        b.nodes["t"] =
            ##"{"id":"t","type":"text","parent":"f","name":"A","props":{"x":0,"y":0,"w":10,"h":10,"type":{"size":12,"weight":400},"fill":[{"type":"solid","color":"#111111"}]},"text":"a"}"##
        b.nodes["u"] =
            ##"{"id":"u","type":"text","parent":"f","name":"B","props":{"x":50,"y":5,"w":30,"h":10,"type":{"size":20,"weight":700},"fill":[{"type":"solid","color":"#222222"}]},"text":"b"}"##
        b.nodes["v"] =
            ##"{"id":"v","type":"text","parent":"f","name":"C","props":{"x":100,"y":0,"w":20,"h":10,"type":{"size":20,"weight":400}},"text":"c"}"##
        let e = DesignEditor(doc: "dd_1")
        e.readOnly = readOnly
        e.attach(b)
        b.sel = ["t", "u", "v"]
        e.reload()
        return (e, b)
    }

    @Test func aFieldWriteOnAMultiSelectionChangesOnlyThatField() {
        let (e, b) = make()
        e.setEach("type") { InspectorEdits.type($0, "size", .number(30)) }
        let json = b.edits.last ?? ""
        // each text keeps its own weight; only size is 30
        #expect(json.contains(#""weight":700"#) && json.contains(#""weight":400"#))
        #expect(json.components(separatedBy: #""size":30"#).count == 4)
    }

    @Test func differingValuesAreMixed() {
        let (e, _) = make()
        #expect(e.mixed { $0.props["type"]?["size"] })
        #expect(!e.mixed { $0.props["type"]?.object == nil ? .null : .string("same") })
        #expect(e.mixed { $0.props["x"] })
    }

    @Test func alignMathUsesEachOwnSizeAndTheSelectionBounds() {
        let boxes = [
            EditorAlign.Box(id: "a", x: 0, y: 0, w: 10, h: 10), EditorAlign.Box(id: "b", x: 50, y: 5, w: 30, h: 10),
        ]
        let right = EditorAlign.align(boxes, .right)
        #expect(right.count == 1 && right[0] == ("a", "x", 70))  // b already at the right edge (80)
        let centre = EditorAlign.align(boxes, .centerX)
        #expect(centre.first { $0.0 == "a" }?.2 == 35 && centre.first { $0.0 == "b" }?.2 == 25)
        let one = EditorAlign.align([boxes[0]], .centerX, in: (w: 100, h: 100))
        #expect(one[0].2 == 45)
    }

    @Test func distributeKeepsTheOuterTwoAndEvensTheGaps() {
        let boxes = [
            EditorAlign.Box(id: "a", x: 0, y: 0, w: 10, h: 10), EditorAlign.Box(id: "b", x: 50, y: 0, w: 30, h: 10),
            EditorAlign.Box(id: "c", x: 100, y: 0, w: 20, h: 10),
        ]
        let d = EditorAlign.distribute(boxes, horizontal: true)
        // span 120, widths 60, gap 30: b at 40
        #expect(d.count == 1 && d[0] == ("b", "x", 40))
        #expect(EditorAlign.distribute(Array(boxes.prefix(2)), horizontal: true).isEmpty)
    }

    @Test func aViewerCannotWrite() {
        let (e, b) = make(readOnly: true)
        let before = b.edits.count
        #expect(!e.apply([EditOps.delete("t")]))
        e.undo()
        #expect(b.edits.count == before && e.notice == DesignEditor.readOnlySentence)
    }

    @Test func aHaltedDesignRefusesEditsAndReopenRebuilds() {
        let (e, b) = make()
        b.syncHalted = true
        e.reload()
        #expect(e.syncHalted && !e.apply([EditOps.delete("t")]) && e.notice == DesignEditor.haltedSentence)
        let g = e.generation
        e.reopen()
        #expect(e.generation == g + 1 && !e.syncHalted && !e.attached)
    }

    @Test func deletingSeveralLayersIsOneUndoStepAndSkipsChildrenOfDeleted() {
        let (e, b) = make()
        b.sel = ["f", "t", "u"]
        e.reload()
        e.deleteSelected()
        let json = b.edits.last ?? ""
        #expect(json.contains(#""id":"f""#) && !json.contains(#""id":"t""#) && !json.contains(#""id":"u""#))
        b.sel = ["t", "u"]
        e.reload()
        e.deleteSelected()
        #expect(b.edits.last?.contains(#""id":"t""#) == true && b.edits.last?.contains(#""id":"u""#) == true)
    }

    @Test func theStarterWaitsForTheFirstSnapshot() {
        let b = FakeBackend()
        let e = DesignEditor(doc: "dd_2")
        e.starter = DesignOptions.starterOps(DesignOptions.canvas)
        b.loaded = false
        e.attach(b)
        #expect(b.edits.isEmpty)
        b.loaded = true
        e.reload()
        #expect(b.edits.count == 1)
    }

    @Test func peersDecodeFromTheEngineList() {
        let json = #"[{"peer":"person:d_a","label":"Another device","kind":"person","following":false},{"peer":"session:as_b","label":"An AI session","kind":"ai","following":false}]"#
        let p = DesignPeer.decode(json.data(using: .utf8))
        #expect(p.count == 2 && p[1].isAI && p[0].label == "Another device")
    }
}
