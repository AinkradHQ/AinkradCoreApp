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
                if focus != nil { FocusTabs(shell: shell).frame(maxHeight: .infinity, alignment: .top) }
            }
        }
    }

    @ViewBuilder
    private func pane(_ spec: PaneSpec, layout: TileLayout, area: CGSize) -> some View {
        let focus = shell.focusedPane
        let folded = focus != nil && focus != spec.id
        let tiled = layout.frames[spec.id] ?? CGRect(origin: .zero, size: area)
        let slot = focus == spec.id ? CGRect(origin: .zero, size: area) : tiled
        let dragging = drag?.id == spec.id
        PaneHost(
            spec: spec, active: shell.activePane == spec.id && (focus != nil || shell.panes.count > 1), shell: shell
        ) { value in
            guard focus == nil else { return }
            if drag?.id != spec.id { shell.activePane = spec.id }
            drag = (spec.id, drag?.id == spec.id ? drag!.origin : slot.origin, value.translation)
            drop = TileTree.dropTarget(at: value.location, frames: layout.frames, excluding: spec.id)
        } onDragEnd: {
            withAnimation(Motion.out(Motion.move)) {
                if let drop { shell.dropPane(spec.id, on: drop.target, edge: drop.edge) }
                drag = nil
                drop = nil
            }
        }
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

/// Focus mode's tabs, in the title strip (`#tabs`): one sliding indicator, the sub-title when a pane has one, 220 pt at most.
private struct FocusTabs: View {
    @Bindable var shell: ShellModel
    @Namespace private var indicator
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        HStack(spacing: Space.s1) {
            ForEach(shell.panes) { p in
                let on = shell.focusedPane == p.id
                Button {
                    shell.focusedPane = p.id
                    shell.activePane = p.id
                } label: {
                    Text(p.sub ?? p.title).font(.system(size: MacTextSize.body, weight: .medium)).lineLimit(1)
                        .truncationMode(.tail)
                        // As wide as the label, 220 pt at most: frame first, then fixedSize so it does not stretch to fill.
                        .frame(maxWidth: Space.s8 * 7)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd)
                        .background {
                            if on {
                                coreShape(Radius.control).fill(palette.navActive)
                                    .matchedGeometryEffect(id: "on", in: indicator)
                            }
                        }
                        .contentShape(coreShape(Radius.control))
                }
                .buttonStyle(.plain)
                .help(p.sub.map { "\(p.title) · \($0)" } ?? p.title)
                .accessibilityLabel("Focus \(p.title)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Space.s1)
        .coreGlass(radius: Radius.cardMac)
        .animation(reduce ? nil : Motion.out(Motion.move), value: shell.focusedPane)
        // ← and → move between tabs and select as they go.
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

/// One pane in the workspace: chrome plus a drag handle on the head. A double click on the head toggles focus mode; the head's
/// menu closes the pane, the others, or focuses this one.
private struct PaneHost: View {
    let spec: PaneSpec
    let active: Bool
    let shell: ShellModel
    let onDrag: (DragGesture.Value) -> Void
    let onDragEnd: () -> Void

    var body: some View {
        CorePaneChrome(
            title: spec.title, sub: spec.sub, symbol: spec.symbol,
            state: spec.chip.map { ($0.label, $0.tone, $0.symbol) }, active: active,
            onClose: { shell.dismissPane(spec.id) }
        ) {
            spec.content
        }
        .overlay(alignment: .top) {
            Color.clear.frame(height: MacSize.controlLg + Space.s4)
                .padding(.trailing, MacSize.controlMd + Space.s4)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { toggleFocus() }
                .gesture(
                    DragGesture(minimumDistance: Space.s1, coordinateSpace: .named("ws")).onChanged(onDrag).onEnded {
                        _ in onDragEnd()
                    }
                )
                .contextMenu {
                    Button(shell.focusedPane == spec.id ? "Tile All Panes" : "Focus This Pane") { toggleFocus() }
                    Divider()
                    Button("Close Pane") { shell.dismissPane(spec.id) }
                    Button("Close Other Panes") { shell.closeOtherPanes(except: spec.id) }
                        .disabled(shell.panes.count < 2)
                }
                .accessibilityHidden(true)
        }
    }

    private func toggleFocus() {
        shell.activePane = spec.id
        if shell.focusedPane == nil { shell.focusedPane = spec.id } else { shell.focusedPane = nil }
        shell.surface = .workspace
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
