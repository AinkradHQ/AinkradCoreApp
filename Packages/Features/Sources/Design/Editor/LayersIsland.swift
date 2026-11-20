import CoreUI
import Projects
import SwiftUI
import UniformTypeIdentifiers

/// The layers panel (V3-04): the page's nodes as a tree, front layer first. Click selects, double-click (or the menu) renames,
/// the eye hides, and a drag reorders, nests or un-nests. Everything it does is an edit op; the keyboard and VoiceOver reorder
/// with Move Forward / Move Backward in the row's menu.
struct LayersIsland: View {
    let editor: DesignEditor

    var body: some View {
        let rows = editor.layers.rows(expanded: editor.expanded)
        Island("Layers", sub: editor.layers.layers.isEmpty ? nil : "\(editor.layers.layers.count)") {
            if rows.isEmpty {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("No layers").coreFont(size: MacTextSize.body, weight: .semibold)
                    Text(
                        editor.attached
                            ? "Draw on the canvas, or ask the AI to." : "Layers show once the canvas is open."
                    )
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s2)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.s1) {
                        ForEach(rows) { LayerRowView(editor: editor, row: $0) }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
        .accessibilityIdentifier("design-layers")
    }
}

private struct LayerRowView: View {
    @Environment(\.coreAccent) private var paneAccent
    let editor: DesignEditor
    let row: LayerRow
    @State private var height: CGFloat = MacSize.controlLg
    @State private var hint: LayerDrop?
    @State private var draft = ""
    @FocusState private var focused: Bool
    private var layer: DesignLayer { row.layer }
    private var selected: Bool { editor.selection.contains(layer.id) }

    var body: some View {
        HStack(spacing: Space.s1) {
            Color.clear.frame(width: CGFloat(row.depth) * Space.s4, height: 1)
            chevron
            if editor.renaming == layer.id { renameField } else { rowBody }
        }
        .opacity(layer.hidden ? 0.5 : 1)
        .overlay(alignment: .top) { if case .above = hint { bar } }
        .overlay(alignment: .bottom) { if case .below = hint { bar } }
        .background { if case .into = hint { coreShape(Radius.control).fill(GlassInk.wellHover) } }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height = $0 }
        .onDrag {
            editor.dragging = layer.id
            return NSItemProvider(object: layer.id as NSString)
        }
        .onDrop(
            of: [.plainText], delegate: LayerDropDelegate(editor: editor, layer: layer, height: height, hint: $hint)
        )
        .contextMenu { menu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(layer.title)
        .accessibilityValue(layer.hidden ? "Hidden" : "")
        .accessibilityAction(named: "Move Forward") { editor.step(layer.id, up: true) }
        .accessibilityAction(named: "Move Backward") { editor.step(layer.id, up: false) }
    }

    private var bar: some View {
        coreShape(1).fill(GlassInk.accent(paneAccent)).frame(height: 2).padding(.horizontal, Space.s2)
    }

    @ViewBuilder private var chevron: some View {
        if row.hasChildren {
            CoreIconButton(
                symbol: row.expanded ? "chevron.down" : "chevron.right", label: row.expanded ? "Collapse" : "Expand"
            ) {
                if row.expanded { editor.expanded.remove(layer.id) } else { editor.expanded.insert(layer.id) }
            }
        } else {
            Color.clear.frame(width: MacSize.controlMd, height: 1)
        }
    }

    private var rowBody: some View {
        CoreRow(layer.title, symbol: layer.symbol, selected: selected, action: { editor.select(layer.id) }) {
            if layer.type != "page" {
                CoreIconButton(
                    symbol: layer.hidden ? "eye.slash" : "eye", label: layer.hidden ? "Show Layer" : "Hide Layer"
                ) { editor.setHidden(layer.id, !layer.hidden) }
            }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { beginRename() })
        .help(layer.title)
    }

    private var renameField: some View {
        TextField("Layer name", text: $draft)
            .textFieldStyle(.plain)
            .coreFont(size: MacTextSize.body)
            .padding(.horizontal, Space.s3)
            .frame(minHeight: MacSize.controlLg)
            .coreFieldSurface(focused: true)
            .focused($focused)
            .onSubmit { editor.rename(layer.id, to: draft) }
            .onExitCommand { editor.renaming = nil }
            .onAppear {
                draft = layer.name
                focused = true
            }
            .accessibilityLabel("Layer name")
    }

    private func beginRename() { if layer.type != "page" { editor.renaming = layer.id } }

    @ViewBuilder private var menu: some View {
        if layer.type != "page" {
            Button("Rename") { beginRename() }
            Button(layer.hidden ? "Show Layer" : "Hide Layer") { editor.setHidden(layer.id, !layer.hidden) }
            Divider()
            Button("Move Forward") { editor.step(layer.id, up: true) }
            Button("Move Backward") { editor.step(layer.id, up: false) }
            Divider()
            Button("Delete", role: .destructive) { editor.delete(layer.id) }
        }
    }
}

/// Drops on one row: the top quarter lands above, the bottom quarter below, the middle inside a container (a leaf splits at
/// the half). The drag carries only the layer id; `DesignEditor.dragging` holds it, and `LayerTree.canMove` refuses a drop
/// into the layer's own subtree before the pointer shows it as possible.
private struct LayerDropDelegate: DropDelegate {
    let editor: DesignEditor
    let layer: DesignLayer
    let height: CGFloat
    @Binding var hint: LayerDrop?

    private func zone(_ y: CGFloat) -> LayerDrop {
        let f = height > 0 ? y / height : 0.5
        if layer.isContainer, f > 0.25, f < 0.75 { return .into(layer.id) }
        return f <= 0.5 ? .above(layer.id) : .below(layer.id)
    }

    private func allowed(_ info: DropInfo) -> LayerDrop? {
        guard let d = editor.dragging else { return nil }
        let z = zone(info.location.y)
        return editor.layers.canMove(d, z) ? z : nil
    }

    func validateDrop(info: DropInfo) -> Bool { allowed(info) != nil }
    func dropEntered(info: DropInfo) { hint = allowed(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        hint = allowed(info)
        return DropProposal(operation: hint == nil ? .forbidden : .move)
    }
    func dropExited(info: DropInfo) { hint = nil }
    func performDrop(info: DropInfo) -> Bool {
        defer { hint = nil }
        guard let d = editor.dragging, let z = allowed(info) else { return false }
        editor.drop(d, z)
        return true
    }
}
