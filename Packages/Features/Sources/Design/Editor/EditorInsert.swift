import CoreUI
import ImageIO
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

    /// A library picture as an image node, `w` × `h` (its own size when it is known), shrunk to fit its frame on insert.
    static func image(_ a: DesignAsset, w: Double = 200, h: Double = 200) -> InsertPreset {
        InsertPreset(
            id: "image-\(a.sha)", title: a.name, symbol: "photo", type: "image", w: w, h: h,
            props: ["asset": .string(a.sha), "fit": .string("fit")], capToParent: true)
    }
    /// The picture is not larger than the frame it lands in (it keeps its proportions).
    var capToParent = false
}

extension DesignEditor {
    /// Adds one preset and selects it, inside the selected container (or the selected layer's), else the first frame, else
    /// the page (a frame goes on the page, beside the others). An empty design gets its page and starter frame first. One
    /// undo step. False when the canvas is not up or the engine refused it (`notice` says why).
    @discardableResult
    func insert(_ p: InsertPreset) -> Bool {
        guard attached, loaded, !readOnly else { return false }
        if layers.layers.isEmpty {
            apply(DesignOptions.starterOps(DesignOptions.canvas))
            reload()
        }
        let isFrame = p.type == "frame"
        let picked = selection.first.flatMap { layers[$0] }
        let into =
            isFrame
            ? currentPage
            : (picked?.isContainer == true && picked?.type != "page" ? picked : picked?.parent.flatMap { layers[$0] })
                .flatMap { $0.type == "page" ? nil : $0 }
                ?? currentPage.flatMap { p in layers.children(of: p.id).first { $0.type == "frame" } } ?? currentPage
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
        var (w, h) = (p.w, p.h)
        if p.capToParent, let pw = node(of: parent.id)?.props["w"]?.double,
            let ph = node(of: parent.id)?.props["h"]?.double, pw > 0, ph > 0
        {
            let k = min(1, pw / w, ph / h)
            (w, h) = ((w * k).rounded(), (h * k).rounded())
        }
        props["x"] = .number(at.0)
        props["y"] = .number(at.1)
        props["w"] = .number(w)
        props["h"] = .number(h)
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

extension DesignEditor {
    /// Places a library picture at its natural size (capped to its frame). Falls back to 200 × 200 when its size is unknown
    /// (a vector file, or the bytes did not come).
    func insertImage(_ a: DesignAsset) async {
        var (w, h) = (200.0, 200.0)
        if let data = try? await service?.data(a.sha), let src = CGImageSourceCreateWithData(data as CFData, nil),
            let pr = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
            let pw = pr[kCGImagePropertyPixelWidth] as? Double, let ph = pr[kCGImagePropertyPixelHeight] as? Double,
            pw > 0, ph > 0
        {
            (w, h) = (pw, ph)
        }
        insert(.image(a, w: w, h: h))
    }
}

/// The canvas tools (the engine's `DE_TOOL_*`). A drawing tool draws one shape by dragging, then the canvas goes back to
/// Move. The letters work on the canvas whenever no text is being edited, as in Figma.
enum CanvasTool: Int, CaseIterable {
    case select = 0
    case hand, frame, rect, ellipse, line, text, pen
    var title: String {
        switch self {
        case .select: "Move"
        case .hand: "Hand"
        case .frame: "Frame"
        case .rect: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .text: "Text"
        case .pen: "Pen"
        }
    }
    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .hand: "hand.raised"
        case .frame: "number"
        case .rect: "square"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .text: "textformat"
        case .pen: "pencil.tip"
        }
    }
    var key: String {
        switch self {
        case .select: "V"
        case .hand: "H"
        case .frame: "F"
        case .rect: "R"
        case .ellipse: "O"
        case .line: "L"
        case .text: "T"
        case .pen: "P"
        }
    }
    var help: String {
        switch self {
        case .select: "Move: select, drag to move, handles resize  V"
        case .hand: "Hand: drag to pan the canvas  H"
        case .pen: "Pen: click to add points, click the first to close, Return to finish  P"
        case .text: "Text: click to type, drag to set its width  T"
        default: "\(title): drag on the canvas to draw, Shift keeps it square  \(key)"
        }
    }
}

/// The toolbar along the canvas's foot, as in Figma: Move and Hand, then Frame, Shape, Pen and Text as drawing tools (the
/// arrow next to each also lists ready-made kinds to place at once), Image from the library, Draw with AI and Ask.
struct CanvasToolbar: View {
    let model: DesignModel
    @Bindable var editor: DesignEditor
    @Environment(\.coreAccent) private var paneAccent

    private var current: CanvasTool { CanvasTool(rawValue: editor.tool) ?? .select }
    private var pictures: [DesignAsset] {
        model.assets.filter { $0.loadable && [.image, .icon, .logo].contains($0.kind) }
    }

