import CoreUI
import SwiftUI

/// The inspector (V3-04): the selected node's layout, size, fill, stroke, radius, material, type, token pickers and
/// overrides. Every control writes edit ops through `DesignEditor.set` (one undo step each, all selected nodes of that type),
/// and shows what the node holds now, so a canvas drag or an AI edit shows up here at once.
struct InspectorIsland: View {
    let editor: DesignEditor

    var body: some View {
        Group {
            if let n = editor.node {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s5) {
                        header(n)
                        if n.isContainer { layout(n) }
                        if n.type != "page" { size(n) }
                        appearance(n)
                        fill(n)
                        if n.type != "page" { stroke(n) }
                        if n.type == "text" { typeStyle(n) }
                        if n.type == "instance" { overrides(n) }
                    }
                }
                .scrollIndicators(.automatic)
            } else {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Nothing selected").coreFont(size: MacTextSize.body, weight: .semibold)
                    Text("Click something on the canvas, or pick a layer.").foregroundStyle(GlassInk.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("design-inspector")
    }

    private func header(_ n: EditorNode) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(n.name.isEmpty ? n.type.capitalizedFirst : n.name).coreFont(size: MacTextSize.title, weight: .semibold)
                .lineLimit(1).help(n.name)
            Text(
                editor.selection.count > 1
                    ? "\(editor.selection.count) selected. Changes apply to every \(n.type)."
                    : n.type.capitalizedFirst
            )
            .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func num(_ n: EditorNode, _ key: String) -> Double? { n.props[key]?.double }

    // MARK: layout

    @ViewBuilder private func layout(_ n: EditorNode) -> some View {
        InspectorSection(title: "Layout") {
            CoreSwitch(
                "Auto layout",
                isOn: Binding(
                    get: { n.hasLayout },
                    set: { editor.set("layout", $0 ? InspectorEdits.layout(n, "dir", .string("column")) : nil) }))
            if n.hasLayout {
                let l = n.props["layout"]
                ChoiceRow(label: "Direction", value: l?["dir"]?.string, choices: ["row", "column"]) {
                    editor.set("layout", InspectorEdits.layout(n, "dir", .string($0)))
                }
                NumberRow(label: "Gap", value: l?["gap"]?.double, suffix: "pt") {
                    editor.set("layout", InspectorEdits.layout(n, "gap", $0.map { .number($0) }))
                }
                NumberRow(label: "Padding", value: InspectorEdits.padValue(n), suffix: "pt") {
                    editor.set("layout", InspectorEdits.layout(n, "pad", $0.map(InspectorEdits.pad)))
                }
                ChoiceRow(label: "Align", value: l?["align"]?.string, choices: ["start", "center", "end", "stretch"]) {
                    editor.set("layout", InspectorEdits.layout(n, "align", .string($0)))
                }
                ChoiceRow(
                    label: "Justify", value: l?["justify"]?.string, choices: ["start", "center", "end", "between"]
                ) {
                    editor.set("layout", InspectorEdits.layout(n, "justify", .string($0)))
                }
                CoreSwitch(
                    "Wrap",
                    isOn: Binding(
                        get: { l?["wrap"]?.bool == true },
                        set: { editor.set("layout", InspectorEdits.layout(n, "wrap", .bool($0))) }))
            }
        }
    }

    // MARK: size

    private func size(_ n: EditorNode) -> some View {
        InspectorSection(title: "Size") {
            HStack(alignment: .top, spacing: Space.s2) {
                axis(n, "w", "Width")
                axis(n, "h", "Height")
            }
            HStack(alignment: .top, spacing: Space.s2) {
                NumberRow(label: "X", value: num(n, "x"), suffix: "pt", clearable: true) {
                    editor.set("x", $0.map { .number($0) })
                }
                NumberRow(label: "Y", value: num(n, "y"), suffix: "pt", clearable: true) {
                    editor.set("y", $0.map { .number($0) })
                }
            }
        }
    }

    @ViewBuilder private func axis(_ n: EditorNode, _ key: String, _ label: String) -> some View {
        let mode = n.props["sizing"]?[key]?.string ?? "fixed"
        VStack(alignment: .leading, spacing: Space.s2) {
            ChoiceRow(label: label, value: mode, choices: ["fixed", "hug", "fill"]) {
                editor.set("sizing", InspectorEdits.sizing(n, key, $0))
            }
            if mode == "fixed" {
                NumberRow(label: "\(label) in points", value: num(n, key), suffix: "pt") {
                    editor.set(key, $0.map { .number(max(0, $0)) })
                }
            }
        }
    }

    // MARK: appearance (radius, material, opacity)

    @ViewBuilder private func appearance(_ n: EditorNode) -> some View {
        InspectorSection(title: "Appearance") {
            if n.type != "page", n.type != "text", n.type != "ellipse", n.type != "vector" {
                tokenOrNumber(n, key: "radius", label: "Radius", kind: "radius", suffix: "pt")
            }
            if ["frame", "rect", "component", "instance"].contains(n.type) {
                let m = n.props["material"]
                TokenSelect(label: "Material token", kind: "material", current: m, tokens: editor.tokens) {
                    editor.set("material", $0.map(DJSON.token) ?? InspectorEdits.literal(kind: "material"))
                }
                if m?.tokenName == nil {
                    ChoiceRow(
                        label: "Material", value: m?.string ?? "none", choices: ["none", "glass", "well", "clear"]
                    ) {
                        editor.set("material", $0 == "none" ? nil : .string($0))
                    }
                }
            }
            if n.type != "page" {
                NumberRow(label: "Opacity", value: num(n, "opacity").map { $0 * 100 }, suffix: "%", clearable: true) {
                    editor.set("opacity", $0.map { .number(min(1, max(0, $0 / 100))) })
                }
            }
            if n.isContainer {
                CoreSwitch(
                    "Clip content",
                    isOn: Binding(get: { n.props["clip"]?.bool == true }, set: { editor.set("clip", .bool($0)) }))
            }
        }
    }

    /// A prop that is a number or a token (radius, gap): the token select when the system has some, else the number.
    @ViewBuilder private func tokenOrNumber(_ n: EditorNode, key: String, label: String, kind: String, suffix: String)
        -> some View
    {
        let v = n.props[key]
        TokenSelect(label: "\(label) token", kind: kind, current: v, tokens: editor.tokens) {
            editor.set(key, $0.map(DJSON.token) ?? InspectorEdits.literal(kind: kind))
        }
        if v?.tokenName == nil {
            NumberRow(label: label, value: v?.double ?? v?.array?.first?.double, suffix: suffix, clearable: true) {
                editor.set(key, $0.map { .number(max(0, $0)) })
            }
        }
    }

    // MARK: fill + stroke

    @ViewBuilder private func fill(_ n: EditorNode) -> some View {
        let solid = InspectorEdits.firstSolid(n)
        let fills = InspectorEdits.fills(n)
        InspectorSection(title: "Fill") {
            if fills.isEmpty {
                Button("Add Fill") {
                    editor.set("fill", InspectorEdits.fill(n, color: InspectorEdits.literal(kind: "color")))
                }
                .buttonStyle(.coreSecondary)
            } else if let solid {
                TokenSelect(label: "Colour token", kind: "color", current: solid, tokens: editor.tokens) {
                    editor.set(
                        "fill",
                        InspectorEdits.fill(n, color: $0.map(DJSON.token) ?? InspectorEdits.literal(kind: "color")))
                }
                if solid.tokenName == nil {
                    ColorRow(label: "Colour", hex: solid.string) {
                        editor.set("fill", InspectorEdits.fill(n, color: .string($0)))
                    }
                }
                Button("Remove Fill") { editor.set("fill", InspectorEdits.removingFirstFill(n)) }
                    .buttonStyle(.coreQuietDanger)
            } else {
                Text("A gradient or image fill. Edit it on the canvas or ask the AI.").foregroundStyle(
                    GlassInk.secondary
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            if fills.count > 1 { Text("\(fills.count - 1) more").foregroundStyle(GlassInk.secondary) }
        }
    }

    @ViewBuilder private func stroke(_ n: EditorNode) -> some View {
        let s = n.props["stroke"]
        InspectorSection(title: "Stroke") {
            if let s {
                TokenSelect(label: "Colour token", kind: "color", current: s["color"], tokens: editor.tokens) {
                    editor.set(
                        "stroke",
                        InspectorEdits.stroke(n, "color", $0.map(DJSON.token) ?? InspectorEdits.literal(kind: "color")))
                }
                if s["color"]?.tokenName == nil {
                    ColorRow(label: "Colour", hex: s["color"]?.string) {
                        editor.set("stroke", InspectorEdits.stroke(n, "color", .string($0)))
                    }
                }
                NumberRow(label: "Width", value: s["width"]?.double, suffix: "pt") {
                    editor.set("stroke", InspectorEdits.stroke(n, "width", .number(max(0, $0 ?? 1))))
                }
                Button("Remove Stroke") { editor.set("stroke", nil) }.buttonStyle(.coreQuietDanger)
            } else {
                Button("Add Stroke") {
                    editor.set("stroke", InspectorEdits.stroke(n, "color", InspectorEdits.literal(kind: "color")))
                }
                .buttonStyle(.coreSecondary)
            }
        }
    }

    // MARK: type

    @ViewBuilder private func typeStyle(_ n: EditorNode) -> some View {
        let t = n.props["type"]
        InspectorSection(title: "Type") {
            TokenSelect(label: "Style token", kind: "type", current: t, tokens: editor.tokens) {
                editor.set("type", $0.map(DJSON.token) ?? InspectorEdits.literal(kind: "type"))
            }
            if t?.tokenName == nil {
                HStack(alignment: .top, spacing: Space.s2) {
                    NumberRow(label: "Size", value: t?["size"]?.double, suffix: "pt") {
                        if let v = $0 { editor.set("type", InspectorEdits.type(n, "size", .number(v))) }
                    }
                    ChoiceRow(
                        label: "Weight", value: t?["weight"]?.double.map { String(Int($0)) },
                        choices: ["300", "400", "500", "600", "700"]
                    ) { editor.set("type", InspectorEdits.type(n, "weight", .number(Double($0) ?? 400))) }
                }
                ChoiceRow(label: "Align", value: t?["align"]?.string, choices: ["left", "center", "right", "justify"]) {
                    editor.set("type", InspectorEdits.type(n, "align", .string($0)))
                }
            }
            Text("Double-click the text on the canvas to edit it.").foregroundStyle(GlassInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: overrides

    @ViewBuilder private func overrides(_ n: EditorNode) -> some View {
        let list = InspectorEdits.overridePaths(n)
        InspectorSection(title: "Overrides") {
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
