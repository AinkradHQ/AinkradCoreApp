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
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// Debug: `CORE_PANE_WIDTH=<pt>` gives the workspace exactly that width, to see what an app needs (min-width probe).
    #if DEBUG
    private static let probeWidth = ProcessInfo.processInfo.environment["CORE_PANE_WIDTH"].flatMap(Double.init)
        .map { CGFloat($0) }
    /// `CORE_PANE_HEIGHT=<pt>`: the same for height (does a list app still look right 400 pt tall?).
    private static let probeHeight = ProcessInfo.processInfo.environment["CORE_PANE_HEIGHT"].flatMap(Double.init)
        .map { CGFloat($0) }
    #else
    private static let probeWidth: CGFloat? = nil
    private static let probeHeight: CGFloat? = nil
    #endif

    var body: some View {
        GeometryReader { geo in
            let area = CGSize(
                width: Self.probeWidth ?? geo.size.width - ShellMetrics.paneInset * 2,
                height: Self.probeHeight ?? geo.size.height - ShellMetrics.topBar - ShellMetrics.paneInset)
            let mins = Dictionary(uniqueKeysWithValues: shell.panes.map { ($0.id, $0.minWidth) })
            let tiled = shell.tree.layout(
                minWidth: { mins[$0] ?? ShellMetrics.paneMinWidth }, container: area, gap: ShellMetrics.paneGap,
                minHeight: shell.panes.map(\.minHeight).max() ?? ShellMetrics.paneMinHeight)
            let focus = shell.focusedPane
            // A new app joins side by side or stacked while every pane keeps its minimum (`place`); otherwise it gets a
            // workspace. A window shrunk later scrolls sideways.
            let layout = tiled
            ZStack(alignment: .topLeading) {
                // The strip scrolls by its own offset, not a ScrollView: a terminal pane takes every scroll event, so
                // sideways swipes are caught for the whole workspace (StripSwipe), and picking a pane slides it into view.
                let maxX = focus == nil && layout.isStrip ? max(0, layout.contentWidth - area.width) : 0
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        ForEach(shell.allPanes) { spec in
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
                        room: geo.size.width - ShellMetrics.statusRoom,
                        onDrag: { dragTo($0, $1, $2, layout) }, onDragEnd: { dropIt($0) }
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .overlay(alignment: .bottom) {
                if let note = shell.spaceNote { SpaceNoteCard(shell: shell, note: note) }
            }
            .onChange(of: area, initial: true) { _, a in
                shell.workspaceWidth = a.width
                shell.workspaceHeight = a.height
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
    private func pane(_ spec: PaneSpec, layout: TileLayout, area: CGSize) -> some View {
        let focus = shell.focusedPane
        // Panes of other workspaces stay in the tree (a terminal keeps its view) and wait off to the side.
        let away = shell.spaceOffset(of: spec.id)
        let folded = (focus != nil && focus != spec.id) || away != 0
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
            x: dragging
                ? drag!.origin.x + drag!.translation.width
                : slot.minX + (reduce ? 0 : CGFloat(away) * (area.width + ShellMetrics.paneInset)),
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
