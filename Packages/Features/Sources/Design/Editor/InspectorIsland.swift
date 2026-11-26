import CoreUI
import SwiftUI

/// The inspector (V3-04), laid out like Figma's Design panel: Position (align, X, Y), Layout (auto layout, W, H, resizing,
/// clip), Appearance (opacity, radius, blend, material), Fill (several, solid or gradient), Stroke, Effects (drop
/// shadows), Typography and Overrides. Every control writes edit ops through `DesignEditor.set` (one undo step each, all
/// selected nodes of that type) and shows what the node holds now, so a canvas drag or an AI edit shows up at once.
struct InspectorIsland: View {
    let editor: DesignEditor

    var body: some View {
        Group {
            if let n = editor.node {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(n)
                        if n.type != "page" { position(n) }
                        if n.type != "page" { layout(n) }
                        if n.type != "page" { appearance(n) }
                        fill(n)
                        if n.type != "page" { stroke(n) }
                        if n.type != "page" { effects(n) }
                        if n.type == "text" { typography(n) }
                        if n.type == "instance" { overrides(n) }
                        if n.type != "page" { PrototypeBlock(editor: editor, node: n) }
                    }
                    // A new selection fades its sections in; edits to the same node change in place.
                    .id(n.id)
                    .transition(.opacity)
                }
                .scrollIndicators(.never)
            } else {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Nothing selected").coreFont(size: MacTextSize.body, weight: .semibold)
                    Text("Click something on the canvas, pick a layer, or add one from the toolbar.")
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Motion.out(Motion.ui), value: editor.node?.id)
        .accessibilityIdentifier("design-inspector")
    }

    private func num(_ n: EditorNode, _ key: String) -> Double? { n.props[key]?.double }
    private func pair<A: View, B: View>(_ a: A, _ b: B) -> some View {
        HStack(spacing: Space.s2) {
            a
            b
        }
    }

    // MARK: header

    private func header(_ n: EditorNode) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(n.name.isEmpty ? n.type.capitalizedFirst : n.name).coreFont(
                    size: MacTextSize.title, weight: .semibold
                )
                .lineLimit(1).help(n.name)
                Text(
                    editor.selection.count > 1
                        ? "\(editor.selection.count) selected · changes apply to every \(n.type)"
                        : n.type.capitalizedFirst
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
            Spacer(minLength: 0)
            if n.type != "page" {
                let hidden = n.props["visible"]?.bool == false
                InspectorIcon(symbol: hidden ? "eye.slash" : "eye", label: hidden ? "Show Layer" : "Hide Layer") {
                    editor.setHidden(n.id, !hidden)
                }
            }
        }
        .padding(.bottom, Space.s3)
    }

    // MARK: position

    private func position(_ n: EditorNode) -> some View {
        let parent = n.parent.flatMap { editor.node(of: $0) }
        let pw = parent?.props["w"]?.double
        let ph = parent?.props["h"]?.double
        let w = num(n, "w") ?? 0
        let h = num(n, "h") ?? 0
        return InspectorBlock("Position") {
            if let pw, let ph {
                HStack(spacing: Space.s2) {
                    alignRow([
                        ("align.horizontal.left", "Align left", { editor.set("x", .number(0)) }),
                        (
                            "align.horizontal.center", "Align centre",
                            { editor.set("x", .number(((pw - w) / 2).rounded())) }
                        ),
                        ("align.horizontal.right", "Align right", { editor.set("x", .number(pw - w)) }),
                    ])
                    alignRow([
                        ("align.vertical.top", "Align top", { editor.set("y", .number(0)) }),
                        (
                            "align.vertical.center", "Align middle",
                            { editor.set("y", .number(((ph - h) / 2).rounded())) }
                        ),
                        ("align.vertical.bottom", "Align bottom", { editor.set("y", .number(ph - h)) }),
                    ])
                }
            }
            pair(
                InlineNumber(label: "X", value: num(n, "x")) {
                    editor.set("x", DesignOptions.snap($0).map { .number($0) })
                },
                InlineNumber(label: "Y", value: num(n, "y")) {
                    editor.set("y", DesignOptions.snap($0).map { .number($0) })
                })
        }
    }

    private func alignRow(_ items: [(String, String, () -> Void)]) -> some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                Button(action: items[i].2) {
                    Image(systemName: items[i].0).coreFont(size: MacTextSize.body)
                        .frame(maxWidth: .infinity, minHeight: MacSize.controlMd + 2)
                        .contentShape(coreShape(Radius.control))
                }
                .buttonStyle(.plain).help(items[i].1).accessibilityLabel(items[i].1)
            }
        }
        .padding(2)
        .background(GlassInk.well, in: coreShape(Radius.control + 2))
    }

    // MARK: layout

    @ViewBuilder private func layout(_ n: EditorNode) -> some View {
        let l = n.props["layout"]
        let sizing = n.props["sizing"]
        InspectorBlock("Layout") {
            if n.isContainer {
                IconChoices(
                    choices: [
                        ("none", "square.dashed", "No auto layout"), ("column", "arrow.down", "Auto layout, vertical"),
                        ("row", "arrow.right", "Auto layout, horizontal"),
                    ],
                    current: n.hasLayout ? (l?["dir"]?.string ?? "column") : "none"
                ) { dir in
                    editor.set("layout", dir == "none" ? nil : InspectorEdits.layout(n, "dir", .string(dir)))
                }
            }
            pair(
                InlineNumber(label: "W", value: num(n, "w")) {
                    editor.set("w", DesignOptions.snap($0).map { .number(max(0, $0)) })
                },
                InlineNumber(label: "H", value: num(n, "h")) {
                    editor.set("h", DesignOptions.snap($0).map { .number(max(0, $0)) })
                })
            pair(
                InlineMenu(label: "W", value: sizing?["w"]?.string ?? "fixed", choices: ["fixed", "hug", "fill"]) {
                    editor.set("sizing", InspectorEdits.sizing(n, "w", $0))
                },
                InlineMenu(label: "H", value: sizing?["h"]?.string ?? "fixed", choices: ["fixed", "hug", "fill"]) {
                    editor.set("sizing", InspectorEdits.sizing(n, "h", $0))
                })
            if n.hasLayout {
                pair(
                    InlineNumber(label: "Gap", value: l?["gap"]?.double) {
                        editor.set("layout", InspectorEdits.layout(n, "gap", $0.map { .number(max(0, $0)) }))
                    },
                    InlineNumber(label: "Pad", value: InspectorEdits.padValue(n)) {
                        editor.set("layout", InspectorEdits.layout(n, "pad", $0.map { InspectorEdits.pad(max(0, $0)) }))
                    })
                pair(
                    InlineMenu(
                        label: "Align", value: l?["align"]?.string ?? "start",
                        choices: ["start", "center", "end", "stretch"]
                    ) { editor.set("layout", InspectorEdits.layout(n, "align", .string($0))) },
                    InlineMenu(
                        label: "Justify", value: l?["justify"]?.string ?? "start",
                        choices: ["start", "center", "end", "between"]
                    ) { editor.set("layout", InspectorEdits.layout(n, "justify", .string($0))) })
            }
            if n.isContainer {
                Toggle(
                    "Clip content",
                    isOn: Binding(get: { n.props["clip"]?.bool == true }, set: { editor.set("clip", .bool($0)) })
                )
                .toggleStyle(.checkbox)
            }
        }
    }

    // MARK: appearance

    @ViewBuilder private func appearance(_ n: EditorNode) -> some View {
        let rounds = ["frame", "rect", "image", "component", "instance"].contains(n.type)
        InspectorBlock("Appearance") {
            pair(
                InlineNumber(label: "Opacity", value: num(n, "opacity") ?? 1, suffix: "%", scale: 100) {
                    editor.set("opacity", $0.map { .number(min(1, max(0, $0))) })
                },
                Group {
                    if rounds, n.props["radius"]?.tokenName == nil {
                        InlineNumber(
                            label: "Radius", value: n.props["radius"]?.double ?? n.props["radius"]?.array?.first?.double
                        ) { editor.set("radius", $0.map { .number(max(0, $0)) }) }
                    } else {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                })
            if rounds {
                TokenSelect(label: "Radius token", kind: "radius", current: n.props["radius"], tokens: editor.tokens) {
                    editor.set("radius", $0.map(DJSON.token) ?? InspectorEdits.literal(kind: "radius"))
                }
            }
            pair(
                InlineMenu(
                    label: "Blend", value: n.props["blend"]?.string ?? "normal",
                    choices: ["normal", "multiply", "screen", "overlay", "darken", "lighten"]
                ) { editor.set("blend", $0 == "normal" ? nil : .string($0)) },
                Group {
                    if ["frame", "rect", "component", "instance"].contains(n.type),
                        n.props["material"]?.tokenName == nil
                    {
                        InlineMenu(
                            label: "Material", value: n.props["material"]?.string ?? "none",
                            choices: ["none", "glass", "well", "clear"]
                        ) { editor.set("material", $0 == "none" ? nil : .string($0)) }
                    } else {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                })
        }
    }

    // MARK: fill

    @ViewBuilder private func fill(_ n: EditorNode) -> some View {
        let fills = InspectorEdits.fills(n)
        InspectorBlock("Fill") {
            Menu {
                Button("Solid") { editor.set("fill", .array(fills + [InsertPreset.grey.array?.first ?? .null])) }
                Button("Linear gradient") { editor.set("fill", .array(fills + [Self.gradient])) }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Add a fill").accessibilityLabel("Add a fill")
        } content: {
            if let first = fills.first, first["type"]?.string == "solid" {
                TokenSelect(label: "Colour token", kind: "color", current: first["color"], tokens: editor.tokens) {
                    editor.set(
                        "fill",
                        InspectorEdits.fill(n, color: $0.map(DJSON.token) ?? InspectorEdits.literal(kind: "color")))
                }
            }
            ForEach(fills.indices, id: \.self) { i in
                HStack(spacing: Space.s1) {
                    fillRow(fills[i]) { editor.set("fill", .array(Self.replacing(fills, i, $0))) }
                    InspectorIcon(symbol: "minus", label: "Remove this fill") {
                        var rest = fills
                        rest.remove(at: i)
                        editor.set("fill", rest.isEmpty ? nil : .array(rest))
                    }
                }
            }
        }
    }

    static let gradient = DJSON.object([
        "type": .string("linear"), "angle": .number(90),
        "stops": .array([
            .object(["at": .number(0), "color": .string("#4f46e5")]),
            .object(["at": .number(1), "color": .string("#ec4899")]),
        ]),
    ])

    static func replacing(_ all: [DJSON], _ i: Int, _ v: DJSON) -> [DJSON] {
        var a = all
        a[i] = v
        return a
    }

    @ViewBuilder private func fillRow(_ f: DJSON, set: @escaping (DJSON) -> Void) -> some View {
        switch f["type"]?.string {
        case "solid":
            if let name = f["color"]?.tokenName {
                Label(name, systemImage: "swatchpalette").frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ColorField(hex: f["color"]?.string) { set(.object(["type": .string("solid"), "color": .string($0)])) }
            }
        case "linear":
            let stops = f["stops"]?.array ?? []
            HStack(spacing: Space.s1) {
                ForEach(stops.indices, id: \.self) { s in
                    ColorField(hex: stops[s]["color"]?.string) { hex in
                        var o = f.object ?? [:]
                        var st = stops
                        var stop = st[s].object ?? [:]
                        stop["color"] = .string(hex)
                        st[s] = .object(stop)
                        o["stops"] = .array(st)
                        set(.object(o))
                    }
                }
            }
        default:
            Label("Image", systemImage: "photo").frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: stroke

    @ViewBuilder private func stroke(_ n: EditorNode) -> some View {
        let s = n.props["stroke"]
        InspectorBlock("Stroke") {
            if s == nil {
                InspectorIcon(symbol: "plus", label: "Add a stroke") {
                    editor.set(
                        "stroke", .object(["color": .string("#111111"), "width": .number(1)]))
                }
            }
        } content: {
            if let s {
                HStack(spacing: Space.s1) {
                    if s["color"]?.tokenName == nil {
                        ColorField(hex: s["color"]?.string) {
                            editor.set("stroke", InspectorEdits.stroke(n, "color", .string($0)))
                        }
                    }
                    InlineNumber(label: "W", value: s["width"]?.double) {
                        editor.set("stroke", InspectorEdits.stroke(n, "width", .number(max(0, $0 ?? 1))))
                    }
                    .frame(width: Space.s8 * 2 + Space.s2)
                    InspectorIcon(symbol: "minus", label: "Remove the stroke") { editor.set("stroke", nil) }
                }
                TokenSelect(label: "Colour token", kind: "color", current: s["color"], tokens: editor.tokens) {
                    editor.set(
                        "stroke",
                        InspectorEdits.stroke(n, "color", $0.map(DJSON.token) ?? InspectorEdits.literal(kind: "color"))
                    )
                }
            }
        }
    }

    // MARK: effects

    @ViewBuilder private func effects(_ n: EditorNode) -> some View {
        let list = n.props["shadow"]?.tokenName == nil ? (n.props["shadow"]?.array ?? []) : []
        InspectorBlock("Effects") {
            InspectorIcon(symbol: "plus", label: "Add a drop shadow") {
                editor.set("shadow", .array(list + [Self.shadow]))
            }
        } content: {
            if let name = n.props["shadow"]?.tokenName {
                Label(name, systemImage: "swatchpalette")
            }
            ForEach(list.indices, id: \.self) { i in
                let sh = list[i]
                let put = { (k: String, v: DJSON) in
                    var o = sh.object ?? [:]
                    o[k] = v
                    editor.set("shadow", .array(Self.replacing(list, i, .object(o))))
                }
                VStack(spacing: Space.s1) {
                    HStack(spacing: Space.s1) {
                        Text("Drop shadow").coreFont(size: MacTextSize.meta, weight: .medium)
                        Spacer(minLength: 0)
                        InspectorIcon(symbol: "minus", label: "Remove this shadow") {
                            var rest = list
                            rest.remove(at: i)
                            editor.set("shadow", rest.isEmpty ? nil : .array(rest))
                        }
                    }
                    pair(
                        InlineNumber(label: "X", value: sh["x"]?.double) { put("x", .number($0 ?? 0)) },
                        InlineNumber(label: "Y", value: sh["y"]?.double) { put("y", .number($0 ?? 0)) })
                    pair(
                        InlineNumber(label: "Blur", value: sh["blur"]?.double) {
                            put("blur", .number(max(0, $0 ?? 0)))
                        },
                        InlineNumber(label: "Spread", value: sh["spread"]?.double) { put("spread", .number($0 ?? 0)) })
                    ColorField(hex: sh["color"]?.string) { put("color", .string($0)) }
                }
            }
        }
    }

    static let shadow = DJSON.object([
        "x": .number(0), "y": .number(4), "blur": .number(12), "spread": .number(0), "color": .string("#00000040"),
    ])

    // MARK: typography

    @ViewBuilder private func typography(_ n: EditorNode) -> some View {
        let t = n.props["type"]
        InspectorBlock("Typography") {
            TokenSelect(label: "Style token", kind: "type", current: t, tokens: editor.tokens) {
                editor.set("type", $0.map(DJSON.token) ?? InspectorEdits.literal(kind: "type"))
            }
            if t?.tokenName == nil {
                FontRow(editor: editor, node: n)
                pair(
                    InlineNumber(label: "Size", value: t?["size"]?.double) {
                        if let v = $0 { editor.set("type", InspectorEdits.type(n, "size", .number(max(1, v)))) }
                    },
                    InlineMenu(
                        label: "Weight", value: t?["weight"]?.double.map { String(Int($0)) } ?? "400",
                        choices: ["300", "400", "500", "600", "700", "800"]
                    ) { editor.set("type", InspectorEdits.type(n, "weight", .number(Double($0) ?? 400))) })
                pair(
                    InlineNumber(label: "Line", value: t?["line"]?.double, clearable: true) {
                        editor.set("type", InspectorEdits.type(n, "line", $0.map { .number(max(0, $0)) } ?? .null))
                    },
                    InlineNumber(
                        label: "Spacing", value: t?["tracking"]?.double, suffix: "%", scale: 100, clearable: true
                    ) {
                        editor.set(
                            "type", InspectorEdits.type(n, "tracking", $0.map { .number(min(1, max(-1, $0))) } ?? .null)
                        )
                    })
                pair(
                    IconChoices(
                        choices: [
                            ("left", "text.alignleft", "Align left"), ("center", "text.aligncenter", "Align centre"),
                            ("right", "text.alignright", "Align right"),
                        ],
                        current: t?["align"]?.string ?? "left"
                    ) { editor.set("type", InspectorEdits.type(n, "align", .string($0))) },
                    InlineMenu(
                        label: "Case", value: t?["transform"]?.string ?? "none",
                        choices: ["none", "uppercase", "lowercase", "capitalize"]
                    ) { editor.set("type", InspectorEdits.type(n, "transform", .string($0))) })
            }
            Text("Double-click the text on the canvas to edit it.").coreFont(size: MacTextSize.meta)
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: overrides

    @ViewBuilder private func overrides(_ n: EditorNode) -> some View {
        let list = InspectorEdits.overridePaths(n)
        InspectorBlock("Overrides") {
            if list.isEmpty {
                Text("This instance follows its component exactly.").foregroundStyle(GlassInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(list, id: \.path) { o in
                CoreRow(
                    o.path == "." ? "This instance" : o.path, subtitle: Words.count(o.props, "change"),
                    symbol: "arrow.triangle.branch"
                ) {
                    CoreIconButton(symbol: "arrow.uturn.backward", label: "Remove Override") {
                        editor.set("overrides", InspectorEdits.overrides(n, removing: o.path))
                    }
                }
            }
        }
    }
}
