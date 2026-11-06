import CoreUI
import SwiftUI

/// The window content: sky, Home or workspace, status cluster, and everything that opens over them.
public struct ShellView: View {
    @Bindable var shell: ShellModel
    @Environment(\.colorScheme) private var scheme
    @FocusState private var calm: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce

    public init(shell: ShellModel) { self.shell = shell }

    public var body: some View {
        ZStack {
            base
            covers
            // Above the scrim: a dropped link must stay visible with Settings or a dialog open.
            connectionBanner.padding(.top, ShellMetrics.topBar)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            escape
        }
        .animation(reduce ? nil : Motion.out(Motion.move), value: shell.surface)
        .coreAnimation(Motion.out(Motion.ui), value: shell.coverOpen)
        .coreTheme()
        .coreToast($shell.toast)
        // A toast left from before must not sit under a dialog that has just opened.
        .onChange(of: shell.dialog != nil || shell.topDialog != nil || shell.sheet != nil) { _, open in
            if open { shell.toast = nil }
        }
        // The window opens calm: focus rests on the root, so no control shows a ring until the keyboard moves it.
        .focusable()
        .focused($calm)
        .focusEffectDisabled()
        .onKeyPress(.escape) { shell.closeTopmost() ? .handled : .ignored }
        .onAppear { calm = true }
        .ignoresSafeArea()
    }

    /// One scrim for the launcher, Settings, dialogs and sheets (prototype MV-05): the desktop behind blurs 6 pt and dims.
    private var scrimmed: Bool {
        shell.launcherOpen || shell.actionsOpen || shell.overviewOpen || shell.overlay != nil || shell.dialog != nil
            || shell.topDialog != nil || shell.sheet != nil
    }

    private var base: some View {
        ZStack {
            sky
            HomeView(shell: shell)
                .opacity(shell.surface == .home ? 1 : 0)
                .scaleEffect(shell.surface == .home || reduce ? 1 : 0.97)
                .allowsHitTesting(shell.surface == .home)
                .accessibilityHidden(shell.surface != .home)
            WorkspaceView(shell: shell)
                .opacity(shell.surface == .workspace ? 1 : 0)
                .allowsHitTesting(shell.surface == .workspace)
                .accessibilityHidden(shell.surface != .workspace)
            VStack(spacing: 0) {
                StatusCluster(shell: shell)
                Spacer(minLength: 0)
            }
        }
        .blur(radius: scrimmed ? 6 : 0)
        .saturation(scrimmed ? 0.9 : 1)
        .animation(reduce ? nil : Motion.out(Motion.ui), value: scrimmed)
    }

    /// Reconnecting and offline show a banner under the status cluster; the Home Core button says the same in words. A link notice
    /// (slow down, session renewing, Core restarted) takes the banner's place while it lasts.
    @ViewBuilder private var connectionBanner: some View {
        let width = ShellMetrics.bellWidth * 1.5
        if let notice = shell.linkNotice {
            switch notice {
            case .rateLimited(let until):
                LinkBanner(.rateLimited(until: until)).frame(maxWidth: width)
            case .renewing: LinkBanner(.renewing).frame(maxWidth: width)
            case .restarted:
                LinkBanner(.restarted, dismiss: { shell.linkNotice = nil }).frame(maxWidth: width)
            }
        } else {
            switch shell.coreLink {
            case .reconnecting:
                LinkBanner(.resuming(since: shell.lastLiveAt), retry: shell.retryConnection.map { r in { r() } })
                    .frame(maxWidth: width)
            case .offline:
                ConnectionBanner(.offline, retry: shell.retryConnection.map { r in { r() } })
                    .frame(maxWidth: width)
            default: EmptyView()
            }
        }
    }

