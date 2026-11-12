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
    /// How far the workspace strip is scrolled, so a drag measured on screen lands on the right pane.
    @State private var scrollX: CGFloat = 0
    @State private var scrolling = false
    /// The pane on top of the stack when the active pane is elsewhere.
    @State private var stackFront: String?
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        GeometryReader { geo in
            let area = CGSize(
                width: geo.size.width - ShellMetrics.paneInset * 2,
                height: geo.size.height - ShellMetrics.topBar - ShellMetrics.paneInset)
            let mins = Dictionary(uniqueKeysWithValues: shell.panes.map { ($0.id, $0.minWidth) })
            let tiled = shell.tree.layout(
                minWidth: { mins[$0] ?? ShellMetrics.paneMinWidth }, container: area, gap: ShellMetrics.paneGap,
                minHeight: ShellMetrics.paneMinHeight)
            let focus = shell.focusedPane
            let stack = Stack.make(
                order: shell.tree.leaves, tiled: tiled, area: area,
                minWidth: mins.values.max() ?? ShellMetrics.paneMinWidth,
                active: shell.activePane, front: stackFront, focused: focus != nil)
            let layout = stack.layout
            ZStack(alignment: .topLeading) {
                if shell.panes.isEmpty { empty }
                // The strip scrolls by its own offset, not a ScrollView: a terminal pane takes every scroll event, so
                // sideways swipes are caught for the whole workspace (StripSwipe), and picking a pane slides it into view.
                let maxX = focus == nil && layout.isStrip ? max(0, layout.contentWidth - area.width) : 0
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        if let slot = stack.slot, stack.hidden.count > 0 {
                            StackBehind(slot: slot, count: stack.hidden.count)
                        }
                        ForEach(shell.panes) { spec in
                            pane(spec, layout: layout, area: area, hidden: stack.hidden.contains(spec.id))
                        }
                        if let slot = stack.slot, let front = stack.front {
                            StackBadge(
                                index: (stack.members.firstIndex(of: front) ?? 0) + 1, count: stack.members.count,
                                slot: slot
                            )
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
                        height: max(area.height, layout.frames.values.map(\.maxY).max() ?? 0), alignment: .topLeading
                    )
                    .offset(x: -min(scrollX, maxX))
                }
                .frame(width: area.width, height: area.height, alignment: .topLeading)
                .clipped()
                .overlay(alignment: .bottom) {
                    if maxX > 0 {
                        StripBar(offset: min(scrollX, maxX), visible: area.width, total: layout.contentWidth)
                    }
                }
                .background {
                    StripSwipe(enabled: maxX > 0) { dx in
                        scrolling = true
                        scrollX = min(max(scrollX - dx, 0), maxX)
                    } ended: {
                        scrolling = false
                    }
                }
                .onChange(of: shell.activePane) { _, id in
                    if let id, stack.members.contains(id) { stackFront = id }
                    guard maxX > 0, let id, let f = layout.frames[id] else { return }
                    let target =
                        f.minX < scrollX ? f.minX : f.maxX > scrollX + area.width ? f.maxX - area.width : scrollX
                    withAnimation(reduce ? nil : Motion.out(Motion.move)) { scrollX = min(max(target, 0), maxX) }
                }
                .padding(.leading, ShellMetrics.paneInset)
                .padding(.top, ShellMetrics.topBar)
                if !shell.panes.isEmpty {
                    // Every pane's tab, tiled or focused: title, state and all its actions. Dragging a tab over another
                    // pane tiles it there.
                    PaneTabs(
                        shell: shell, compact: geo.size.width < ShellMetrics.railBelow,
                        onDrag: { dragTo($0, $1, $2, layout) }, onDragEnd: { dropIt($0) }
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .coordinateSpace(name: "wsroot")
        }
    }

    /// Dragging a pane (its tab, or the grip on the pane) moves it with the pointer and shows where it will tile.
    private func dragTo(_ id: String, _ location: CGPoint, _ translation: CGSize, _ layout: TileLayout) {
        guard shell.focusedPane == nil, let slot = layout.frames[id] else { return }
        if drag?.id != id { shell.activePane = id }
        drag = (id, drag?.id == id ? drag!.origin : slot.origin, translation)
        let p = CGPoint(x: location.x - ShellMetrics.paneInset + scrollX, y: location.y - ShellMetrics.topBar)
        drop = TileTree.dropTarget(at: p, frames: layout.frames, excluding: id)
    }

    private func dropIt(_ id: String) {
        withAnimation(Motion.out(Motion.move)) {
            if let drop { shell.dropPane(id, on: drop.target, edge: drop.edge) }
            drag = nil
            drop = nil
        }
    }

    @ViewBuilder
    private func pane(_ spec: PaneSpec, layout: TileLayout, area: CGSize, hidden: Bool) -> some View {
        let focus = shell.focusedPane
        let folded = (focus != nil && focus != spec.id) || hidden
        let tiled = layout.frames[spec.id] ?? CGRect(origin: .zero, size: area)
        let slot = focus == spec.id ? CGRect(origin: .zero, size: area) : tiled
        let dragging = drag?.id == spec.id
        PaneHost(
            spec: spec, active: shell.activePane == spec.id && (focus != nil || shell.panes.count > 1),
            canDrag: focus == nil && shell.panes.count > 1, scrolling: scrolling,
            onDrag: { dragTo(spec.id, $0, $1, layout) }, onDragEnd: { dropIt(spec.id) }
        )
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
            Text("No apps in this workspace").coreFont(size: MacTextSize.title, weight: .semibold)
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
    /// A narrow window: every tab shrinks to its icon (and state dot), the rail of the AI Sessions narrow mockup. The same for
    /// every app, since the tabs are the Shell's own.
    let compact: Bool
    let onDrag: (String, CGPoint, CGSize) -> Void
    let onDragEnd: (String) -> Void
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(shell.panes) { p in
                PaneTab(
                    shell: shell, spec: p, compact: compact, on: (shell.focusedPane ?? shell.activePane) == p.id,
                    indicator: indicator,
                    onDrag: { onDrag(p.id, $0, $1) }, onDragEnd: { onDragEnd(p.id) })
            }
        }
        .padding(Space.s1)
        .coreGlass(radius: Radius.cardMac)
        .coreAnimation(Motion.out(Motion.ui), value: shell.focusedPane ?? shell.activePane)
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: compact)
        .coreSideKeys {
            shell.cyclePane($0)
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
    let compact: Bool
    let on: Bool
    let indicator: Namespace.ID
    let onDrag: (CGPoint, CGSize) -> Void
    let onDragEnd: () -> Void
    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var editing: Bool

    private var stateColor: Color? {
        guard let chip = spec.chip else { return nil }
        switch chip.tone {
        case .run, .done: return GlassInk.green
        case .fail: return GlassInk.red
        default: return GlassInk.amber
        }
    }

    /// Minimal (Ahmed, 2026-11-05): icon and title, a small state dot, nothing else until hovered. The active tab is a
    /// quiet white glass that glides between tabs; ⋯ and × appear on hover only.
    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: spec.symbol).coreFont(size: MacTextSize.body, weight: .medium)
                .foregroundStyle(on ? GlassInk.primary : GlassInk.secondary)
                .accessibilityHidden(true)
            if shell.renamingTab == spec.id {
                TextField("Tab name", text: $draft)
                    .textFieldStyle(.plain).coreFont(size: MacTextSize.body, weight: .semibold)
                    .foregroundStyle(GlassInk.primary).frame(width: Space.s8 * 4)
                    .focused($editing)
                    .onSubmit { shell.renameTab(spec.id, to: draft) }
                    .onExitCommand { shell.renamingTab = nil }
                    .onAppear {
                        draft = shell.tabName(spec)
                        editing = true
                    }
            } else if !compact {
                Text(shell.tabName(spec)).coreFont(size: MacTextSize.body, weight: on ? .semibold : .regular)
                    .foregroundStyle(on ? GlassInk.primary : GlassInk.secondary).lineLimit(1)
                    .frame(maxWidth: Space.s8 * 5).fixedSize(horizontal: true, vertical: false)
                    .transition(.opacity)
            }
            if let c = stateColor {
                coreShape(1.5).fill(c).frame(width: 6, height: 6).help(spec.chip?.label ?? "")
            }
            // Always laid out in a fixed 24 pt slot and shown by opacity, so hover never moves the tab. The rail has no room for
            // it: the tab's menu closes the pane.
            if !compact {
                Button {
                    shell.dismissPane(spec.id)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Close \(spec.title)")
                .opacity(hovering ? 1 : 0).allowsHitTesting(hovering)
            }
        }
        .foregroundStyle(GlassInk.secondary)
        .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd)
        .background {
            if on {
                coreShape(Radius.control).fill(GlassInk.lift(0.14))
                    .matchedGeometryEffect(id: "on", in: indicator)
            }
        }
        .animation(Motion.out(Motion.hover), value: hovering)
        .contentShape(coreShape(Radius.control))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { toggleFocus() }
        .onTapGesture { pick() }
        .gesture(
            DragGesture(minimumDistance: Space.s2, coordinateSpace: .named("wsroot"))
                .onChanged { onDrag($0.location, $0.translation) }
                .onEnded { _ in onDragEnd() }
        )
        .contextMenu { menu }
        .help(
            "\(compact ? shell.tabName(spec) + " · " : "")\(spec.title) · right-click for actions, ⌃Tab next tab, ⇧⌘R rename"
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spec.chip.map { "\(shell.tabName(spec)), \($0.label)" } ?? shell.tabName(spec))
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { pick() }
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
                    ForEach(item.children) { c in
                        Button(role: c.destructive ? .destructive : nil, action: c.run) {
                            Label(c.title, systemImage: c.symbol)
                        }
                        .help(c.help ?? "")
                    }
                } label: {
                    Label(item.title, systemImage: item.symbol)
                }
                .disabled(!item.enabled)
            }
        }
        if shell.paneMenus[spec.id] != nil { Divider() }
        Button {
            shell.renamingTab = spec.id
        } label: {
            Label("Rename Tab…", systemImage: "pencil")
        }
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

