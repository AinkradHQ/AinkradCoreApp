import CoreUI
import SwiftUI

/// Top right, icons only (E2-2, D-10): Home, Workspace, then Core, Runners and Brain with their dropdowns, the bell and the launcher.
/// Running work is a badge on Runners; what needs you is the mark on the bell.
struct StatusCluster: View {
    @Bindable var shell: ShellModel

    var body: some View {
        // Sessions, as the AI Sessions list counts them: running, and needing you (an approval or your next message).
        let counts = shell.sessionCounts?() ?? (running: shell.home.runningAgents, needYou: shell.waitingOnYou)
        let needsYou = counts.needYou + shell.alertsOnYou + shell.joinRequests > 0
        HStack(spacing: 2) {
            TopBarIcon(
                .home, label: "Home", symbol: "house", on: shell.surface == .home && !shell.coverOpen
            ) { shell.show(.home) }
            TopBarIcon(
                .workspace, label: "Workspace", symbol: "rectangle.split.2x2",
                on: shell.surface == .workspace && !shell.coverOpen
            ) { shell.show(.workspace) }
            TopBarIcon(
                .core, label: coreLabel, symbol: coreSymbol, on: shell.topMenu == .core, tone: coreTone
            ) { shell.toggleMenu(.core) }
            TopBarIcon(
                .runners, label: counts.running == 0 ? "Runners" : "Runners, \(counts.running) running",
                symbol: "server.rack", on: shell.topMenu == .runners, badge: counts.running
            ) { shell.toggleMenu(.runners) }
            TopBarIcon(.brain, label: "Brain", symbol: "brain", on: shell.topMenu == .brain) { shell.toggleMenu(.brain) }
            Spacer().frame(width: Space.s2)
            TopBarIcon(
                .bell, label: shell.bell.count == 0 ? "Notifications" : "Notifications, \(shell.bell.count)",
                symbol: "bell", on: shell.bellOpen, mark: needsYou
            ) { shell.toggleBell() }
            Spacer().frame(width: Space.s2)
            TopBarIcon(.launcher, label: "Launcher (⌘K)", symbol: nil, on: shell.launcherOpen) { shell.toggleLauncher() }
        }
        .padding(.horizontal, Space.s4)
        .frame(height: ShellMetrics.topBar, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .task { shell.watchNetwork() }
    }

    private var coreLabel: String {
        guard let state = shell.chipState else { return "Core" }
        return "\(shell.home.coreName), \(state.popTitle)"
    }
    /// The Core icon tells a broken link at a glance; online it is the plain icon.
    private var coreSymbol: String {
        switch shell.chipState {
        case .noNetwork?: "wifi.slash"
        case .coreNotAnswering?: "exclamationmark.triangle"
        default: "cube"
        }
    }
    private var coreTone: Tone? {
        switch shell.chipState {
        case .noNetwork?: .queue
        case .coreNotAnswering?: .warn
        case .reconnecting?: .done
        default: nil
        }
    }
}

/// Which icon this is, and so which calm loop it plays.
enum TopBarKind { case home, workspace, core, runners, brain, bell, launcher }

/// One top-bar icon: 28 x 26 button, hover well, lit while its dropdown is open. The glyph plays a slow loop (opacity and
/// transform only, never following the pointer); with Reduce Motion it is the still drawing. `badge` counts running work,
/// `mark` is the small square on the bell when something needs you.
private struct TopBarIcon: View {
    let kind: TopBarKind
    let label: String
    let symbol: String?
    var on = false
    var tone: Tone?
    var badge = 0
    var mark = false
    let action: () -> Void
    @Environment(\.corePalette) private var palette

    init(
        _ kind: TopBarKind, label: String, symbol: String?, on: Bool = false, tone: Tone? = nil, badge: Int = 0,
        mark: Bool = false, action: @escaping () -> Void
    ) {
        self.kind = kind
        self.label = label
        self.symbol = symbol
        self.on = on
        self.tone = tone
        self.badge = badge
        self.mark = mark
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            glyph
                .modifier(TopBarLoop(kind: kind))
                .frame(width: 36, height: MacSize.controlMd - Space.s1 / 2)
                .overlay(alignment: .topTrailing) { badgeView }
        }
        .buttonStyle(StatusBarStyle(on: on))
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var glyph: some View {
        if let symbol {
            Image(systemName: symbol).font(.system(size: 15, weight: .regular))
                .foregroundStyle(tone.map { palette.tone($0).ink } ?? palette.text)
                .contentTransition(.symbolEffect(.replace))
        } else {
            Image("Emblem", bundle: .main).resizable().scaledToFit().frame(width: 19, height: 17)
        }
    }

    @ViewBuilder private var badgeView: some View {
        if badge > 0 {
            Text("\(badge)").coreFont(size: 9, weight: .semibold).monospacedDigit().foregroundStyle(.white)
                .padding(.horizontal, 3).frame(minWidth: 14, minHeight: 14)
                .background(palette.btnPrimary, in: coreShape(Radius.chip))
                .offset(x: -1, y: 0).accessibilityHidden(true)
        } else if mark {
            coreShape(2).fill(GlassInk.red).frame(width: 7, height: 7).offset(x: -8, y: 3).accessibilityHidden(true)
        }
    }
}

/// The calm loops of the mockup (`kit-shell.css` k-bi): slow, small, transform and opacity only. Reduce Motion: none.
private struct TopBarLoop: ViewModifier {
    let kind: TopBarKind
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        if reduce {
            content
        } else if kind == .bell {
            // A short ring every seven seconds, still the rest of the time.
            content.keyframeAnimator(initialValue: 0.0, repeating: true) { view, angle in
                view.rotationEffect(.degrees(angle), anchor: .init(x: 0.5, y: 0.1))
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0, duration: 5.8)
                    CubicKeyframe(9, duration: 0.2)
                    CubicKeyframe(-8, duration: 0.2)
                    CubicKeyframe(5, duration: 0.2)
                    CubicKeyframe(0, duration: 0.4)
                }
            }
        } else {
            content
                .opacity(on ? spec.opacity : 1)
                .scaleEffect(x: on ? spec.scaleX : 1, y: on ? spec.scale : 1, anchor: spec.anchor)
                .offset(y: on ? spec.lift : 0)
                .animation(.easeInOut(duration: spec.period).repeatForever(autoreverses: true), value: on)
                .onAppear { on = true }
        }
    }

    private var spec: (period: Double, opacity: Double, scale: Double, scaleX: Double, lift: CGFloat, anchor: UnitPoint) {
        switch kind {
        case .home: (3, 0.6, 1, 1, 0, .center)
        case .workspace: (4, 0.65, 1, 1, 0, .center)
        case .core: (2.5, 0.65, 0.88, 0.88, 0, .center)
        case .runners: (1.9, 1, 0.82, 1, 0, .bottom)
        case .brain: (2.3, 0.55, 0.88, 0.88, 0, .center)
        case .launcher: (2.5, 1, 1, 1, -1.5, .center)
        case .bell: (1, 1, 1, 1, 0, .center)
        }
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
