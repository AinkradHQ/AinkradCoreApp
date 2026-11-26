import CoreUI
import SwiftUI

/// One thing the toolbar can add: a node type with its starting size and props. Shapes the engine has no type for (line,
/// arrow, triangle, star) are vectors with SVG path data in their own box.
struct InsertPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let type: String
    let w: Double
    let h: Double
    var props: [String: DJSON] = [:]
    var text: String?

    static func solid(_ hex: String) -> DJSON { .array([.object(["type": .string("solid"), "color": .string(hex)])]) }
    static let grey = solid("#D9D9D9")

    static func frame(_ id: String, _ title: String, _ w: Double, _ h: Double) -> InsertPreset {
        InsertPreset(
            id: id, title: title, symbol: "number", type: "frame", w: w, h: h,
            props: ["fill": solid("#FFFFFF"), "clip": .bool(true)])
    }
    static func vector(_ id: String, _ title: String, _ symbol: String, _ w: Double, _ h: Double, _ path: String)
        -> InsertPreset
    {
        InsertPreset(
            id: id, title: title, symbol: symbol, type: "vector", w: w, h: h,
            props: ["path": .string(path), "fill": grey])
    }
    static func text(_ id: String, _ title: String, size: Double, weight: Double, _ words: String) -> InsertPreset {
        InsertPreset(
            id: id, title: title, symbol: "textformat", type: "text", w: max(120, size * 10), h: (size * 1.4).rounded(),
            props: [
                "type": .object(["size": .number(size), "weight": .number(weight)]), "fill": solid("#111111"),
            ],
            text: words)
    }

    static let frames: [InsertPreset] = [
        frame("phone", "Phone", 390, 844), frame("tablet", "Tablet", 820, 1180),
        frame("desktop", "Desktop", 1440, 900), frame("square", "Square", 400, 400),
    ]
    static let shapes: [InsertPreset] = [
        InsertPreset(
            id: "rect", title: "Rectangle", symbol: "square", type: "rect", w: 160, h: 120,
            props: ["fill": grey, "radius": .number(8)]),
        InsertPreset(
            id: "ellipse", title: "Ellipse", symbol: "circle", type: "ellipse", w: 120, h: 120, props: ["fill": grey]),
        InsertPreset(
            id: "line", title: "Line", symbol: "line.diagonal", type: "rect", w: 200, h: 2,
            props: ["fill": solid("#111111")]),
        vector("arrow", "Arrow", "arrow.right", 200, 24, "M0 10 H180 V0 L200 12 L180 24 V14 H0 Z"),
        vector("triangle", "Triangle", "triangle", 120, 104, "M60 0 L120 104 L0 104 Z"),
        vector(
            "star", "Star", "star", 120, 114,
            "M60 0 L74 42 L120 43 L83 70 L97 114 L60 88 L23 114 L37 70 L0 43 L46 42 Z"),
    ]
    static let texts: [InsertPreset] = [
        text("heading", "Heading", size: 32, weight: 700, "Heading"),
        text("body", "Body", size: 16, weight: 400, "Body text"),
        text("caption", "Caption", size: 12, weight: 500, "Caption"),
    ]

    /// A library picture as an image node.
    static func image(_ a: DesignAsset) -> InsertPreset {
        InsertPreset(
            id: "image-\(a.sha)", title: a.name, symbol: "photo", type: "image", w: 200, h: 200,
            props: ["asset": .string(a.sha), "fit": .string("fit")])
    }
}

extension DesignEditor {
    /// Adds one preset and selects it, inside the selected container (or the selected layer's), else the first frame, else
    /// the page (a frame goes on the page, beside the others). An empty design gets its page and starter frame first. One
    /// undo step. False when the canvas is not up or the engine refused it (`notice` says why).
    @discardableResult
    func insert(_ p: InsertPreset) -> Bool {
        guard attached else { return false }
        if layers.layers.isEmpty {
            apply(DesignOptions.starterOps(DesignOptions.canvas))
            reload()
        }
        let isFrame = p.type == "frame"
        let picked = selection.first.flatMap { layers[$0] }
        let into =
            isFrame
            ? layers.children(of: nil).first
            : (picked?.isContainer == true && picked?.type != "page" ? picked : picked?.parent.flatMap { layers[$0] })
                .flatMap { $0.type == "page" ? nil : $0 }
                ?? layers.layers.first { $0.type == "frame" } ?? layers.children(of: nil).first
        guard let parent = into else { return false }
        let siblings = layers.children(of: parent.id)
        guard let order = FractionalOrder.between(siblings.last?.order, nil) else { return false }
        // A frame goes to the right of the last one; a shape steps down and right so repeats do not stack.
        let at: (Double, Double)
        if isFrame {
            let right = siblings.compactMap { s -> Double? in
                guard let n = node(of: s.id), let x = n.props["x"]?.double else { return nil }
                return x + (n.props["w"]?.double ?? 0)
            }.max()
            at = (right.map { $0 + 80 } ?? 0, 0)
        } else {
            let step = Double(siblings.count % 10) * 24
            at = (40 + step, 40 + step)
        }
        let id = DesignOptions.nodeID()
        var props = p.props
        props["x"] = .number(at.0)
        props["y"] = .number(at.1)
        props["w"] = .number(p.w)
        props["h"] = .number(p.h)
        var op: [String: DJSON] = [
            "op": .string("add"), "id": .string(id), "type": .string(p.type), "parent": .string(parent.id),
            "order": .string(order), "name": .string(p.title), "props": .object(props),
        ]
        if let t = p.text { op["text"] = .string(t) }
        guard apply([op]) else { return false }
        reload()
        select(id, quiet: true)
        if isFrame { fitSelection() }
        return true
    }
}