/// One pane in the workspace: the chrome (clear glass, no head) around its content. On hover a grip appears on its top
/// edge: drag it to move the pane and drop it beside or into another (the drop hint shows where).
private struct PaneHost: View {
    let spec: PaneSpec
    let active: Bool
    let canDrag: Bool
    let scrolling: Bool
    let onDrag: (CGPoint, CGSize) -> Void
    let onDragEnd: () -> Void
    @State private var hovering = false
    @State private var gripHover = false
    /// The grip stays while it is held: the pane moves under the pointer, and losing hover must not end the drag.
    @State private var dragging = false

    var body: some View {
        CorePaneChrome(
            title: spec.title, sub: spec.sub, symbol: spec.symbol,
            state: spec.chip.map { ($0.label, $0.tone, $0.symbol) }, active: active, onClose: {}
        ) {
            spec.content
        }
        .overlay(alignment: .top) {
            if canDrag && (dragging || (hovering && !scrolling)) {
                coreShape(2.5).fill(GlassInk.primary.opacity(gripHover ? 0.75 : 0.4))
                    .frame(width: gripHover ? 64 : 44, height: 5)
                    .padding(.vertical, 6).padding(.horizontal, 24)
                    .contentShape(Rectangle())
                    .onHover { gripHover = $0 }
                    .modifier(GrabPointer(active: dragging))
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .named("wsroot"))
                            .onChanged {
                                dragging = true
                                onDrag($0.location, $0.translation)
                            }
                            .onEnded { _ in
                                dragging = false
                                onDragEnd()
                            }
                    )
                    .help("Drag to move this app")
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .animation(.spring(duration: 0.2), value: gripHover)
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
            .onHover { hovering = $0 }
            .modifier(SeamCursor(horizontal: horizontal, hovering: hovering))
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

/// The grab hand on the grip, open at rest and closed while dragging.
private struct GrabPointer: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(active ? .grabActive : .grabIdle)
        } else {
            content
        }
    }
}

/// The resize cursor over a seam: the system pointer style where it exists, otherwise a push/pop kept balanced even if the
/// seam disappears (a pane closing under the pointer) while hovered.
private struct SeamCursor: ViewModifier {
    let horizontal: Bool
    let hovering: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(horizontal ? .columnResize : .rowResize)
        } else {
            content
                .onChange(of: hovering) { _, now in
                    if now, !pushed {
                        (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                        pushed = true
                    } else if !now {
                        release()
                    }
                }
                .onDisappear { release() }
        }
    }

    private func release() {
        if pushed { NSCursor.pop() }
        pushed = false
    }
}
