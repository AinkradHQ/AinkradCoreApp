import CoreUI
import SwiftUI

/// Top right: Home/Workspace, layout, what is running, the Touch ID elevation chip (placeholder), the bell, the Core's state when it is not connected, and the emblem.
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
            elevation
            StatusButton(
                title: shell.bell.count > 0 ? "\(shell.bell.count)" : nil, symbol: "bell",
                label: shell.bell.count == 0 ? "Notifications" : "Notifications, \(shell.bell.count)",
                on: shell.bellOpen
            ) { shell.toggleBell() }
            // The Core is reached from the launcher; the bar names it only when the link is not live.
            if shell.coreLink != .live {
                StatusButton(title: coreTitle, symbol: coreSymbol, label: "\(shell.home.coreName), \(coreWord)") {
                    if shell.coreLink == .offline, let retry = shell.retryConnection { retry() }
                }
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

    /// "Locked" until Touch ID, then "Elevated until 14:32". A word and a symbol, never a colour alone.
    @ViewBuilder private var elevation: some View {
        if let until = shell.elevatedUntil, until > Date() {
            StatusButton(
                title: "Elevated until \(until.formatted(date: .omitted, time: .shortened))", symbol: "lock.open",
                label: "Touch ID elevation: elevated until \(until.formatted(date: .omitted, time: .shortened))",
                on: true
            ) { shell.elevate?() }
        } else {
            StatusButton(title: "Locked", symbol: "lock", label: "Touch ID elevation: locked") { shell.elevate?() }
        }
    }

    private var coreWord: String {
        switch shell.coreLink {
        case .none: "not connected"
        case .connecting: "connecting"
        case .live: "connected"
        case .reconnecting: "reconnecting"
        case .offline: "offline"
        }
    }
    private var coreTitle: String {
        switch shell.coreLink {
        case .live: shell.home.coreName
        case .none: "Not connected"
        case .connecting: "Connecting"
        case .reconnecting: "Reconnecting"
        case .offline: "Offline"
        }
    }
    private var coreSymbol: String {
        switch shell.coreLink {
        case .live: "server.rack"
        case .none, .offline: "wifi.slash"
        case .connecting, .reconnecting: "arrow.triangle.2.circlepath"
        }
    }

    @ViewBuilder private var activity: some View {
        let running = shell.home.runningAgents
        let waiting = shell.bell.waiting
        if running > 0 || waiting > 0 {
            HStack(spacing: Space.s1) {
                StatusDot(color: palette.tone(waiting > 0 ? .warn : .run).ink)
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
    let symbol: String?
    let label: String
    var on = false
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s1) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) } else { CoreMark() }
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

/// The blue mark beside "Home Core": a rounded diamond, the connection state is the word next to it.
private struct CoreMark: View {
    @Environment(\.corePalette) private var palette
    var body: some View {
        coreShape(Space.s1).fill(palette.primary).frame(width: Space.s2 + Space.s1, height: Space.s2 + Space.s1)
            .rotationEffect(.degrees(45)).accessibilityHidden(true)
    }
}
