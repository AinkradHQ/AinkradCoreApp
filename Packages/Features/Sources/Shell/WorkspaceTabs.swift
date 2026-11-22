import CoreUI
import SwiftUI

/// The top bar's left (Ahmed, 2026-11-21: "show tabs from all workspaces smartly and compact"): one group per workspace, in
/// workspace order. The current workspace's apps are full tabs (icon and name, the active one raised, dragging tiles); every
/// other workspace is a quiet well of icons with their state dots, and a click goes there and picks that app. Always one
/// line: when the strip runs out of room the names fold away, first all but the active one, then that one too.
struct PaneTabs: View {
    @Bindable var shell: ShellModel
    /// A narrow window: every tab shrinks to its icon (and state dot), the rail of the AI Sessions narrow mockup.
    let compact: Bool
    /// The room left of the status cluster.
    let room: CGFloat
    let onDrag: (String, CGPoint, CGSize) -> Void
    let onDragEnd: (String) -> Void
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// How much of the names fits: all of them, only the active tab's, or none.
    enum Names { case all, active, none }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !compact {
                strip(.all)
                strip(.active)
            }
            strip(.none)
        }
        .frame(maxWidth: room, alignment: .leading)
        .coreAnimation(Motion.out(Motion.ui), value: shell.focusedPane ?? shell.activePane)
        // Switching workspace: the new current group opens into tabs, the one left folds into its well.
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: shell.spaceIndex)
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: compact)
        .coreSideKeys {
            shell.cyclePane($0)
            return .handled
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Space.s4)
        .padding(.top, Space.s2)
        .frame(height: ShellMetrics.topBar, alignment: .top)
    }

    private func strip(_ names: Names) -> some View {
        let at = shell.spaceIndex
        return HStack(spacing: Space.s2) {
            ForEach(Array(shell.spaces.enumerated()), id: \.element.id) { i, space in
                if i == at {
                    HStack(spacing: Space.s1) {
                        ForEach(shell.panes) { p in
                            let on = (shell.focusedPane ?? shell.activePane) == p.id
                            PaneTab(
                                shell: shell, spec: p, compact: names == .none || (names == .active && !on), on: on,
                                indicator: indicator,
                                onDrag: { onDrag(p.id, $0, $1) }, onDragEnd: { onDragEnd(p.id) })
                        }
                    }
                    .transition(.opacity)
                } else {
                    SpaceGroup(shell: shell, index: i).transition(.opacity)
                }
            }
        }
        .padding(Space.s1)
        .coreGlass(radius: Radius.cardMac)
        .fixedSize()
    }
}

/// Another workspace's apps as icons in one quiet rounded well.
private struct SpaceGroup: View {
    @Bindable var shell: ShellModel
    let index: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(shell.panes(inSpace: index)) { p in
                SpaceAppIcon(shell: shell, spec: p, space: index)
            }
        }
        .background(GlassInk.lift(0.07), in: coreShape(Radius.control))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace \(index + 1)")
    }
}

private struct SpaceAppIcon: View {
    @Bindable var shell: ShellModel
    let spec: PaneSpec
    let space: Int
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        Button {
            shell.goTo(spec.id)
        } label: {
            // Hover opens the icon into a tab with its name (Ahmed, 2026-11-22); leaving folds it back.
            HStack(spacing: Space.s1) {
                Image(systemName: spec.symbol).coreFont(size: MacTextSize.body, weight: .medium)
                    .frame(width: MacSize.controlMd - Space.s2, height: MacSize.controlMd)
                if hovering {
                    Text(shell.tabName(spec)).coreFont(size: MacTextSize.body).lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.trailing, Space.s2)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(hovering ? GlassInk.primary : GlassInk.secondary)
            .padding(.leading, Space.s1)
            .frame(minWidth: MacSize.controlMd, minHeight: MacSize.controlMd)
            .overlay(alignment: .topTrailing) {
                if let c = PaneTab.stateColor(spec) {
                    coreShape(1.5).fill(c).frame(width: 6, height: 6).padding(Space.s1)
                }
            }
            .background(hovering ? GlassInk.lift(0.1) : .clear, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: hovering)
        .help("\(shell.tabName(spec)) · Workspace \(space + 1)\(spec.chip.map { " · \($0.label)" } ?? "")")
        .accessibilityLabel(spec.chip.map { "\(shell.tabName(spec)), \($0.label)" } ?? shell.tabName(spec))
        .accessibilityHint("Goes to workspace \(space + 1)")
    }
}

struct PaneTab: View {
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

    /// The state dot's colour, shared with the icons of the other workspaces.
    static func stateColor(_ spec: PaneSpec) -> Color? {
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
            } else if !compact || hovering {
                Text(shell.tabName(spec)).coreFont(size: MacTextSize.body, weight: on ? .semibold : .regular)
                    .foregroundStyle(on ? GlassInk.primary : GlassInk.secondary).lineLimit(1)
                    .frame(maxWidth: Space.s8 * 5).fixedSize(horizontal: true, vertical: false)
                    .transition(.opacity)
            }
            if let c = Self.stateColor(spec) {
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
