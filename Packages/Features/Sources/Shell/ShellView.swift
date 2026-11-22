import CoreUI
import SwiftUI

/// The window content: sky, Home or workspace, status cluster, and everything that opens over them.
public struct ShellView: View {
    @Bindable var shell: ShellModel
    @Environment(\.colorScheme) private var scheme
    @FocusState private var calm: Bool
    @Environment(\.corePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduce
    /// Settings, Appearance, Content background: the Look inside every glass rim, unless an app replaces it.
    @Bindable private var look = LookPrefs.shared

    public init(shell: ShellModel) { self.shell = shell }

    public var body: some View {
        ZStack {
            base
            if shell.lock == .open {
                covers
            } else {
                // Locked: the Unlock card is above everything (an open dialog's own dim buried it, a near-black screen
                // after sleep or a Space switch). The dialogs come back once unlocked; only Touch ID rides above the card.
                let sheet = shell.topDialog.flatMap { $0.id == "step-up" ? $0 : nil }
                UnlockCard(shell: shell, sheetUp: sheet != nil)
                if let d = sheet { dialogLayer(d, id: "top") }
            }
        }
        .coreAnimation(Motion.out(Motion.move), value: shell.lock)
        .animation(Motion.calm(Motion.out(Motion.move), reduce), value: shell.surface)
        .coreAnimation(Motion.out(Motion.ui), value: shell.coverOpen)
        .coreTheme()
        .coreToast($shell.toast)
        .environment(\.coreLook, look.look)
        // The window opens calm: focus rests on the root, so no control shows a ring until the keyboard moves it.
        .focusable()
        .focused($calm)
        .focusEffectDisabled()
        // The one Esc owner: the shell's own layers close here; a pane's back handler only sees Esc when none is open.
        .coreEscape { shell.closeTopmost() }
        .onAppear { calm = true }
        .ignoresSafeArea()
    }

    /// One scrim for the launcher, Settings, dialogs and sheets (prototype MV-05): the desktop behind dims and loses a little colour (no blur: it re-rendered the whole window).
    private var scrimmed: Bool {
        shell.launcherOpen || shell.actionsOpen || shell.overviewOpen || shell.overlay != nil || shell.dialog != nil
            || shell.topDialog != nil || shell.sheet != nil
    }

    @ViewBuilder private var base: some View {
        if shell.setupOpen() { WallpaperView().ignoresSafeArea() } else { desktop }
    }

    private var desktop: some View {
        ZStack {
            sky
            HomeView(shell: shell)
                .environment(\.homeLive, shell.surface == .home)
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
                connectionBanner
                Spacer(minLength: 0)
            }
        }
        // No colour filter on the desktop under the launcher or a dialog (2026-11-21): it redrew the whole desktop, wallpaper
        // and widgets into a second layer every frame, and made the launcher slow. The dim does the job alone.
    }

    /// Reconnecting and offline show a banner under the status cluster; the Home Core button says the same in words. A link notice
    /// (slow down, session renewing, Core restarted) takes the banner's place while it lasts.
    private var connectionBanner: some View {
        ZStack {
            if bannerKey != "" {
                banner.id(bannerKey)
                    .transition(.opacity.combined(with: .offset(y: reduce ? 0 : 4)))
            }
        }
        .animation(Motion.out(Motion.ui), value: bannerKey)
        .onChange(of: bannerKey) { old, new in
            let words: String?
            switch new {
            case "reconnecting": words = String(localized: "Reconnecting to Core", bundle: .module)
            case "offline": words = String(localized: "Core is offline", bundle: .module)
            case "rate": words = String(localized: "Core asked the app to slow down", bundle: .module)
            case "renew": words = String(localized: "The session is renewing", bundle: .module)
            case "restart": words = String(localized: "Core restarted", bundle: .module)
            default:
                words =
                    old == "reconnecting" || old == "offline" ? String(localized: "Back online", bundle: .module) : nil
            }
            if let words { CoreAnnounce.settled("link", words) }
        }
    }