    var body: some View {
        HStack(spacing: 2) {
            tool(.select)
            tool(.hand)
            divider
            group(
                [.frame], symbol: CanvasTool.frame.symbol, presets: InsertPreset.frames, label: "Frame",
                presetsTitle: "Place a frame")
            group(
                [.rect, .ellipse, .line],
                symbol: [CanvasTool.rect, .ellipse, .line].contains(current) ? current.symbol : CanvasTool.rect.symbol,
                presets: Array(InsertPreset.shapes.dropFirst(3)), label: "Shape", presetsTitle: "Place a shape")
            tool(.pen)
            group(
                [.text], symbol: CanvasTool.text.symbol, presets: InsertPreset.texts, label: "Text",
                presetsTitle: "Place text")
            images
            ComponentsMenu(editor: editor)
            divider
            Button {
                Task { await model.drawWithAI() }
            } label: {
                icon("sparkles", lit: false)
            }
            .buttonStyle(.plain)
            .modifier(ToolHover())
            .disabled(!model.composeSupported || model.readOnly)
            .help(
                model.composeSupported
                    ? "Draw with AI: describe it, AI draws it here" : "This Core cannot draw with AI yet"
            )
            .accessibilityLabel("Draw with AI")
            divider
            ZoomMenu(editor: editor)
            divider
            AskField(editor: editor)
        }
        .padding(Space.s1)
        // Opaque: over a white board a see-through bar washed out.
        .background(GlassInk.adaptive(Color(white: 0.15), day: .white), in: coreShape(Radius.cardMac + 2))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .animation(Motion.out(Motion.hover), value: editor.tool)
        .disabled(!editor.attached || !editor.loaded || model.readOnly || editor.syncHalted)
        .help(editor.loaded ? "" : "The tools work once the design has opened.")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tools")
    }

    private var divider: some View {
        coreShape(1).fill(GlassInk.secondary.opacity(0.25)).frame(width: 1, height: MacSize.controlMd)
            .padding(.horizontal, Space.s1)
    }

    private func icon(_ symbol: String, lit: Bool) -> some View {
        Image(systemName: symbol).coreFont(size: MacTextSize.title)
            .foregroundStyle(lit ? .white : GlassInk.primary)
            .frame(width: MacSize.controlLg + Space.s1, height: MacSize.controlLg + Space.s1)
            .background(lit ? GlassInk.accent(paneAccent) : .clear, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
    }

    private func tool(_ t: CanvasTool) -> some View {
        Button {
            editor.setTool(t)
        } label: {
            icon(t.symbol, lit: current == t)
        }
        .buttonStyle(.plain)
        .modifier(ToolHover())
        .help(t.help)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(current == t ? .isSelected : [])
        .accessibilityIdentifier("design-tool-\(t.title.lowercased())")
    }

    /// A drawing tool with its kinds: a click picks the (first) tool; the arrow lists every tool of the group and the
    /// ready-made kinds that are placed at once.
    private func group(
        _ tools: [CanvasTool], symbol: String, presets: [InsertPreset], label: String, presetsTitle: String
    ) -> some View {
        let lit = tools.contains(current)
        return HStack(spacing: 0) {
            Button {
                editor.setTool(tools.contains(current) ? current : tools[0])
            } label: {
                icon(symbol, lit: lit)
            }
            .buttonStyle(.plain)
            .help(
                tools.count == 1
                    ? tools[0].help : "\(label): \(tools.map { "\($0.title) \($0.key)" }.joined(separator: ", "))"
            )
            .accessibilityLabel(label)
            .accessibilityAddTraits(lit ? .isSelected : [])
            .accessibilityIdentifier("design-tool-\(label.lowercased())")
            Menu {
                ForEach(tools, id: \.rawValue) { t in
                    Button {
                        editor.setTool(t)
                    } label: {
                        Label("\(t.title)    \(t.key)", systemImage: t.symbol)
                    }
                }
                Divider()
                Section(presetsTitle) {
                    ForEach(presets) { p in
                        Button {
                            editor.insert(p)
                        } label: {
                            Label(p.title, systemImage: p.symbol)
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down").coreFont(size: 9, weight: .semibold).foregroundStyle(
                    GlassInk.secondary
                )
                .frame(width: Space.s4, height: MacSize.controlLg + Space.s1).contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More \(label.lowercased()) kinds")
        }
        .modifier(ToolHover())
    }

    @ViewBuilder private var images: some View {
        Menu {
            if pictures.isEmpty {
                Text("No pictures in the library yet")
            }
            ForEach(pictures.prefix(30)) { a in
                Button {
                    Task { await editor.insertImage(a) }
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
            .frame(height: MacSize.controlLg + Space.s1).padding(.horizontal, Space.s2)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .modifier(ToolHover())
        .help("Image: place a picture from the library")
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