/// The toolbar along the canvas's foot, as in Figma: Frame, Shape, Text and Image each add their first kind on a click and
/// list the rest on the arrow (⌥⌘1…⌥⌘4 add the first kinds); Draw with AI; then the Ask… field.
struct CanvasToolbar: View {
    let model: DesignModel
    @Bindable var editor: DesignEditor
    @Environment(\.coreAccent) private var paneAccent

    private var pictures: [DesignAsset] {
        model.assets.filter { $0.loadable && [.image, .icon, .logo].contains($0.kind) }
    }

    var body: some View {
        HStack(spacing: Space.s1) {
            tool("Move", "cursorarrow", lit: true) {}
                .help("Select and move: click on the canvas, drag to move, handles resize")
            group("Frame", "number", key: "1", InsertPreset.frames)
            group("Shape", "square", key: "2", InsertPreset.shapes)
            group("Text", "textformat", key: "3", InsertPreset.texts)
            images
            divider
            tool("Draw with AI", "sparkles", lit: false) { Task { await model.drawWithAI() } }
                .disabled(!model.composeSupported || model.readOnly)
                .help(
                    model.composeSupported
                        ? "Draw with AI: describe it, AI draws it here" : "This Core cannot draw with AI yet")
            divider
            AskField(editor: editor)
        }
        .padding(Space.s1)
        // Opaque: over a white board a see-through bar washed out.
        .background(GlassInk.adaptive(Color(white: 0.15), day: .white), in: coreShape(Radius.cardMac + 2))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .disabled(!editor.attached || model.readOnly)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tools")
    }

    private var divider: some View {
        coreShape(1).fill(GlassInk.secondary.opacity(0.25)).frame(width: 1, height: MacSize.controlMd)
            .padding(.horizontal, Space.s1)
    }

    private func tool(_ title: String, _ symbol: String, lit: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol).coreFont(size: MacTextSize.title)
                .foregroundStyle(lit ? .white : GlassInk.primary)
                .frame(width: MacSize.controlLg + Space.s1, height: MacSize.controlLg + Space.s1)
                .background(lit ? GlassInk.accent(paneAccent) : .clear, in: coreShape(Radius.control))
                .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .modifier(ToolHover())
        .accessibilityLabel(title)
    }

    /// A tool with its kinds: a click adds the first, the menu lists them all.
    private func group(_ title: String, _ symbol: String, key: Character, _ presets: [InsertPreset]) -> some View {
        Menu {
            ForEach(presets) { p in
                Button {
                    editor.insert(p)
                } label: {
                    Label(p.title, systemImage: p.symbol)
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: symbol).coreFont(size: MacTextSize.title).foregroundStyle(GlassInk.primary)
                Image(systemName: "chevron.down").coreFont(size: 9, weight: .semibold).foregroundStyle(
                    GlassInk.secondary)
            }
        } primaryAction: {
            if let first = presets.first { editor.insert(first) }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(height: MacSize.controlLg + Space.s1).padding(.horizontal, Space.s2)
        .modifier(ToolHover())
        .keyboardShortcut(KeyEquivalent(key), modifiers: [.command, .option])
        .help("\(title): click to add a \(presets.first?.title.lowercased() ?? ""), or pick one  ⌥⌘\(key)")
        .accessibilityLabel(title)
        .accessibilityIdentifier("design-tool-\(title.lowercased())")
    }

    @ViewBuilder private var images: some View {
        Menu {
            if pictures.isEmpty {
                Text("No pictures in the library yet")
            }
            ForEach(pictures.prefix(30)) { a in
                Button {
                    editor.insert(.image(a))
                } label: {
                    Label(a.name, systemImage: "photo")
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "photo").coreFont(size: MacTextSize.title).foregroundStyle(GlassInk.primary)
                Image(systemName: "chevron.down").coreFont(size: 9, weight: .semibold).foregroundStyle(
                    GlassInk.secondary)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(height: MacSize.controlLg + Space.s1).padding(.horizontal, Space.s2)
        .modifier(ToolHover())
        .help("Image: a picture from the library")
        .accessibilityLabel("Image")
    }
}

/// A tool's hover: a soft well behind it, eased in and out.
struct ToolHover: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .background(on ? GlassInk.wellHover : .clear, in: coreShape(Radius.control))
            .onHover { on = $0 }
            .animation(Motion.out(Motion.hover), value: on)
    }
}
