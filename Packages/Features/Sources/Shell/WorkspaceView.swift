import AppKit
import CoreUI
import SwiftUI

/// The pane workspace (`tiles.js`): panes tiled by the split tree under the status cluster, a sideways strip when the columns do not
/// fit, drag-to-tile with a drop hint, seams in both axes, and focus mode with its tabs.
struct WorkspaceView: View {
    @Bindable var shell: ShellModel
    @State private var drag: (id: String, origin: CGPoint, translation: CGSize)?
    @State private var drop: TileDrop?
    @State private var resizing = false
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        GeometryReader { geo in
            let area = CGSize(
                width: geo.size.width - ShellMetrics.paneInset * 2,
                height: geo.size.height - ShellMetrics.topBar - ShellMetrics.paneInset)
            let mins = Dictionary(uniqueKeysWithValues: shell.panes.map { ($0.id, $0.minWidth) })
            let layout = shell.tree.layout(
                minWidth: { mins[$0] ?? ShellMetrics.paneMinWidth }, container: area, gap: ShellMetrics.paneGap,
                minHeight: ShellMetrics.paneMinHeight)
            let focus = shell.focusedPane
            ZStack(alignment: .topLeading) {
                if shell.panes.isEmpty { empty }
                ScrollView(.horizontal, showsIndicators: layout.isStrip && focus == nil) {
                    ZStack(alignment: .topLeading) {
                        ForEach(shell.panes) { spec in
                            pane(spec, layout: layout, area: area)
                        }
                        if focus == nil {
                            if let drop {
                                dropHint(drop.hint)
                            }
                            if drag == nil {
                                ForEach(Array(layout.seams.enumerated()), id: \.offset) { _, seam in
                                    if seam.axis == .vertical || !layout.isStrip {
                                        SeamHandle(shell: shell, seam: seam, resizing: $resizing)
                                    }
                                }
                            }
                        }
                    }
                    .coordinateSpace(name: "ws")
                    .frame(
                        width: focus == nil ? max(layout.contentWidth, area.width) : area.width,
                        height: max(area.height, layout.frames.values.map(\.maxY).max() ?? 0), alignment: .topLeading)
                }
                .scrollDisabled(focus != nil || !layout.isStrip)
                .frame(width: area.width, height: area.height)
                .padding(.leading, ShellMetrics.paneInset)
                .padding(.top, ShellMetrics.topBar)
                if !shell.panes.isEmpty {
                    // Every pane's tab, tiled or focused: title, state and all its actions. Dragging a tab over another
                    // pane tiles it there.
                    PaneTabs(shell: shell) { id, location, translation in
                        guard focus == nil, let slot = layout.frames[id] else { return }
                        if drag?.id != id { shell.activePane = id }
                        drag = (id, drag?.id == id ? drag!.origin : slot.origin, translation)
                        let p = CGPoint(x: location.x - ShellMetrics.paneInset, y: location.y - ShellMetrics.topBar)
                        drop = TileTree.dropTarget(at: p, frames: layout.frames, excluding: id)
                    } onDragEnd: { id in
                        withAnimation(Motion.out(Motion.move)) {
                            if let drop { shell.dropPane(id, on: drop.target, edge: drop.edge) }
                            drag = nil
                            drop = nil
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .coordinateSpace(name: "wsroot")
        }
    }

    @ViewBuilder
    private func pane(_ spec: PaneSpec, layout: TileLayout, area: CGSize) -> some View {
        let focus = shell.focusedPane
        let folded = focus != nil && focus != spec.id
        let tiled = layout.frames[spec.id] ?? CGRect(origin: .zero, size: area)
        let slot = focus == spec.id ? CGRect(origin: .zero, size: area) : tiled
        let dragging = drag?.id == spec.id
        PaneHost(spec: spec, active: shell.activePane == spec.id && (focus != nil || shell.panes.count > 1))
            .frame(width: slot.width, height: slot.height)
            // Reduce Motion: positions snap, the pane fades in and out; otherwise it travels and scales.
            .scaleEffect(folded || dragging ? coreScale(0.96) : 1)
            .offset(
                x: dragging ? drag!.origin.x + drag!.translation.width : slot.minX,
                y: dragging ? drag!.origin.y + drag!.translation.height : slot.minY
            )
            .animation(reduce || resizing ? nil : Motion.out(Motion.move), value: slot)
            .opacity(folded ? 0 : 1)
            .allowsHitTesting(!folded)
            .zIndex(dragging ? 1 : 0)
            // A pane rises 18 pt and settles from 97 %; Reduce Motion is a fade.
            .transition(
                reduce ? .opacity : .opacity.combined(with: .offset(y: 18)).combined(with: .scale(scale: 0.97))
            )
            .onTapGesture { shell.activePane = spec.id }
    }

    /// The half of the target pane that the drop will take.
    private func dropHint(_ r: CGRect) -> some View {
        coreShape(Radius.pane).fill(palette.primary.opacity(0.18))
            .overlay { coreShape(Radius.pane).strokeBorder(palette.primary, lineWidth: 1.5) }
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .animation(reduce ? nil : Motion.out(Motion.ui), value: r)
            .zIndex(2)
    }

    private func coreScale(_ s: CGFloat) -> CGFloat { reduce ? 1 : s }

    private var empty: some View {
        VStack(spacing: Space.s1) {
            Text("No apps in this workspace").font(.system(size: MacTextSize.title, weight: .semibold))
            Text("Open one from the launcher with ⌘K.").foregroundStyle(palette.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Every pane's tab in the top bar's left (Ahmed, 2026-11-05): the pane's icon, title and state, and a menu with all its
/// actions. Click picks the pane (in focus mode, shows it); a double click toggles focus mode; dragging a tab tiles its
/// pane elsewhere. One indicator glides to the active tab.
private struct PaneTabs: View {
    @Bindable var shell: ShellModel
    let onDrag: (String, CGPoint, CGSize) -> Void
    let onDragEnd: (String) -> Void
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(shell.panes) { p in
                PaneTab(
                    shell: shell, spec: p, on: (shell.focusedPane ?? shell.activePane) == p.id, indicator: indicator,
                    onDrag: { onDrag(p.id, $0, $1) }, onDragEnd: { onDragEnd(p.id) })
            }
        }
        .padding(Space.s1)
        .coreGlass(radius: Radius.cardMac)
        .animation(reduce ? nil : .spring(duration: 0.3, bounce: 0.2), value: shell.focusedPane ?? shell.activePane)
        .onKeyPress(.leftArrow) {
            shell.cyclePane(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            shell.cyclePane(1)
            return .handled
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Space.s4)
        .padding(.top, Space.s2)
        .frame(height: ShellMetrics.topBar, alignment: .top)
    }
}

private struct PaneTab: View {
    @Bindable var shell: ShellModel
    let spec: PaneSpec
    let on: Bool
    let indicator: Namespace.ID
    let onDrag: (CGPoint, CGSize) -> Void
    let onDragEnd: () -> Void
    @State private var hovering = false

    /// Each kind of pane has its colour, so tabs read at a glance.
    private var hue: Color {
        switch spec.symbol {
        case "terminal": GlassInk.slate
        case "sparkles", "play": GlassInk.violet
        case "server.rack": GlassInk.green
        case "creditcard", "person.crop.circle": GlassInk.orange
        default: GlassInk.blue
        }
    }

    private var stateColor: Color? {
        guard let chip = spec.chip else { return nil }
        switch chip.tone {
        case .run, .done: return GlassInk.green
        case .fail: return GlassInk.red
        default: return GlassInk.orange
        }
    }

    var body: some View {
        HStack(spacing: Space.s2) {
            IconTile(spec.symbol, hue: on ? hue : hue.opacity(0.55), size: 26, bounce: on)
                .overlay(alignment: .bottomTrailing) {
                    if let c = stateColor {
                        StatusDot(color: c, live: spec.chip?.tone == .run)
                            .padding(2).background(.black.opacity(0.55), in: coreShape(3))
                            .offset(x: 4, y: 4)
                            .help(spec.chip?.label ?? "")
                    }
                }
            VStack(alignment: .leading, spacing: 0) {
                Text(spec.title).font(.system(size: MacTextSize.body, weight: .semibold)).lineLimit(1)
                if let sub = spec.sub {
                    Text(sub).font(.system(size: MacTextSize.meta)).foregroundStyle(WidgetInk.secondary).lineLimit(1)
                        .frame(maxWidth: Space.s8 * 5, alignment: .leading).fixedSize(horizontal: true, vertical: false)
                }
            }
            Menu {
                menu
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(hovering ? 0.18 : 0.08), in: coreShape(6))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .opacity(on || hovering ? 1 : 0)
            .accessibilityLabel("\(spec.title) actions")
            Button {
                shell.dismissPane(spec.id)
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18)
                    .background(.white.opacity(0.1), in: coreShape(5))
            }
            .buttonStyle(.plain).opacity(hovering ? 1 : 0)
            .accessibilityLabel("Close \(spec.title)")
        }
        .foregroundStyle(WidgetInk.primary)
        .padding(.leading, Space.s1).padding(.trailing, Space.s2).frame(height: MacSize.controlMd + 12)
        .background {
            if on {
                coreShape(Radius.control + 2)
                    .fill(
                        LinearGradient(
                            colors: [hue.opacity(0.35), hue.opacity(0.12)], startPoint: .top, endPoint: .bottom)
                    )
                    .overlay { coreShape(Radius.control + 2).strokeBorder(.white.opacity(0.3), lineWidth: 1) }
                    .overlay(alignment: .bottom) {
                        Capsule().fill(hue).frame(width: 22, height: 3).offset(y: -2)
                    }
                    .shadow(color: hue.opacity(0.4), radius: 10)
                    .matchedGeometryEffect(id: "on", in: indicator)
            } else if hovering {
                coreShape(Radius.control + 2).fill(.white.opacity(0.08))
            }
        }
        .scaleEffect(hovering && !on ? 1.03 : 1)
        .animation(.spring(duration: 0.25, bounce: 0.3), value: hovering)
        .contentShape(coreShape(Radius.control + 2))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { toggleFocus() }
        .onTapGesture { pick() }
        .gesture(
            DragGesture(minimumDistance: Space.s2, coordinateSpace: .named("wsroot"))
                .onChanged { onDrag($0.location, $0.translation) }
                .onEnded { _ in onDragEnd() }
        )
        .contextMenu { menu }
        .help(spec.sub.map { "\(spec.title) · \($0)" } ?? spec.title)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spec.sub.map { "\(spec.title), \($0)" } ?? spec.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The pane's own actions, then the workspace's.
    @ViewBuilder private var menu: some View {
        ForEach(shell.paneMenus[spec.id]?() ?? []) { item in
            if item.children.isEmpty {
                Button(role: item.destructive ? .destructive : nil, action: item.run) {
                    Label(item.title, systemImage: item.symbol)
                }
                .disabled(!item.enabled)
            } else {
                Menu {
                    ForEach(item.children) { c in Button(c.title, action: c.run) }
                } label: {
                    Label(item.title, systemImage: item.symbol)
                }
                .disabled(!item.enabled)
            }
        }
        if shell.paneMenus[spec.id] != nil { Divider() }
        Button {
            toggleFocus()
        } label: {
            Label(
                shell.focusedPane == spec.id ? "Tile All Panes" : "Full Pane",
                systemImage: shell.focusedPane == spec.id
                    ? "rectangle.split.2x1" : "arrow.up.left.and.arrow.down.right")
        }
        Button {
            shell.dismissPane(spec.id)
        } label: {
            Label("Close Pane", systemImage: "xmark")
        }
        Button {
            shell.closeOtherPanes(except: spec.id)
        } label: {
            Label("Close Other Panes", systemImage: "xmark.square")
        }
        .disabled(shell.panes.count < 2)
    }

    private func pick() {
        shell.activePane = spec.id
        if shell.focusedPane != nil { shell.focusedPane = spec.id }
    }

    private func toggleFocus() {
        shell.activePane = spec.id
        shell.focusedPane = shell.focusedPane == nil ? spec.id : nil
        shell.surface = .workspace
    }
}

/// One pane in the workspace: the chrome (clear glass, no head) around its content. Its tab carries the title and actions.
private struct PaneHost: View {
    let spec: PaneSpec
    let active: Bool

    var body: some View {
        CorePaneChrome(
            title: spec.title, sub: spec.sub, symbol: spec.symbol,
            state: spec.chip.map { ($0.label, $0.tone, $0.symbol) }, active: active, onClose: {}
        ) {
            spec.content
        }
    }
}

/// The gap between two siblings is a handle: drag it to trade space between them (10 % at least, and never below a pane's minimum).
private struct SeamHandle: View {
    @Bindable var shell: ShellModel
    let seam: TileSeam
    @Binding var resizing: Bool
    @State private var hovering = false
    @Environment(\.corePalette) private var palette

    private var horizontal: Bool { seam.axis == .horizontal }
    private var center: CGFloat { horizontal ? seam.frame.midX : seam.frame.midY }

    var body: some View {
        Color.clear
            .frame(width: seam.frame.width, height: seam.frame.height)
            .overlay {
                coreShape(Space.s1).fill(palette.primary.opacity(hovering || resizing ? 0.9 : 0))
                    .frame(width: horizontal ? Space.s1 : Space.s8 * 2, height: horizontal ? Space.s8 * 2 : Space.s1)
            }
            .contentShape(Rectangle())
            .offset(x: seam.frame.minX, y: seam.frame.minY)
            .onHover { inside in
                hovering = inside
                if inside {
                    (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("ws"))
                    .onChanged { v in
                        resizing = true
                        move(to: horizontal ? v.location.x : v.location.y)
                    }
                    .onEnded { _ in resizing = false }
            )
            .accessibilityElement()
            .accessibilityLabel(horizontal ? "Resize panes side by side" : "Resize panes above and below")
            .accessibilityAdjustableAction { dir in move(to: center + Space.s8 * (dir == .increment ? 1 : -1)) }
    }

    private func move(to pointer: CGFloat) {
        shell.resizeSeam(seam, gap: ShellMetrics.paneGap, position: pointer - seam.origin)
    }
}
