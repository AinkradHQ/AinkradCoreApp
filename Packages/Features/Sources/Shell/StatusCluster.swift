import CoreUI
import SwiftUI

/// Top right: Home/Workspace, layout, what is running, the Touch ID elevation chip (placeholder), the bell, Home Core and the emblem.
struct StatusCluster: View {
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        HStack(spacing: Space.s1) {
            StatusButton(
                title: shell.surface == .home ? "Workspace" : "Home",
                symbol: shell.surface == .home ? "sidebar.left" : "square.grid.2x2",
                label: shell.surface == .home ? "Show workspace" : "Show Home"
            ) { shell.toggleSurface() }
            if shell.surface == .workspace && !shell.panes.isEmpty {
                StatusButton(
                    title: nil, symbol: shell.focusedPane == nil ? "rectangle.split.2x1" : "rectangle",
                    label: shell.focusedPane == nil ? "Focus one pane" : "Tile all panes"
                ) { shell.toggleFocusMode() }
            }
            activity
            StatusButton(title: "Locked", symbol: "lock", label: "Touch ID elevation: locked") {
                shell.showToast("Touch ID elevation arrives with the pairing story.")
            }
            StatusButton(
                title: shell.bell.count > 0 ? "\(shell.bell.count)" : nil, symbol: "bell",
                label: shell.bell.count == 0 ? "Notifications" : "Notifications, \(shell.bell.count)",
                on: shell.bellOpen
            ) { shell.toggleBell() }
            StatusButton(title: shell.home.coreName, symbol: "server.rack", label: "\(shell.home.coreName), connected")
            {
                if let core = shell.launcher.entry("core") { core.run() } else { shell.toggleLauncher() }
            }
            Button {
                shell.toggleLauncher()
            } label: {
                Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: MacSize.controlMd - Space.s1)
                    .frame(width: MacSize.controlLg, height: MacSize.controlLg)
            }
            .buttonStyle(.plain)
            .help("Launcher (⌘K)")
            .accessibilityLabel("Launcher")
        }
        .padding(.horizontal, Space.s4)
        .frame(height: ShellMetrics.topBar, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder private var activity: some View {
        let running = shell.home.runningAgents
        let waiting = shell.bell.waiting
        if running > 0 || waiting > 0 {
            HStack(spacing: Space.s1) {
                Image(systemName: waiting > 0 ? "exclamationmark.triangle" : "waveform")
                    .foregroundStyle(palette.tone(waiting > 0 ? .warn : .run).ink).accessibilityHidden(true)
                Text("\(running) running").monospacedDigit()
                if waiting > 0 { Text("· \(waiting) waiting").fontWeight(.semibold) }
            }
            .font(.system(size: MacTextSize.body))
            .padding(.horizontal, Space.s2)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct StatusButton: View {
    let title: String?
    let symbol: String
    let label: String
    var on = false
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s1) {
                Image(systemName: symbol).accessibilityHidden(true)
                if let title { Text(title).lineLimit(1) }
            }
            .font(.system(size: MacTextSize.body))
            .padding(.horizontal, Space.s2)
            .frame(minWidth: MacSize.controlMd, minHeight: MacSize.controlMd)
            .background(on ? palette.navActive : hovering ? palette.uDim : .clear, in: coreShape(Radius.control))
            .contentShape(coreShape(Radius.control))
        }
        .buttonStyle(.plain)
        .focused($focused)
        .focusEffectDisabled()
        .coreFocusRing(focused, radius: Radius.control, palette: palette)
        .onHover { hovering = $0 }
        .animation(Motion.out(Motion.hover), value: hovering)
        .help(label)
        .accessibilityLabel(label)
    }
}
