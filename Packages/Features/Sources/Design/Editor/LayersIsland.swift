import AppKit
import CoreUI
import Projects
import SwiftUI
import UniformTypeIdentifiers

/// The layers panel (V3-04), compact like Figma's: one slim row per layer with its kind's icon, thin guides for nesting,
/// a chevron only where there is something inside. Click selects, double-click (or Return) renames, the eye (shown on
/// hover, or always for a hidden layer) hides, and a drag reorders, nests or un-nests. With the panel focused the keys
/// move: ↑ ↓ the next layer, → open, ← close (or go to the parent), Return rename, Delete delete. Find narrows the list to
/// matching names and their parents. Everything is an edit op; VoiceOver reorders with Move Forward / Move Backward.
struct LayersIsland: View {
    @Bindable var editor: DesignEditor
    @State private var find = ""
    @State private var finding = false
    @FocusState private var findFocus: Bool
    @FocusState private var listFocus: Bool
    @State private var reveal: Task<Void, Never>?

    private var rows: [LayerRow] {
        let q = find.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return editor.layers.rows(expanded: editor.expanded) }
        // Every layer open, then only the matches and the layers they sit in.
        let all = editor.layers.rows(expanded: Set(editor.layers.layers.map(\.id)))
        let hits = Set(all.filter { $0.layer.title.lowercased().contains(q) }.map(\.id))
        let keep = hits.union(hits.flatMap { editor.layers.ancestors(of: $0) })
        return all.filter { keep.contains($0.id) }
    }

    var body: some View {
        let rows = rows
        let shapes = editor.layers.layers.filter { $0.type != "page" }.count
        Island(
            title: "Layers", sub: shapes == 0 ? nil : "\(shapes)",
            accessory: {
                HStack(spacing: 2) {
                    CoreIconButton(symbol: "magnifyingglass", label: "Find a layer", selected: finding) {
                        withAnimation(Motion.out(Motion.ui)) { finding.toggle() }
                        if finding { findFocus = true } else { find = "" }
                    }
                    CoreIconButton(symbol: "rectangle.compress.vertical", label: "Close every group") {
                        withAnimation(Motion.out(Motion.ui)) {
                            editor.expanded = Set(editor.layers.children(of: nil).map(\.id))
                        }
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s2) {
                if finding {
                    HStack(spacing: Space.s2) {
                        Image(systemName: "magnifyingglass").foregroundStyle(GlassInk.secondary).accessibilityHidden(
                            true)
                        TextField("", text: $find, prompt: Text("Find a layer").foregroundStyle(GlassInk.secondary))
                            .textFieldStyle(.plain).focused($findFocus)
                            .onExitCommand {
                                find = ""
                                withAnimation(Motion.out(Motion.ui)) { finding = false }
                            }
                    }
                    .padding(.horizontal, Space.s2).frame(height: MacSize.controlMd + 2)
                    .coreFieldSurface(focused: findFocus)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if shapes == 0 {
                    empty
                } else if rows.isEmpty {
                    Text("No layer is called “\(find)”.").foregroundStyle(GlassInk.secondary)
                        .padding(.top, Space.s1)
                } else {
                    ScrollViewReader { reader in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(rows) {
                                    LayerRowView(editor: editor, row: $0, pick: { pick($0, rows, $1) }).lineLimit(1)
                                        .id($0.id)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .animation(Motion.out(Motion.ui), value: rows.map(\.id))
                        }
                        .scrollIndicators(.never)
                        // Only a pick made on the canvas scrolls the list, and only after it has settled: never inside a
                        // layout pass, and not while the AI draws (a scroll then froze the window once).
                        .onChange(of: editor.revealStamp) {
                            reveal?.cancel()
                            guard !editor.revealPaused, editor.dragging == nil else { return }
                            reveal = Task {
                                try? await Task.sleep(for: .milliseconds(200))
                                guard !Task.isCancelled, !editor.revealPaused, let id = editor.selection.first else {
                                    return
                                }
                                reader.scrollTo(id)
                            }
                        }
                    }
                    // Focusable only by a click: focus that wandered in on its own (when the AI panel's field went away) froze
                    // the window.
                    .focusable(true, interactions: .activate).focused($listFocus).focusEffectDisabled()
                    .onKeyPress(phases: .down) { key($0, rows) }
                }
            }
        }
        .accessibilityIdentifier("design-layers")
    }

    /// A click on a row: ⌘ adds or removes it, ⇧ takes everything from the first selected layer to it, plain selects it.
    private func pick(_ id: String, _ rows: [LayerRow], _ mods: NSEvent.ModifierFlags) {
        let ids = rows.filter { $0.layer.type != "page" }.map(\.id)
        if mods.contains(.command) {
            var sel = editor.selection
            if let i = sel.firstIndex(of: id) { sel.remove(at: i) } else { sel.append(id) }
            editor.selectMany(sel)
        } else if mods.contains(.shift), let anchor = editor.selection.first, let a = ids.firstIndex(of: anchor),
            let b = ids.firstIndex(of: id)
        {
            editor.selectMany([anchor] + ids[min(a, b)...max(a, b)].filter { $0 != anchor })
        } else {
            editor.select(id)
        }
    }

    /// Nothing drawn yet: how to start, with the keys.
    private var empty: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(editor.attached ? "Nothing on this page yet" : "Layers show once the canvas is open")
                .coreFont(size: MacTextSize.body, weight: .semibold)
            if editor.attached {
                VStack(alignment: .leading, spacing: Space.s2) {
                    hint("F", "Draw a frame")
                    hint("R", "Draw a rectangle")
                    hint("T", "Write text")
                    hint("P", "Draw with the pen")
                }
                Text("Or describe it in the Ask field below and AI draws it.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Space.s1)
    }

    private func hint(_ key: String, _ what: String) -> some View {
        HStack(spacing: Space.s2) {
            CoreKeycap(key)
            Text(what).foregroundStyle(GlassInk.secondary)
        }
    }

    /// The list's keys (only while the list has focus).
    private func key(_ press: KeyPress, _ rows: [LayerRow]) -> KeyPress.Result {
        guard editor.renaming == nil else { return .ignored }
        let ids = rows.map(\.id)
        let at = editor.selection.first.flatMap(ids.firstIndex(of:))
        let current = at.map { rows[$0] }
        switch press.key {
        case .downArrow, .upArrow:
            let step = press.key == .downArrow ? 1 : -1
            let next = at.map { min(max($0 + step, 0), ids.count - 1) } ?? 0
            if ids.indices.contains(next) { editor.select(ids[next], quiet: true) }
        case .rightArrow:
            guard let r = current, r.hasChildren else { return .ignored }
            withAnimation(Motion.out(Motion.ui)) { _ = editor.expanded.insert(r.id) }
        case .leftArrow:
            guard let r = current else { return .ignored }
            if r.hasChildren, r.expanded {
                withAnimation(Motion.out(Motion.ui)) { _ = editor.expanded.remove(r.id) }
            } else if let p = r.layer.parent {
                editor.select(p, quiet: true)
            }
        case .return:
            guard let r = current, r.layer.type != "page", !editor.readOnly else { return .ignored }
            editor.renaming = r.id
        case .delete, .deleteForward:
            guard current != nil else { return .ignored }
            editor.deleteSelected()
        default: return .ignored
        }
        return .handled
    }
}

private struct LayerRowView: View {
    @Environment(\.coreAccent) private var paneAccent
    @Environment(\.corePalette) private var palette
    let editor: DesignEditor
    let row: LayerRow
    let pick: (String, NSEvent.ModifierFlags) -> Void
    @State private var height: CGFloat = 28
    @State private var hint: LayerDrop?
    @State private var draft = ""
    @State private var hovering = false
    @FocusState private var focused: Bool
    private var layer: DesignLayer { row.layer }
    private var selected: Bool { editor.selection.contains(layer.id) }
    private var page: Bool { layer.type == "page" }
    static let indent: CGFloat = 14

    var body: some View {
        HStack(spacing: 4) {
            guides
            chevron
            Image(systemName: icon).coreFont(size: 12, weight: .medium)
                .foregroundStyle(selected ? GlassInk.primary : GlassInk.secondary)
                .frame(width: 16).accessibilityHidden(true)
            if editor.renaming == layer.id {
                renameField
            } else {
                Text(layer.title).coreFont(
                    size: MacTextSize.body, weight: page || row.depth == 1 ? .semibold : .regular
                )
                .foregroundStyle(GlassInk.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !page, hovering || layer.hidden {
                Button {
                    editor.setHidden(layer.id, !layer.hidden)
                } label: {
                    Image(systemName: layer.hidden ? "eye.slash" : "eye").coreFont(size: 11)
                        .foregroundStyle(GlassInk.secondary).frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(layer.hidden ? "Show Layer" : "Hide Layer")
                .accessibilityLabel(layer.hidden ? "Show Layer" : "Hide Layer")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Space.s1)
        .frame(height: 28)
        .background(
            selected ? palette.btnPrimary.opacity(0.24) : hovering ? GlassInk.wellHover : .clear,
            in: coreShape(Radius.control)
        )
        .contentShape(coreShape(Radius.control))
        .opacity(layer.hidden ? 0.5 : 1)
        // The single click acts at once; the double click is read beside it, so a click is never held back for it.
        .onTapGesture { pick(layer.id, NSEvent.modifierFlags) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { beginRename() })
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(Motion.out(Motion.hover), value: selected)
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
        .help(layer.title)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(layer.title)
        .accessibilityValue(layer.hidden ? "Hidden" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Move Forward") { editor.step(layer.id, up: true) }
        .accessibilityAction(named: "Move Backward") { editor.step(layer.id, up: false) }
    }

    /// Frames read as #, like Figma.
    private var icon: String { layer.type == "frame" ? "number" : layer.symbol }

    /// One thin line per nesting level, so what sits inside what reads at a glance.
    private var guides: some View {
        HStack(spacing: 0) {
            ForEach(0..<row.depth, id: \.self) { _ in
                coreShape(0).fill(GlassInk.secondary.opacity(0.18)).frame(width: 1, height: 28)
                    .frame(width: Self.indent, alignment: .center)
            }
        }
    }

    private var bar: some View {
        coreShape(1).fill(GlassInk.accent(paneAccent)).frame(height: 2).padding(.horizontal, Space.s2)
    }

    @ViewBuilder private var chevron: some View {
        if row.hasChildren {
            Button {
                withAnimation(Motion.out(Motion.ui)) {
                    if row.expanded {
                        _ = editor.expanded.remove(layer.id)
                    } else {
                        _ = editor.expanded.insert(layer.id)
                    }
                }
            } label: {
                Image(systemName: "chevron.right").coreFont(size: 9, weight: .bold)
                    .foregroundStyle(GlassInk.secondary)
                    .rotationEffect(.degrees(row.expanded ? 90 : 0))
                    .frame(width: 14, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.expanded ? "Collapse" : "Expand")
        } else {
            Color.clear.frame(width: 14, height: 1)
        }
    }

    private var renameField: some View {
        TextField("Layer name", text: $draft)
            .textFieldStyle(.plain)
            .coreFont(size: MacTextSize.body)
            .padding(.horizontal, Space.s1)
            .frame(height: 22)
            .coreFieldSurface(focused: true)
            .focused($focused)
            .onSubmit { editor.rename(layer.id, to: draft) }
            .onExitCommand { editor.renaming = nil }
            // Leaving the field (a click elsewhere) keeps what was typed, like Return.
            .onChange(of: focused) { _, on in if !on, editor.renaming == layer.id { editor.rename(layer.id, to: draft) } }
            .onAppear {
                draft = layer.name
                focused = true
            }
            .accessibilityLabel("Layer name")
    }

    private func beginRename() { if !page, !editor.readOnly { editor.renaming = layer.id } }

    @ViewBuilder private var menu: some View {
        if !page {
            Button("Rename") { beginRename() }.disabled(editor.readOnly)
            Button(layer.hidden ? "Show Layer" : "Hide Layer") { editor.setHidden(layer.id, !layer.hidden) }
                .disabled(editor.readOnly)
            Divider()
            Button("Move Forward") { editor.step(layer.id, up: true) }.disabled(editor.readOnly)
            Button("Move Backward") { editor.step(layer.id, up: false) }.disabled(editor.readOnly)
            Divider()
            Button("Delete", role: .destructive) {
                if selected, editor.selection.count > 1 { editor.deleteSelected() } else { editor.delete(layer.id) }
            }
            .disabled(editor.readOnly)
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