    /// With a workspace open the sky recedes: it dims, loses some colour and grows 3 % over half a second (`shell.css` .in-ws).
    private var sky: some View {
        let ws = shell.surface == .workspace
        let day = scheme == .light
        return Color.clear.overlay {
            Image(day ? "HomeSkyDay" : "HomeSky", bundle: .main).resizable().scaledToFill()
                .colorMultiply(Color(white: ws ? (day ? 0.9 : 0.62) : 1))
                .saturation(ws ? (day ? 0.8 : 0.85) : 1)
                .scaleEffect(ws && !reduce ? 1.03 : 1)
        }
        .clipped()
        .animation(reduce ? nil : Motion.out(Motion.reveal), value: ws)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var covers: some View {
        if shell.elevationPanelOpen {
            Color.clear.contentShape(Rectangle()).onTapGesture { shell.elevationPanelOpen = false }
                .accessibilityHidden(true)
            ElevationPanel(shell: shell)
                .padding(.top, ShellMetrics.topBar).padding(.trailing, Space.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.opacity)
        }
        if shell.launcherOpen || shell.actionsOpen || shell.overviewOpen || shell.overlay != nil {
            Self.scrim.onTapGesture { shell.closeTopmost() }
                .transition(.opacity).accessibilityHidden(true)
        } else if shell.bellOpen {
            // The bell glance does not dim Home (prototype); a click outside still closes it.
            Color.clear.contentShape(Rectangle()).onTapGesture { shell.closeTopmost() }.accessibilityHidden(true)
        }
        if shell.launcherOpen {
            LauncherView(shell: shell).frame(maxHeight: .infinity, alignment: .center)
        }
        if shell.overviewOpen {
            OverviewView(shell: shell).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        if shell.actionsOpen {
            LauncherView(shell: shell, actionsOnly: true).frame(maxHeight: .infinity, alignment: .center)
        }
        if shell.bellOpen {
            BellGlance(shell: shell)
                .padding(.top, ShellMetrics.topBar).padding(.trailing, Space.s4).padding(.bottom, Space.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        if shell.overlay == .settings { SettingsView(shell: shell) }
        if shell.overlay == .shortcuts { ShortcutsView(shell: shell) }
        if let sheet = shell.sheet { sheetLayer(sheet) }
        if let d = shell.dialog { dialogLayer(d, id: "dialog") }
        if let d = shell.topDialog { dialogLayer(d, id: "top") }
    }

    private func dialogLayer(_ d: ShellDialog, id: String) -> some View {
        ZStack {
            Self.scrim.onTapGesture { shell.closeTopmost() }.accessibilityHidden(true)
            d.content
        }
        .id("\(id)-\(d.id)")
        // The Touch ID sheet arrives at once: Apple's embedded Touch ID view cancels while it is see-through.
        .transition(d.id == "step-up" ? .identity : .opacity)
    }

    static let scrim = Color(red: 3 / 255, green: 8 / 255, blue: 20 / 255).opacity(0.52)

    /// `Mac.sheet`: every confirmation is the one ConfirmCard (visual, animated, keyboard driven), over the scrim. The safe
    /// choice comes first and starts highlighted.
    private func sheetLayer(_ sheet: ShellSheet) -> some View {
        let safe = sheet.actions.filter { !$0.primary && !$0.destructive }
        let rest = sheet.actions.filter { $0.primary || $0.destructive }
        // Choice 0 is the one Esc and a bare Return run, so it must never destroy: with no safe action of its own the
        // sheet gets a plain Cancel in front.
        let cancel = ConfirmChoice("Cancel", symbol: "arrow.uturn.backward") { shell.sheet = nil }
        let choices: [ConfirmChoice] =
            (safe.isEmpty ? [cancel] : [])
            + (safe + rest).map { a in
                let isSafe = !a.primary && !a.destructive
                return ConfirmChoice(
                    a.label,
                    symbol: isSafe && a.id == safe.first?.id
                        ? "arrow.uturn.backward" : a.destructive ? "trash" : "checkmark",
                    destructive: a.destructive
                ) {
                    shell.sheet = nil
                    a.run()
                }
            }
        return ZStack {
            Self.scrim.onTapGesture { shell.sheet = nil }.accessibilityHidden(true)
            ConfirmCard(
                title: sheet.title, message: sheet.message, symbol: sheet.symbol,
                choices: choices, cancel: { shell.sheet = nil })
        }
        .id("sheet-\(sheet.id)")
        .transition(.opacity)
    }

    /// Esc closes the topmost thing, from anywhere in the window.
    private var escape: some View {
        Button("Close") { shell.closeTopmost() }
            .keyboardShortcut(.cancelAction)
            .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}
