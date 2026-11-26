import CoreUI
import SwiftUI

/// What the insert bar adds: each a plain shape on the grid, inside the selected container (or the selected layer's), else
/// the first frame, else the page. An empty design gets its page and starter frame first. One undo step per insert.
enum InsertKind: String, CaseIterable, Identifiable {
    case frame, rect, ellipse, text
    var id: String { rawValue }
    var title: String {
        switch self {
        case .frame: "Frame"
        case .rect: "Rectangle"
        case .ellipse: "Ellipse"
        case .text: "Text"
        }
    }
    var symbol: String {
        switch self {
        case .frame: "number"
        case .rect: "square"
        case .ellipse: "circle"
        case .text: "textformat"
        }
    }
    /// ⌥⌘1…⌥⌘4.
    var key: Character { Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1)) }

    func props(at x: Double, _ y: Double) -> [String: DJSON] {
        let grey: DJSON = .array([.object(["type": .string("solid"), "color": .string("#D9D9D9")])])
        let white: DJSON = .array([.object(["type": .string("solid"), "color": .string("#FFFFFF")])])
        switch self {
        case .frame: return ["x": .number(x), "y": .number(y), "w": .number(390), "h": .number(844), "fill": white]
        case .rect:
            return [
                "x": .number(x), "y": .number(y), "w": .number(160), "h": .number(120), "fill": grey,
                "radius": .number(8),
            ]
        case .ellipse: return ["x": .number(x), "y": .number(y), "w": .number(120), "h": .number(120), "fill": grey]
        case .text:
            return [
                "x": .number(x), "y": .number(y), "w": .number(240), "h": .number(40),
                "type": .object(["size": .number(24), "weight": .number(600)]),
            ]
        }
    }
}

extension DesignEditor {
    /// Adds one shape and selects it. False when the canvas is not up or the engine refused it (`notice` says why).
    @discardableResult
    func insert(_ kind: InsertKind) -> Bool {
        guard attached else { return false }
        if layers.layers.isEmpty {
            apply(DesignOptions.starterOps(DesignOptions.canvas))
            reload()
        }
        let picked = selection.first.flatMap { layers[$0] }
        let into =
            (picked?.isContainer == true ? picked : picked?.parent.flatMap { layers[$0] })
            ?? (kind == .frame ? nil : layers.layers.first { $0.type == "frame" })
            ?? layers.children(of: nil).first
        guard let parent = into else { return false }
        let siblings = layers.children(of: parent.id)
        guard let order = FractionalOrder.between(siblings.last?.order, nil) else { return false }
        // A new frame goes beside the others on the page; a shape steps down and right so repeats do not stack.
        let step = Double(siblings.count % 10) * 24
        let at: (Double, Double) =
            kind == .frame && parent.type == "page" ? (Double(siblings.count) * 440, 0) : (40 + step, 40 + step)
        let id = DesignOptions.nodeID()
        var op: [String: DJSON] = [
            "op": .string("add"), "id": .string(id), "type": .string(kind.rawValue), "parent": .string(parent.id),
            "order": .string(order), "name": .string(kind.title), "props": .object(kind.props(at: at.0, at.1)),
        ]
        if kind == .text { op["text"] = .string("Text") }
        guard apply([op]) else { return false }
        reload()
        select(id)
        return true
    }
}

/// The insert bar over the canvas's top: Frame, Rectangle, Ellipse, Text (⌥⌘1…⌥⌘4). Floating, so it takes the clear glass.
struct InsertBar: View {
    let editor: DesignEditor

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(InsertKind.allCases) { kind in
                CoreIconButton(symbol: kind.symbol, label: "Add a \(kind.title.lowercased())  ⌥⌘\(kind.key)") {
                    editor.insert(kind)
                }
                .keyboardShortcut(KeyEquivalent(kind.key), modifiers: [.command, .option])
                .accessibilityIdentifier("design-insert-\(kind.rawValue)")
            }
        }
        .padding(.horizontal, Space.s2)
        .frame(height: MacSize.controlLg + Space.s2)
        .coreGlass(radius: Radius.cardMac, interactive: false)
        .disabled(!editor.attached)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Add to the design")
    }
}
