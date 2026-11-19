import Testing

@testable import Design

@MainActor
struct FrameSketchTests {
    @Test func aFrameIsSketchedFromItsChildren() {
        let layers = LayerTree([
            DesignLayer(id: "f", type: "frame", parent: nil, order: "a"),
            DesignLayer(id: "t", type: "text", parent: "f", order: "a"),
            DesignLayer(id: "b", type: "rect", parent: "f", order: "b"),
            DesignLayer(id: "h", type: "rect", parent: "f", order: "c", hidden: true),
        ])
        let nodes: [String: EditorNode] = [
            "f": EditorNode(id: "f", type: "frame", props: ["w": .number(360), "h": .number(640), "radius": .number(24),
                "fill": .array([.object(["type": .string("solid"), "color": .string("#F5F7FB")])])]),
            "t": EditorNode(id: "t", type: "text", props: ["x": .number(24), "y": .number(80), "w": .number(300), "h": .number(40),
                "type": .object(["size": .number(34), "weight": .number(700)])], text: "Hi"),
            "b": EditorNode(id: "b", type: "rect", props: ["x": .number(24), "y": .number(540), "w": .number(312), "h": .number(52),
                "radius": .number(14), "fill": .array([.object(["type": .string("solid"), "color": .string("#2F7BEF")])])]),
        ]
        let s = FrameSketch.make(frame: "f", layers: layers) { nodes[$0] }
        #expect(s?.background == "#F5F7FB" && s?.w == 360)
        #expect(s?.shapes.count == 2, "the hidden child is left out")
        #expect(s?.shapes[0].textSize == 34 && s?.shapes[0].text == "Hi")
        #expect(s?.shapes[1].color == "#2F7BEF" && s?.shapes[1].radius == 14)
        #expect(FrameSketch.make(frame: "zz", layers: layers) { nodes[$0] } == nil)
    }
}
