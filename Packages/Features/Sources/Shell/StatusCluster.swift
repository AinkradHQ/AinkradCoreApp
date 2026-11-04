import CoreUI
import SwiftUI

/// Top right: Home/Workspace, layout, what is running, the Touch ID elevation chip, the bell, Home Core and the emblem.
struct StatusCluster: View {
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

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
            ElevationChip(shell: shell)
            StatusButton(
                title: shell.bell.count > 0 ? "\(shell.bell.count)" : nil, symbol: "bell",
                label: shell.bell.count == 0 ? "Notifications" : "Notifications, \(shell.bell.count)",
                on: shell.bellOpen, bounce: reduce ? nil : shell.bell.count
            ) { shell.toggleBell() }
            StatusButton(title: coreTitle, symbol: nil, label: "\(shell.home.coreName), \(coreWord)", gem: gem) {
                if shell.coreLink == .offline, let retry = shell.retryConnection {
                    retry()
                } else if let core = shell.launcher.entry("core") {
                    core.run()
                } else {
                    shell.toggleLauncher()
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
    /// The gem beside the Core's name: blue and beating while connected, amber while it comes back, grey when it is not there.
    private var gem: CoreGem {
        switch shell.coreLink {
        case .live: .live
        case .connecting, .reconnecting: .waiting
        case .none, .offline: .away
        }
    }

    /// "2 running · 1 waiting" (Settings → Activity can hide it). A click opens the bell, where the waiting items are.
    @ViewBuilder private var activity: some View {
        let running = shell.home.runningAgents
        let waiting = shell.bell.waiting
        if shell.showActivityChip && (running > 0 || waiting > 0) {
            Button {
                shell.toggleBell()
            } label: {
                HStack(spacing: Space.s1) {
                    StatusDot(color: palette.tone(waiting > 0 ? .warn : .run).ink)
                    Text("\(running) running").monospacedDigit().contentTransition(.numericText())
                    if waiting > 0 {
                        Text("· \(waiting) waiting").monospacedDigit().fontWeight(.semibold)
                            .contentTransition(.numericText())
                    }
                }
                .font(.system(size: MacTextSize.body))
                .padding(.horizontal, Space.s2)
                .frame(minHeight: MacSize.controlMd)
                .contentShape(coreShape(Radius.control))
            }
            .buttonStyle(.plain)
            .animation(reduce ? nil : Motion.out(Motion.ui), value: running)
            .animation(reduce ? nil : Motion.out(Motion.ui), value: waiting)
            .help(waiting > 0 ? "\(waiting) waiting on you. Open notifications" : "Nothing waiting on you")
            .accessibilityLabel("\(running) running, \(waiting) waiting. Open notifications")
        }
    }
}

enum CoreGem { case live, waiting, away }

private struct StatusButton: View {
    let title: String?
    let symbol: String?
    let label: String
    var on = false
    var gem: CoreGem?
    /// Changes when something new arrives: the symbol bounces once (a flash for Reduce Motion is the count itself).
    var bounce: Int?
    var meter: (value: Double, low: Bool)?
    let action: () -> Void
    @Environment(\.corePalette) private var palette
    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s1) {
                if let gem {
                    GemMark(state: gem)
                } else if let symbol {
                    Image(systemName: symbol).symbolEffect(.bounce, value: bounce ?? 0).accessibilityHidden(true)
                }
                if let title { Text(title).lineLimit(1).contentTransition(.numericText()) }
                if let meter {
                    CoreMeter(meter.value, low: meter.low, label: "Elevation time left").frame(width: Space.s6)
                }
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

/// Locked, unlocked with the time left, or locking soon. The chip says it in words and a symbol; the bar only shows the time.
private struct ElevationChip: View {
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        if let until = shell.elevatedUntil, until > Date() {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = max(0, Int(until.timeIntervalSince(ctx.date).rounded(.up)))
                let soon = left <= 60
                StatusButton(
                    title: "\(soon ? "Locks in" : "Unlocked") \(Countdown.text(left))", symbol: soon ? "lock.badge.clock" : "lock.open",
                    label: "Touch ID elevation: admin actions unlocked for \(Countdown.text(left))",
                    on: shell.elevationPanelOpen, meter: (Double(left) / shell.elevationSpan, soon)
                ) { shell.elevationPanelOpen.toggle() }
            }
        } else {
            StatusButton(
                title: "Locked", symbol: "lock", label: "Touch ID elevation: admin actions are locked",
                on: shell.elevationPanelOpen
            ) { shell.elevationPanelOpen.toggle() }
        }
    }
}

/// m:ss, as the prototype's `mmss`.
enum Countdown {
    static func text(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
}

/// What the elevation chip opens: what is unlocked, the time left, and Renew / Unlock with Touch ID.
struct ElevationPanel: View {
    @Bindable var shell: ShellModel
    @Environment(\.corePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let until = shell.elevatedUntil, until > Date() {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = max(0, Int(until.timeIntervalSince(ctx.date).rounded(.up)))
                    VStack(alignment: .leading, spacing: Space.s3) {
                        header(left <= 60 ? "Locks in \(Countdown.text(left))" : "Unlocked for \(Countdown.text(left))", "lock.open")
                        CoreMeter(Double(left) / shell.elevationSpan, low: left <= 60, label: "Elevation time left")
                    }
                }
                text("Adding devices, renaming, revoking, scopes and clearing lockouts go through without asking again.")
            } else {
                header("Admin actions are locked", "lock")
                text(
                    "Adding, renaming or revoking a device, changing scopes and clearing lockouts ask for Touch ID. Once confirmed they stay unlocked for 5 minutes."
                )
            }
            Text("Elevation ends early if the Core restarts or this device is revoked.")
                .font(.system(size: MacTextSize.meta)).foregroundStyle(palette.text2)
                .fixedSize(horizontal: false, vertical: true)
            let on = shell.elevatedUntil.map { $0 > Date() } ?? false
            Button(on ? "Renew with Touch ID" : "Unlock with Touch ID") {
                shell.elevationPanelOpen = false
                shell.elevate?()
            }
            .buttonStyle(CoreButtonStyle(on ? .secondary : .prominent))
            .frame(maxWidth: .infinity)
        }
        .padding(Space.s4)
        .frame(width: Space.s8 * 10)
        .corePanel(radius: Radius.panel, padding: 0)
        .overlay { coreShape(Radius.panel).strokeBorder(palette.glassCardEdge, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Touch ID elevation")
    }

    private func header(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(title).font(.system(size: MacTextSize.title, weight: .semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func text(_ s: String) -> some View {
        Text(s).foregroundStyle(palette.text2).fixedSize(horizontal: false, vertical: true)
    }
}

/// The blue mark beside "Home Core": a rounded diamond. Connected, it beats once every 3.6 s; Reduce Motion: a slow fade instead.
private struct GemMark: View {
    let state: CoreGem
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var beat = false

    var body: some View {
        coreShape(Space.s1 / 2)
            .fill(
                state == .live ? palette.primary : state == .waiting ? palette.warning : palette.text2.opacity(0.6)
            )
            .frame(width: Space.s2 + Space.s1, height: Space.s2 + Space.s1)
            .rotationEffect(.degrees(45))
            .scaleEffect(state == .live && beat && !reduce ? 1.18 : 1)
            .opacity(state == .live && beat && reduce ? 0.55 : 1)
            .animation(
                state == .live ? .easeInOut(duration: 1.8).repeatForever(autoreverses: true) : .default, value: beat
            )
            .onAppear { beat = true }
            .accessibilityHidden(true)
    }
}
