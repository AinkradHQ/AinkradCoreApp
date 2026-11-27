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
                ScrollViewReader { reader in
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
                            ApprovalBlock(editor: editor, node: n)
                        }
                        // A new selection fades its sections in; edits to the same node change in place.
                        .id(n.id)
                        .transition(.opacity)
                    }
                    .scrollIndicators(.never)
                    #if DEBUG
                    // Debug only: the snapshot walk scrolls to a section (`DesignEditor.inspectorScroll`).
                    .onChange(of: editor.inspectorScroll) { _, section in
                        if let section { reader.scrollTo(section, anchor: .top) }
                    }
                    #endif
                }
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
    /// The selected layers of this type disagree on this value.
    private func mx(_ f: (EditorNode) -> DJSON?) -> Bool { editor.mixed(f) }
    private func mixedProp(_ key: String) -> Bool { mx { $0.props[key] } }
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
                let locked = n.props["locked"]?.bool == true
                InspectorIcon(symbol: locked ? "lock.fill" : "lock.open", label: locked ? "Unlock Layer" : "Lock Layer")
                {
                    editor.setLocked(editor.selection.filter { editor.layers[$0]?.type != "page" }, !locked)
                }
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
        let many = editor.selection.count > 1
        let parent = n.parent.flatMap { editor.node(of: $0) }
        let canAlign = many || (parent?.props["w"]?.double != nil && parent?.props["h"]?.double != nil)
        return InspectorBlock("Position") {
            if canAlign {
                HStack(spacing: Space.s2) {
                    alignRow([
                        ("align.horizontal.left", "Align left", { editor.align(.left) }),
                        ("align.horizontal.center", "Align centre", { editor.align(.centerX) }),
                        ("align.horizontal.right", "Align right", { editor.align(.right) }),
                    ])
                    alignRow([
                        ("align.vertical.top", "Align top", { editor.align(.top) }),
                        ("align.vertical.center", "Align middle", { editor.align(.centerY) }),
                        ("align.vertical.bottom", "Align bottom", { editor.align(.bottom) }),
                    ])
                }
                if editor.selection.count >= 3 {
                    alignRow([
                        ("rectangle.split.3x1", "Distribute horizontally", { editor.distribute(horizontal: true) }),
                        ("rectangle.split.1x3", "Distribute vertically", { editor.distribute(horizontal: false) }),
                    ])
                }
            }
            // Typed values are exact: the grid snaps drags, never a number someone typed.
            pair(
                InlineNumber(label: "X", value: num(n, "x"), mixed: mixedProp("x")) {
                    editor.set("x", $0.map { .number($0) })
                },
                InlineNumber(label: "Y", value: num(n, "y"), mixed: mixedProp("y")) {
                    editor.set("y", $0.map { .number($0) })
                })
            pair(
                InlineNumber(label: "Rotate", value: num(n, "rotation") ?? 0, suffix: "°") {
                    // 0 is "not rotated": the prop goes away, like every other default.
                    let deg = min(360, max(-360, $0 ?? 0))
                    editor.set("rotation", deg == 0 ? nil : .number(deg))
                },
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1))
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
                    editor.setEach("layout") { dir == "none" ? nil : InspectorEdits.layout($0, "dir", .string(dir)) }
                }
            }
            pair(
                InlineNumber(label: "W", value: num(n, "w"), mixed: mixedProp("w")) {
                    editor.set("w", $0.map { .number(max(0, $0)) })
                },
                InlineNumber(label: "H", value: num(n, "h"), mixed: mixedProp("h")) {
                    editor.set("h", $0.map { .number(max(0, $0)) })
                })
            pair(
                InlineMenu(
                    label: "W", value: sizing?["w"]?.string ?? "fixed", choices: ["fixed", "hug", "fill"],
                    mixed: mx { $0.props["sizing"]?["w"] }
                ) { pick in editor.setEach("sizing") { InspectorEdits.sizing($0, "w", pick) } },
                InlineMenu(
                    label: "H", value: sizing?["h"]?.string ?? "fixed", choices: ["fixed", "hug", "fill"],
                    mixed: mx { $0.props["sizing"]?["h"] }
                ) { pick in editor.setEach("sizing") { InspectorEdits.sizing($0, "h", pick) } })
            if n.hasLayout {
                pair(
                    InlineNumber(label: "Gap", value: l?["gap"]?.double, mixed: mx { $0.props["layout"]?["gap"] }) { v in
                        editor.setEach("layout") { InspectorEdits.layout($0, "gap", v.map { .number(max(0, $0)) }) }
                    },
                    InlineNumber(label: "Pad", value: InspectorEdits.padValue(n), mixed: mx { $0.props["layout"]?["pad"] }) {
                        v in
                        editor.setEach("layout") {
                            InspectorEdits.layout($0, "pad", v.map { InspectorEdits.pad(max(0, $0)) })
                        }
                    })
                pair(
                    InlineMenu(
                        label: "Align", value: l?["align"]?.string ?? "start",
                        choices: ["start", "center", "end", "stretch"], mixed: mx { $0.props["layout"]?["align"] }
                    ) { pick in editor.setEach("layout") { InspectorEdits.layout($0, "align", .string(pick)) } },
                    InlineMenu(
                        label: "Justify", value: l?["justify"]?.string ?? "start",
                        choices: ["start", "center", "end", "between"], mixed: mx { $0.props["layout"]?["justify"] }
                    ) { pick in editor.setEach("layout") { InspectorEdits.layout($0, "justify", .string(pick)) } })
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
                InlineNumber(
                    label: "Opacity", value: num(n, "opacity") ?? 1, suffix: "%", scale: 100, mixed: mixedProp("opacity")
                ) {
                    editor.set("opacity", $0.map { .number(min(1, max(0, $0))) })
                },
                Group {
                    if rounds, n.props["radius"]?.tokenName == nil {
                        // Per-corner radii (an array that is not all the same) show as Mixed and are only replaced when
                        // the person types a single value.
                        InlineNumber(
                            label: "Radius", value: n.props["radius"]?.double ?? n.props["radius"]?.array?.first?.double,
                            mixed: mixedProp("radius") || Self.cornersDiffer(n)
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
                    choices: ["normal", "multiply", "screen", "overlay", "darken", "lighten"], mixed: mixedProp("blend")
                ) { editor.set("blend", $0 == "normal" ? nil : .string($0)) },
                Group {
                    if ["frame", "rect", "component", "instance"].contains(n.type),
                        n.props["material"]?.tokenName == nil
                    {
                        InlineMenu(
                            label: "Material", value: n.props["material"]?.string ?? "none",
                            choices: ["none", "glass", "well", "clear"], mixed: mixedProp("material")
                        ) { editor.set("material", $0 == "none" ? nil : .string($0)) }
                    } else {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                })
        }
    }

    /// A radius written per corner whose corners differ.
    static func cornersDiffer(_ n: EditorNode) -> Bool {
        guard let a = n.props["radius"]?.array?.compactMap(\.double), let f = a.first else { return false }
        return a.contains { $0 != f }
    }

    // MARK: fill

    @ViewBuilder private func fill(_ n: EditorNode) -> some View {
        let fills = InspectorEdits.fills(n)
        InspectorBlock("Fill") {
            Menu {
                Button("Solid") {
                    editor.setEach("fill") { .array(InspectorEdits.fills($0) + [InsertPreset.grey.array?.first ?? .null]) }
                }
                Button("Linear gradient") {
                    editor.setEach("fill") { .array(InspectorEdits.fills($0) + [Self.gradient]) }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Add a fill").accessibilityLabel("Add a fill")
        } content: {
            if let first = fills.first, first["type"]?.string == "solid" {
                TokenSelect(label: "Colour token", kind: "color", current: first["color"], tokens: editor.tokens) {
                    let c = $0.map(DJSON.token) ?? InspectorEdits.literal(kind: "color")
                    editor.setEach("fill") { InspectorEdits.fill($0, color: c) }
                }
            }
            ForEach(fills.indices, id: \.self) { i in
                HStack(spacing: Space.s1) {
                    fillRow(fills[i], mixed: mx { InspectorEdits.fills($0).indices.contains(i) ? InspectorEdits.fills($0)[i] : nil }) {
                        new in
                        editor.setEach("fill") { node in
                            let all = InspectorEdits.fills(node)
                            return all.indices.contains(i) ? .array(Self.merging(all, i, new)) : .array(all)
                        }
                    }
                    InspectorIcon(symbol: "minus", label: "Remove this fill") {
                        editor.setEach("fill") { node in
                            var rest = InspectorEdits.fills(node)
                            if rest.indices.contains(i) { rest.remove(at: i) }
                            return rest.isEmpty ? nil : .array(rest)
                        }
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

    /// Puts what the inspector edited of fill `i` onto the node's own fill: a solid replaces it; a gradient takes only the
    /// stop colours that were edited, keeping each node's own angle and stops.
    static func merging(_ all: [DJSON], _ i: Int, _ new: DJSON) -> [DJSON] {
        guard new["type"]?.string == "linear", all[i]["type"]?.string == "linear",
            let ns = new["stops"]?.array, var os = all[i]["stops"]?.array, ns.count == os.count
        else { return replacing(all, i, new) }
        for k in os.indices {
            var o = os[k].object ?? [:]
            o["color"] = ns[k]["color"]
            os[k] = .object(o)
        }
        var g = all[i].object ?? [:]
        g["stops"] = .array(os)
        return replacing(all, i, .object(g))
    }

    @ViewBuilder private func fillRow(_ f: DJSON, mixed: Bool, set: @escaping (DJSON) -> Void) -> some View {
        switch f["type"]?.string {
        case "solid":
            if let name = f["color"]?.tokenName {
                Label(name, systemImage: "swatchpalette").frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ColorField(hex: f["color"]?.string, mixed: mixed) {
                    set(.object(["type": .string("solid"), "color": .string($0)]))
                }
            }
        case "linear":
            let stops = f["stops"]?.array ?? []
            HStack(spacing: Space.s1) {
                ForEach(stops.indices, id: \.self) { s in
                    ColorField(hex: stops[s]["color"]?.string, mixed: mixed) { hex in
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
        let list = InspectorEdits.strokes(n)
        // Each selected layer keeps its own other strokes and fields: only the one that was edited is written.
        let change = { (_ edit: @escaping ([DJSON]) -> [DJSON]) in
            editor.setEach("stroke") { InspectorEdits.strokeValue(edit(InspectorEdits.strokes($0))) }
        }
        let field = { (i: Int, k: String) -> Bool in
            mx { node in
                let l = InspectorEdits.strokes(node)
                return l.indices.contains(i) ? l[i][k] : nil
            }
        }
        InspectorBlock("Stroke") {
            if list.count < InspectorEdits.maxStrokes {
                InspectorIcon(symbol: "plus", label: "Add a stroke") {
                    change { $0.count < InspectorEdits.maxStrokes ? $0 + [InspectorEdits.newStroke] : $0 }
                }
            }
        } content: {
            ForEach(list.indices, id: \.self) { i in
                let s = list[i]
                let put = { (k: String, v: DJSON?) in
                    change { $0.indices.contains(i) ? InspectorEdits.stroking($0, i, k, v) : $0 }
                }
                VStack(spacing: Space.s1) {
                    HStack(spacing: Space.s1) {
                        if s["color"]?.tokenName == nil {
                            ColorField(hex: s["color"]?.string, mixed: field(i, "color")) { put("color", .string($0)) }
                        }
                        InlineNumber(label: "W", value: s["width"]?.double, mixed: field(i, "width")) {
                            put("width", .number(max(0, $0 ?? 1)))
                        }
                            .frame(width: Space.s8 * 2 + Space.s2)
                        InspectorIcon(symbol: "minus", label: "Remove this stroke") {
                            change { all in
                                var rest = all
                                if rest.indices.contains(i) { rest.remove(at: i) }
                                return rest
                            }
                        }
                    }
                    pair(
                        InlineMenu(
                            label: "Align", value: s["align"]?.string ?? "inside",
                            choices: ["inside", "center", "outside"], mixed: field(i, "align")
                        ) { put("align", .string($0)) },
                        InlineMenu(
                            label: "Dash", value: InspectorEdits.dashName(s), choices: ["solid", "dashed", "dotted"],
                            mixed: field(i, "dash")
                        ) { put("dash", InspectorEdits.dash($0, width: s["width"]?.double ?? 1)) })
                    TokenSelect(label: "Colour token", kind: "color", current: s["color"], tokens: editor.tokens) {
                        put("color", $0.map(DJSON.token) ?? InspectorEdits.literal(kind: "color"))
                    }
                }
            }
        }
    }

    // MARK: effects

    @ViewBuilder private func effects(_ n: EditorNode) -> some View {
        let list = n.props["shadow"]?.tokenName == nil ? (n.props["shadow"]?.array ?? []) : []
        InspectorBlock("Effects") {
            Menu {
                Button("Drop shadow") { addShadow(Self.shadow) }
                Button("Inner shadow") { addShadow(Self.merging(Self.shadow, ["inset": .bool(true), "y": .number(2)])) }
                Button("Layer blur") { editor.set("blur", .number(8)) }.disabled(n.props["blur"] != nil)
                Button("Background blur") { editor.set("backdrop_blur", .number(16)) }
                    .disabled(n.props["backdrop_blur"] != nil)
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Add an effect").accessibilityLabel("Add an effect")
        } content: {
            if let name = n.props["shadow"]?.tokenName {
                Label(name, systemImage: "swatchpalette")
            }
            ForEach(list.indices, id: \.self) { i in
                let sh = list[i]
                let inset = InspectorEdits.isInset(sh)
                let put = { (k: String, v: DJSON?) in
                    editor.setEach("shadow") { node in
                        let all = node.props["shadow"]?.array ?? []
                        guard all.indices.contains(i) else { return node.props["shadow"] }
                        var o = all[i].object ?? [:]
                        o[k] = v
                        return .array(Self.replacing(all, i, .object(o)))
                    }
                }
                let mxs = { (k: String) -> Bool in mx { $0.props["shadow"]?.array?[safe: i]?[k] } }
                VStack(spacing: Space.s1) {
                    HStack(spacing: Space.s1) {
                        Text(inset ? "Inner shadow" : "Drop shadow").coreFont(size: MacTextSize.meta, weight: .medium)
                        Spacer(minLength: 0)
                        InspectorIcon(symbol: "minus", label: "Remove this shadow") {
                            editor.setEach("shadow") { node in
                                var rest = node.props["shadow"]?.array ?? []
                                if rest.indices.contains(i) { rest.remove(at: i) }
                                return rest.isEmpty ? nil : .array(rest)
                            }
                        }
                    }
                    pair(
                        InlineNumber(label: "X", value: sh["x"]?.double, mixed: mxs("x")) { put("x", .number($0 ?? 0)) },
                        InlineNumber(label: "Y", value: sh["y"]?.double, mixed: mxs("y")) { put("y", .number($0 ?? 0)) })
                    pair(
                        InlineNumber(label: "Blur", value: sh["blur"]?.double, mixed: mxs("blur")) {
                            put("blur", .number(max(0, $0 ?? 0)))
                        },
                        InlineNumber(label: "Spread", value: sh["spread"]?.double, mixed: mxs("spread")) {
                            put("spread", .number($0 ?? 0))
                        })
                    ColorField(hex: sh["color"]?.string, mixed: mxs("color")) { put("color", .string($0)) }
                    Toggle("Inner shadow", isOn: Binding(get: { inset }, set: { put("inset", $0 ? .bool(true) : nil) }))
                        .toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            blurRow(n, key: "blur", label: "Layer blur", help: "Blurs the layer itself")
            blurRow(n, key: "backdrop_blur", label: "Background blur", help: "Blurs what is behind the layer")
        }
    }

    @ViewBuilder private func blurRow(_ n: EditorNode, key: String, label: String, help: String) -> some View {
        if let v = num(n, key) {
            HStack(spacing: Space.s1) {
                InlineNumber(label: label, value: v) { editor.set(key, .number(min(1000, max(0, $0 ?? 0)))) }
                    .help(help)
                InspectorIcon(symbol: "minus", label: "Remove \(label.lowercased())") { editor.set(key, nil) }
            }
        }
    }

    /// Appends a shadow to every selected layer's own list.
    private func addShadow(_ shadow: DJSON) {
        editor.setEach("shadow") { node in
            .array((node.props["shadow"]?.tokenName == nil ? (node.props["shadow"]?.array ?? []) : []) + [shadow])
        }
    }

    private static func merging(_ base: DJSON, _ extra: [String: DJSON]) -> DJSON {
        .object((base.object ?? [:]).merging(extra) { _, new in new })
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
                    InlineNumber(label: "Size", value: t?["size"]?.double, mixed: mx { $0.props["type"]?["size"] }) {
                        if let v = $0 { editor.setEach("type") { InspectorEdits.type($0, "size", .number(max(1, v))) } }
                    },
                    InlineMenu(
                        label: "Weight", value: t?["weight"]?.double.map { String(Int($0)) } ?? "400",
                        choices: ["300", "400", "500", "600", "700", "800"], mixed: mx { $0.props["type"]?["weight"] }
                    ) { pick in
                        editor.setEach("type") { InspectorEdits.type($0, "weight", .number(Double(pick) ?? 400)) }
                    })
                pair(
                    InlineNumber(
                        label: "Line", value: t?["line"]?.double, clearable: true, mixed: mx { $0.props["type"]?["line"] }
                    ) { v in
                        editor.setEach("type") {
                            InspectorEdits.type($0, "line", v.map { .number(max(0, $0)) } ?? .null)
                        }
                    },
                    InlineNumber(
                        label: "Spacing", value: t?["tracking"]?.double, suffix: "%", scale: 100, clearable: true,
                        mixed: mx { $0.props["type"]?["tracking"] }
                    ) { v in
                        editor.setEach("type") {
                            InspectorEdits.type($0, "tracking", v.map { .number(min(1, max(-1, $0))) } ?? .null)
                        }
                    })
                pair(
                    IconChoices(
                        choices: [
                            ("left", "text.alignleft", "Align left"), ("center", "text.aligncenter", "Align centre"),
                            ("right", "text.alignright", "Align right"),
                        ],
                        current: t?["align"]?.string ?? "left"
                    ) { v in editor.setEach("type") { InspectorEdits.type($0, "align", .string(v)) } },
                    InlineMenu(
                        label: "Case", value: t?["transform"]?.string ?? "none",
                        choices: ["none", "uppercase", "lowercase", "capitalize"], mixed: mx { $0.props["type"]?["transform"] }
                    ) { pick in editor.setEach("type") { InspectorEdits.type($0, "transform", .string(pick)) } })
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

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
