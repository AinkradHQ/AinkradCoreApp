import CoreUI
import SwiftUI

/// Top right: Home/Workspace, layout, what is running, the admin-unlocked chip (only while unlocked), the bell, the Core connection chip, and the emblem.
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
            StatusButton(
                title: shell.bell.count > 0 ? "\(shell.bell.count)" : nil, symbol: "bell",
                label: shell.bell.count == 0 ? "Notifications" : "Notifications, \(shell.bell.count)",
                on: shell.bellOpen, bounce: reduce ? nil : shell.bell.count
            ) { shell.toggleBell() }
            ConnectionChip(shell: shell)
            Button {
                shell.toggleLauncher()
            } label: {
                Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: MacSize.controlMd - Space.s1)
                    .frame(width: MacSize.controlLg, height: MacSize.controlLg)
            }
            .buttonStyle(StatusBarStyle())
            .help("Launcher (⌘K)")
            .accessibilityLabel("Launcher")
        }
        .padding(.horizontal, Space.s4)
        .frame(height: ShellMetrics.topBar, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .task { shell.watchNetwork() }
    }

    /// "2 running · 1 waiting" (Settings → Activity can hide it). A click opens the bell, where the waiting items are.
    @ViewBuilder private var activity: some View {
        // Sessions, as the AI Sessions list counts them: running, and needing you (an approval or your next message).
        let counts = shell.sessionCounts?() ?? (running: shell.home.runningAgents, needYou: shell.waitingOnYou)
        let running = counts.running
        let waiting = counts.needYou
        if shell.showActivityChip && (running > 0 || waiting > 0) {
            Button {
                shell.toggleBell()
            } label: {
                HStack(spacing: Space.s1) {
                    StatusDot(color: palette.tone(waiting > 0 ? .warn : .run).ink)
                    Text("\(running) running").monospacedDigit().contentTransition(.numericText())
                    if waiting > 0 {
                        Text("· \(waiting) need\(waiting == 1 ? "s" : "") you").monospacedDigit().fontWeight(.semibold)
                            .contentTransition(.numericText())
                    }
                }
                .coreFont(size: MacTextSize.body)
                .padding(.horizontal, Space.s2)
                .frame(minHeight: MacSize.controlMd)
            }
            .buttonStyle(StatusBarStyle())
            .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: running)
            .animation(Motion.calm(Motion.out(Motion.ui), reduce), value: waiting)
            .help(
                waiting > 0
                    ? "\(waiting) AI session\(waiting == 1 ? "" : "s") need\(waiting == 1 ? "s" : "") you. Open notifications"
                    : "Nothing needs you"
            )
            .accessibilityLabel("\(running) running, \(waiting) need you. Open notifications")
        }
    }
}

private struct StatusButton: View {
    let title: String?
    let symbol: String?
    let label: String
    var on = false
    /// Changes when something new arrives: the symbol bounces once (a flash for Reduce Motion is the count itself).
    var bounce: Int?
    var meter: (value: Double, low: Bool)?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s1) {
                if let symbol {
                    Image(systemName: symbol).coreBounce(bounce ?? 0).accessibilityHidden(true)
                }
                if let title { Text(title).lineLimit(1).contentTransition(.numericText()) }
                if let meter {
                    CoreMeter(meter.value, low: meter.low, label: "Time left").frame(width: Space.s6)
                }
            }
            .coreFont(size: MacTextSize.body)
            .padding(.horizontal, Space.s2)
            .frame(minWidth: MacSize.controlMd, minHeight: MacSize.controlMd)
        }
        .buttonStyle(StatusBarStyle(on: on))
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The status bar's buttons: CoreUI's quiet press with its hover well, lit while their panel is open. No focus ring.
/// `fill` is a chip's own tone, which the hover lifts.
struct StatusBarStyle: ButtonStyle {
    var on = false
    var fill: Color = .clear
    func makeBody(configuration: Configuration) -> some View {
        Lit(on: on, fill: fill) {
            CoreQuietPressStyle(radius: Radius.control, scale: 0.97, hoverFill: true).makeBody(
                configuration: configuration)
        }
    }

    private struct Lit<Content: View>: View {
        let on: Bool
        let fill: Color
        @ViewBuilder let content: Content
        @Environment(\.corePalette) private var palette
        var body: some View {
            content
                .background(on ? palette.navActive : fill, in: coreShape(Radius.control))
                .contentShape(coreShape(Radius.control))
                .focusEffectDisabled()
        }
    }
}

/// m:ss, as the prototype's `mmss`.
public enum Countdown {
    public static func text(_ seconds: Int) -> String { coreClock(seconds) }
}