    /// Which banner shows now; changes when it comes, goes or is replaced by another.
    private var bannerKey: String {
        if let notice = shell.linkNotice {
            switch notice {
            case .rateLimited: return "rate"
            case .renewing: return "renew"
            case .restarted: return "restart"
            }
        }
        switch shell.coreLink {
        case .reconnecting: return "reconnecting"
        case .offline: return "offline"
        default: return ""
        }
    }

    /// The banner floats over the widget grid, so it sits on the opaque theme surface: on clear glass alone the
    /// widgets' words showed through it.
    private var banner: some View {
        bannerBody
            .background(palette.surface, in: coreShape(Radius.cardMac))
            .frame(maxWidth: ShellMetrics.bellWidth * 1.5).padding(.top, Space.s1)
    }

    @ViewBuilder private var bannerBody: some View {
        if let notice = shell.linkNotice {
            switch notice {
            case .rateLimited(let until): LinkBanner(.rateLimited(until: until))
            case .renewing: LinkBanner(.renewing)
            case .restarted: LinkBanner(.restarted, dismiss: { shell.linkNotice = nil })
            }
        } else {
            switch shell.coreLink {
            case .reconnecting:
                LinkBanner(.resuming(since: shell.lastLiveAt), retry: shell.retryConnection.map { r in { r() } })
            case .offline: ConnectionBanner(.offline, retry: shell.retryConnection.map { r in { r() } })
            default: EmptyView()
            }
        }
    }

    /// With a workspace open the sky recedes: it dims, loses some colour and grows 3 % over half a second (`shell.css` .in-ws).
    private var sky: some View {
        let ws = shell.surface == .workspace
        let day = scheme == .light
        return Color.clear.overlay {
            WallpaperView()
                .colorMultiply(Color(white: ws ? (day ? 0.9 : 0.62) : 1))
                .saturation(ws ? (day ? 0.8 : 0.85) : 1)
                .scaleEffect(ws && !reduce ? 1.03 : 1)
        }
        .clipped()
        .animation(Motion.calm(Motion.out(0.5), reduce), value: ws)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var covers: some View {
        if let menu = shell.topMenu {
            Color.clear.contentShape(Rectangle()).onTapGesture { shell.topMenu = nil }
                .accessibilityHidden(true)
            Group {
                switch menu {
                case .core: ConnectionPanel(shell: shell)
                case .runners: RunnersPanel(shell: shell)
                case .brain: BrainPanel(shell: shell)
                }
            }
            .id(menu)
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

    /// A neutral dark dim in both themes, as a Mac sheet dims its window (Ahmed, 2026-11-15: the pale day wash hid the desk).
    static let scrim = GlassInk.adaptive(Color.black.opacity(0.42), day: Color.black.opacity(0.2))

    /// `Mac.sheet`: every confirmation is the one ConfirmCard (visual, animated, keyboard driven), over the scrim. The safe
    /// choice comes first and starts highlighted.
    private func sheetLayer(_ sheet: ShellSheet) -> some View {
        let ordered =
            sheet.actions.filter { !$0.primary && !$0.destructive }
            + sheet.actions.filter { $0.primary || $0.destructive }
        return ZStack {
            Self.scrim.onTapGesture { shell.sheet = nil }.accessibilityHidden(true)
            ConfirmCard(
                title: sheet.title, message: sheet.message, symbol: sheet.symbol,
                choices: ordered.enumerated().map { i, a in
                    ConfirmChoice(
                        a.label, symbol: i == 0 ? "arrow.uturn.backward" : a.destructive ? "trash" : "checkmark",
                        destructive: a.destructive
                    ) {
                        shell.sheet = nil
                        a.run()
                    }
                },
                cancel: { shell.sheet = nil })
        }
        .id("sheet-\(sheet.id)")
        .transition(.opacity)
    }
}

extension View {
    /// The window's root: it takes whatever size the window has and never asks for a minimum. The `Window` scene
    /// (`.windowResizability(.contentMinSize)`) makes the content's smallest size the window's minimum, and the reconnect
    /// banner's words, wrapped at zero width, asked for 2174 pt: the full-screen window grew past the bottom of the screen and
    /// Home, the greeting and the Unlock card were centred in it, a third of a screen too low (2026-11-22).
    public func fillsWindow() -> some View {
        frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}
