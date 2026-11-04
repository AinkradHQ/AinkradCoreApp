import AppKit
import CoreUI
import SwiftUI

/// The pane workspace: panes in columns under the status cluster, a Stage-style strip when they do not fit, and focus mode.
struct WorkspaceView: View {
    @Bindable var shell: ShellModel
    @State private var drag: (id: String, startX: CGFloat, dx: CGFloat)?
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        GeometryReader { geo in
            let area = CGSize(
                width: geo.size.width - ShellMetrics.paneInset * 2,
                height: geo.size.height - ShellMetrics.topBar - ShellMetrics.paneInset)
            let layout = PaneLayout.make(
                minWidths: shell.panes.map(\.minWidth), fractions: shell.paneFractions, container: area,
                gap: ShellMetrics.paneGap,
                minHeight: ShellMetrics.paneMinHeight)
            ZStack(alignment: .topLeading) {
                if shell.panes.isEmpty { empty }
                ScrollView(.horizontal, showsIndicators: layout.isStrip && shell.focusedPane == nil) {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(shell.panes.enumerated()), id: \.element.id) { i, spec in
                            pane(spec, index: i, layout: layout, area: area)
                        }
                        if shell.focusedPane == nil && !layout.isStrip && drag == nil {
                            ForEach(0..<max(shell.panes.count - 1, 0), id: \.self) { i in
                                Seam(shell: shell, index: i, layout: layout, area: area)
                            }
                        }
                    }
                    .frame(
                        width: shell.focusedPane == nil ? max(layout.contentWidth, area.width) : area.width,
                        height: max(area.height, layout.frames.first?.height ?? 0), alignment: .topLeading)
                }
                .scrollDisabled(shell.focusedPane != nil || !layout.isStrip)
                .frame(width: area.width, height: area.height)
                .padding(.leading, ShellMetrics.paneInset)
                .padding(.top, ShellMetrics.topBar)
                if shell.focusedPane != nil { focusTabs.frame(maxHeight: .infinity, alignment: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func pane(_ spec: PaneSpec, index i: Int, layout: PaneLayout, area: CGSize) -> some View {
        let focus = shell.focusedPane
        let folded = focus != nil && focus != spec.id
        let slot = focus == spec.id ? CGRect(origin: .zero, size: area) : layout.frames[i]
        let dragging = drag?.id == spec.id
        PaneHost(spec: spec, active: shell.activePane == spec.id && (focus != nil || shell.panes.count > 1)) { value in
            guard focus == nil else { return }
            if drag?.id != spec.id { shell.activePane = spec.id }
            drag = (spec.id, drag?.id == spec.id ? drag!.startX : slot.minX, value.translation.width)
            let target = layout.nearestIndex(toX: drag!.startX + slot.width / 2 + value.translation.width)
            if target != i { shell.movePane(spec.id, to: target) }
        } onDragEnd: {
            withAnimation(Motion.out(Motion.move)) { drag = nil }
        } onClose: {
            shell.closePane(spec.id)
        }
        .frame(width: slot.width, height: slot.height)
        // Reduce Motion: positions snap, the pane fades in and out; otherwise it travels and scales.
        .scaleEffect(folded || dragging ? coreScale(0.96) : 1)
        .offset(x: dragging ? drag!.startX + drag!.dx : slot.minX, y: slot.minY)
        .animation(reduce ? nil : Motion.out(Motion.move), value: slot)
        .opacity(folded ? 0 : 1)
        .allowsHitTesting(!folded)
        .zIndex(dragging ? 1 : 0)
        .transition(.opacity.combined(with: .scale(scale: coreScale(0.94))))
        .onTapGesture { shell.activePane = spec.id }
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

    private var focusTabs: some View {
        HStack(spacing: Space.s1) {
            ForEach(shell.panes) { p in
                Button {
                    shell.focusedPane = p.id
                    shell.activePane = p.id
                } label: {
                    Text(p.title).font(.system(size: MacTextSize.body, weight: .medium)).lineLimit(1)
                        .padding(.horizontal, Space.s3).frame(height: MacSize.controlMd)
                        .background(
                            shell.focusedPane == p.id ? palette.navActive : .clear, in: coreShape(Radius.control))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Focus \(p.title)")
                .accessibilityAddTraits(shell.focusedPane == p.id ? .isSelected : [])
            }
        }
        .padding(Space.s1)
        .coreGlass(radius: Radius.cardMac)
        .padding(.bottom, Space.s3)
        .frame(maxWidth: .infinity)
    }
}

/// One pane in the workspace: chrome plus a drag handle on the head.
private struct PaneHost: View {
    let spec: PaneSpec
    let active: Bool
    let onDrag: (DragGesture.Value) -> Void
    let onDragEnd: () -> Void
    let onClose: () -> Void

    var body: some View {
        CorePaneChrome(
            title: spec.title, sub: spec.sub, symbol: spec.symbol,
            state: spec.chip.map { ($0.label, $0.tone, $0.symbol) }, active: active, onClose: onClose
        ) {
            spec.content
        }
        .overlay(alignment: .top) {
            Color.clear.frame(height: MacSize.controlLg + Space.s4)
                .padding(.trailing, MacSize.controlMd + Space.s4)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: Space.s1, coordinateSpace: .global).onChanged(onDrag).onEnded { _ in
                        onDragEnd()
                    }
                )
                .accessibilityHidden(true)
        }
    }
}

/// The gap between two panes is a handle: drag it to trade width between them, never below either pane's minimum.
private struct Seam: View {
    @Bindable var shell: ShellModel
    let index: Int
    let layout: PaneLayout
    let area: CGSize
    @State private var start: (left: CGFloat, right: CGFloat)?
    @State private var hovering = false
    @Environment(\.corePalette) private var palette

    var body: some View {
        let left = layout.frames[index]
        let right = layout.frames[index + 1]
        let gap = ShellMetrics.paneGap
        Color.clear
            .frame(width: gap, height: left.height)
            .overlay {
                coreShape(Space.s1).fill(palette.primary.opacity(hovering || start != nil ? 0.9 : 0))
                    .frame(width: Space.s1, height: Space.s8 * 2)
            }
            .contentShape(Rectangle())
            .offset(x: left.maxX, y: 0)
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        let s = start ?? (left.width, right.width)
                        start = s
                        let minL = shell.panes[index].minWidth
                        let minR = shell.panes[index + 1].minWidth
                        let target = min(max(s.left + v.translation.width, minL), s.left + s.right - minR)
                        let avail = area.width - gap * CGFloat(shell.panes.count - 1)
                        shell.setSeam(index, leftFraction: target / avail)
                    }
                    .onEnded { _ in start = nil }
            )
            .accessibilityElement()
            // A seam can be drawn once more after its pane closed (both closing at once): no index past the end.
            .accessibilityLabel(
                shell.panes.indices.contains(index + 1)
                    ? "Resize \(shell.panes[index].title) and \(shell.panes[index + 1].title)" : "Resize panes"
            )
            .accessibilityAdjustableAction { dir in
                let avail = area.width - gap * CGFloat(shell.panes.count - 1)
                let step: CGFloat = Space.s8 * (dir == .increment ? 1 : -1)
                let minL = shell.panes[index].minWidth
                let minR = shell.panes[index + 1].minWidth
                let target = min(max(left.width + step, minL), left.width + right.width - minR)
                shell.setSeam(index, leftFraction: target / avail)
            }
    }
}
