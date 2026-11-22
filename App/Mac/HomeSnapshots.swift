#if DEBUG
import AppKit
import Accounts
import Pairing
import Shell

/// Debug only. `CORE_HOME_SNAPSHOT=<dir> [CORE_THEME=light|dark]` (with `CORE_DEMO=1`) walks first-run setup, Home (normal, edit
/// mode, gallery, quick action hover) and the bell by changing the app's own state, captures its window and quits. No key events.
@MainActor
enum HomeSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = await SnapshotCapture.mainWindow() else {
            return log("no main window")
        }
        let shell = app.shell
        func shot(_ name: String, wait: Double = 1.8) async {
            try? await Task.sleep(for: .seconds(wait))
            let file = "\(dir)/\(name)-\(theme)-app.png"
            log("shot \(name) \(capture(window, to: file) ? "ok" : "FAILED")")
        }
        for (i, scene) in ["empty", "address", "bootstrap", "typed", "sas", "approved"].enumerated() {
            app.debugFirstRun(scene)
            await shot("setup-\(i + 1)-\(scene)")
        }
        // Just paired: setup over the wallpaper, Home hidden; locked, the Unlock card shows instead; Home only once setup ends.
        app.debugShowDesktop()
        app.debugPairedSetup(true)
        await shot("paired-setup", wait: 2.5)
        shell.lock = .locked
        await shot("paired-setup-locked")
        shell.lock = .open
        await shot("paired-setup-unlocked")
        await app.debugAccountsDemo().show("overview-empty")
        shell.dialog = nil
        app.debugPairedSetupAI()
        await shot("paired-setup-ai", wait: 2.5)
        app.debugPairedSetup(false)
        try? await Task.sleep(for: .seconds(1))
        SetupAIDebug.subscriptionFirst = true
        app.debugPairedSetupAI()
        await shot("paired-setup-ai-sub", wait: 2.5)
        SetupAIDebug.subscriptionFirst = false
        app.debugPairedSetup(false)
        await shot("home", wait: 2.5)
        // Home with no widgets (a fresh account): the greeting must stay where it is with widgets.
        shell.surface = .home
        for w in shell.widgets.items { shell.removeWidget(w.id) }
        shell.toast = nil
        await shot("home-empty", wait: 2.5)
        shell.resetWidgets()
        shell.toast = nil
        // The connection drops (2026-11-22): the banner's words once raised the window's minimum past the screen, so the
        // window grew and Home and the Unlock card sat a third of a screen too low. Each scene logs the window against its screen.
        func frames(_ name: String) {
            let screen = window.screen?.frame ?? .zero
            log("frame \(name) window=\(window.frame) screen=\(screen) fits=\(window.frame.height <= screen.height)")
        }
        let live = shell.coreLink
        shell.coreLink = .reconnecting
        await shot("home-reconnecting", wait: 2.5)
        frames("home-reconnecting")
        shell.coreLink = .offline
        await shot("home-offline", wait: 2.5)
        frames("home-offline")
        // Waking: the app locks while the link is still down, then unlocks and the link comes back.
        shell.coreLink = .reconnecting
        shell.lock = .locked
        await shot("home-after-wake-locked", wait: 2.5)
        frames("home-after-wake-locked")
        shell.lock = .open
        shell.coreLink = live
        await shot("home-after-wake", wait: 2.5)
        frames("home-after-wake")
        // The launcher over Home: it follows Appearance like the panes now.
        shell.toggleLauncher()
        await shot("launcher", wait: 1.5)
        shell.toggleLauncher()
        shell.debugForceQuickHover = true
        await shot("quick-hover")
        shell.debugForceQuickHover = false
        shell.editingWidgets = true
        await shot("home-edit")
        shell.editingWidgets = false
        shell.addingWidget = true
        await shot("gallery")
        shell.addingWidget = false
        shell.toggleBell()
        await shot("bell")
        shell.bellOpen = false
        NSApp.terminate(nil)
    }

    private static func capture(_ window: NSWindow, to path: String) -> Bool {
        SnapshotCapture.png(window, to: path)
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("SNAP \(s)\n".utf8)) }
}
#endif
