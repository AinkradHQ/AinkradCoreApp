#if DEBUG
import AppKit
import CoreUI
import Pairing
import Shell
import SwiftUI

/// Debug only. `CORE_SNAPSHOT=<dir> [CORE_THEME=light|dark]` makes the app walk through the shell screens by changing state
/// (no key events, so nothing leaks to other apps), capture its own window with `screencapture -l`, print the full-screen
/// checks and quit. It leaves the system appearance alone: the theme is this app's own appearance.
@MainActor
enum SnapshotRunner {
    static func runIfRequested(_ app: AppModel) async {
        let shell = app.shell
        let env = ProcessInfo.processInfo.environment
        let asked = env.keys.filter { $0.hasPrefix("CORE_") }.sorted()
        if asked.contains(where: { $0.hasSuffix("SNAPSHOT") || $0.hasSuffix("AUDIT") || $0 == "CORE_ESC_CHECK" }) {
            SnapshotCapture.log("walk requested env=\(asked) active=\(NSApp.isActive) windows=\(NSApp.windows.count)")
        }
        if env["CORE_EXIT_FS_ATTEMPT"] != nil {
            try? await Task.sleep(for: .seconds(3))
            NSApp.windows.first { $0.title == "Ainkrad" }?.toggleFullScreen(nil)
        }
        if env["CORE_OPEN_GALLERY"] == "1" { return await GallerySnapshot.open(env: env) }
        if let dir = env["CORE_GALLERY_SNAPSHOT"] { return await GallerySnapshot.run(dir: dir, env: env) }
        if let dir = env["CORE_AGENTS_SNAPSHOT"] { return await AgentsSnapshots.run(app, dir: dir, env: env) }
        if let log = env["CORE_COMPOSER_TEST"] { return await ComposerSelfTest.run(app, log: log) }
        if let dir = env["CORE_SHOWCASE_SHOTS"] { return await ShowcaseShots.run(app, dir: dir, env: env) }
        if let log = env["CORE_SCROLL_BENCH"] { return await ScrollBenchRun.run(app, log: log, env: env) }
        if let dir = env["CORE_ESC_CHECK"] { return await EscapeCheck.run(app, dir: dir) }
        if let dir = env["CORE_A11Y_AUDIT"] { return await A11yAudit.run(app, dir: dir, env: env) }
        if let dir = env["CORE_UPDATES_SNAPSHOT"] { return await UpdatesSnapshots.run(app, dir: dir, env: env) }
        if let dir = env["CORE_HOME_SNAPSHOT"] { return await HomeSnapshots.run(app, dir: dir, env: env) }
        if let dir = env["CORE_PAIR_SNAPSHOT"] { return await PairingSnapshots.run(app, dir: dir, env: env) }
        if let dir = env["CORE_ACC_SNAPSHOT"] { return await AccountsSnapshots.run(app, dir: dir, env: env) }
        // `CORE_ACC_DEMO=<scene>`: Accounts on the stand-in data, left open to click through (no Core is reached).
        if let scene = env["CORE_ACC_DEMO"] {
            try? await Task.sleep(for: .seconds(3))
            return await app.debugAccountsDemo().showInteractive(scene)
        }
        if let dir = env["CORE_PROJECTS_SNAPSHOT"] { return await ProjectsSnapshots.run(app, dir: dir, env: env) }
        // `CORE_PROJECTS_DEMO=<scene>`: Projects on the stand-in data, left open to click through (no Core is reached).
        if let scene = env["CORE_PROJECTS_DEMO"] {
            try? await Task.sleep(for: .seconds(3))
            return await app.debugProjectsDemo().showInteractive(scene)
        }
        if let dir = env["CORE_LEYLINE_SNAPSHOT"] { return await LeylineSnapshots.run(app, dir: dir, env: env) }
        // `CORE_LEYLINE_DEMO=<scene>`: Leyline on the stand-in data, left open to click through (no Core is reached).
        if let scene = env["CORE_LEYLINE_DEMO"] {
            try? await Task.sleep(for: .seconds(3))
            return await app.debugLeylineDemo().showInteractive(scene)
        }
        if let dir = env["CORE_DESIGN_MEASURE"] { return await DesignMeasure.run(app, dir: dir) }
        if let dir = env["CORE_DESIGN_SNAPSHOT"] { return await DesignSnapshots.run(app, dir: dir, env: env) }
        // `CORE_DESIGN_DEMO=<scene>`: Design on the stand-in data, left open to click through (no Core is reached).
        if let scene = env["CORE_DESIGN_DEMO"] {
            try? await Task.sleep(for: .seconds(3))
            return await app.debugDesignDemo().showInteractive(scene)
        }
        if let dir = env["CORE_LORE_SPACE_SNAPSHOT"] { return await LoreSpaceSnapshots.run(app, dir: dir, env: env) }
        // `CORE_LORE_SPACE_DEMO=<scene>`: the Lore space on made-up notes, left open to click through (no Core is reached).
        if let scene = env["CORE_LORE_SPACE_DEMO"] {
            try? await Task.sleep(for: .seconds(3))
            return await app.debugLoreDemo().show(scene)
        }
        // `CORE_LORE_CAPTURE_DEMO=quick|advanced|error`: the quick capture panel on made-up text, opened over the next app
        // brought to the front (it waits until Ainkrad is in the background), and left open.
        if let scene = env["CORE_LORE_CAPTURE_DEMO"] {
            SnapshotCapture.log("capture demo \(scene) waiting")
            try? await Task.sleep(for: .seconds(12))
            SnapshotCapture.log("capture demo active=\(NSApp.isActive)")
            if let t = env["CORE_THEME"] { NSApp.appearance = NSAppearance(named: t == "light" ? .aqua : .darkAqua) }
            app.debugLoreDemo().capture(scene)
            try? await Task.sleep(for: .seconds(1))
            for w in NSApp.windows where w is NSPanel {
                SnapshotCapture.log("capture panel visible=\(w.isVisible) key=\(w.isKeyWindow) frame=\(w.frame)")
            }
            return
        }
        if let dir = env["CORE_LORE_SNAPSHOT"] { return await LoreSnapshots.run(dir: dir, env: env) }
        // `CORE_LORE_DEMO=1`: the Lore editor on the 10,000-word sample note, left open to type in (no Core is reached).
        if env["CORE_LORE_DEMO"] == "1" { return await LoreSnapshots.run(dir: nil, env: env) }
        if let dir = env["CORE_BRAIN_SNAPSHOT"] { return await BrainSnapshots.run(app, dir: dir, env: env) }
        // `CORE_BRAIN_DEMO=<scene>`: the Brain on sample data, left open to click through (no Core is reached).
        if let scene = env["CORE_BRAIN_DEMO"] {
            try? await Task.sleep(for: .seconds(3))
            return await app.debugBrainDemo().showInteractive(scene)
        }
        if let dir = env["CORE_ADMIN_SNAPSHOT"] { return await AdminSnapshots.run(app, dir: dir, env: env) }
        if let dir = env["CORE_TERM_SNAPSHOT"] { return await TerminalSnapshots.run(app, dir: dir, env: env) }
        if let dir = env["CORE_MACHINES_SNAPSHOT"] { return await MachinesSnapshots.run(app, dir: dir, env: env) }
        // `CORE_LOCK_SNAPSHOT=<dir> [CORE_SETTINGS_PAGE=<id>]`: one Settings page on the paired Core (Lockouts, the default,
        // gets two sample locks).
        if let dir = env["CORE_LOCK_SNAPSHOT"] {
            let page = env["CORE_SETTINGS_PAGE"] ?? "lockouts"
            try? await Task.sleep(for: .seconds(4))
            app.debugOpenSettings(page)
            try? await Task.sleep(for: .seconds(1))
            if page == "lockouts" { app.debugSampleLockouts() }
            try? await Task.sleep(for: .seconds(2))
            if let w = NSApp.windows.first(where: { $0.title == "Ainkrad" }) {
                log("shot \(page) \(capture(w, to: "\(dir)/\(page).png"))")
            }
            NSApp.terminate(nil)
            return
        }
        guard let dir = env["CORE_SNAPSHOT"] else { return }
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        // The full-screen toggle above must not undo the theme.
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = await SnapshotCapture.mainWindow() else {
            return log("no main window")
        }
        log("fullscreen=\(window.styleMask.contains(.fullScreen)) size=\(window.frame.size)")
        log("zoomButtonEnabled=\(window.standardWindowButton(.zoomButton)?.isEnabled ?? false)")
        log("exitItems=\(menuItems(#selector(NSWindow.toggleFullScreen(_:))))")
        window.toggleFullScreen(nil)  // try to leave: it must come back
        try? await Task.sleep(for: .seconds(4))
        log("afterExitAttempt fullscreen=\(window.styleMask.contains(.fullScreen))")
        // The full-screen toggle above must not undo the theme.
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)

        func shot(_ name: String) async {
            try? await Task.sleep(for: .seconds(1.6))
            let ok = capture(window, to: "\(dir)/\(name)-\(theme)-app.png")
            let status = ok ? 0 : 1
            log("shot \(name) status=\(status)")
        }
        func pane(_ id: String) { shell.openPane(SampleWorld.samplePane(id, shell)) }

        await shot("01-home")
        shell.toggleLauncher()
        await shot("02-launcher")
        shell.toggleLauncher()
        shell.launcherQuery = "dev"
        shell.toggleLauncher()
        await shot("02b-launcher-query")
        shell.toggleLauncher()
        shell.showToast("Added Today", kind: .ok)
        await shot("02c-toast-ok")
        shell.showToast("The Core is slow to answer. Trying again.", kind: .warn)
        await shot("02d-toast-warn")
        shell.toast = nil
        shell.presentSheet(
            title: "End this session?", message: "It stops now. What it already wrote stays.",
            actions: [ShellSheetAction("Cancel"), ShellSheetAction("End Session", destructive: true)])
        await shot("02e-sheet")
        shell.sheet = nil
        shell.lock = .locked
        await shot("02f-unlock-card")
        shell.lock = .checking
        await shot("02g-unlock-checking")
        // Locked with a dialog open (the Brain import after sleep): the card stays on top and the dialog waits.
        shell.lock = .open
        shell.present(ShellDialog(id: "sample") { Text("A dialog under the lock").padding(80).corePanel() })
        await shot("02h-dialog-open")
        shell.lock = .locked
        await shot("02i-unlock-over-dialog")
        shell.lock = .open
        await shot("02j-dialog-back")
        shell.closeDialog()
        shell.toggleBell()
        await shot("03-bell")
        shell.bellOpen = false
        pane("agents")
        await shot("04-ws1")
        pane("terminals")
        await shot("05-ws2")
        pane("runners")
        await shot("06-ws3")
        shell.debugDrop("runners", on: "agents", edge: "bottom")
        await shot("12-split")
        shell.closePane("runners")
        pane("runners")
        pane("core")
        pane("citadel")
        await shot("07-wsstrip")
        shell.toggleFocusMode()
        await shot("08-focus")
        shell.toggleFocusMode()
        // Workspaces (06-workspaces): the top-bar indicator and no bottom bar, the overview of every workspace, and the
        // last app of a workspace closing (it goes at once and a neighbour comes up).
        shell.newSpace()
        pane("lore")
        shell.switchSpace(to: 0)
        await shot("15a-ws-indicator")
        shell.toggleSpaces()
        await shot("15b-overview-all")
        shell.overviewOpen = false
        shell.switchSpace(to: shell.spaces.count - 1)
        for p in shell.panes { shell.dismissPane(p.id) }
        shell.toast = nil
        await shot("15c-last-app-closed")
        // Placement and the tab strip of every workspace (2026-11-21): apps join while they fit, the next one gets a
        // workspace, and the strip shows the other workspaces as icon groups.
        shell.closeAllPanes()
        pane("agents")
        pane("terminals")
        await shot("16a-two-apps-one-workspace")
        pane("brain")
        await shot("16b-third-app-fits")
        pane("citadel")
        await shot("16c-fourth-app-new-workspace")
        // Back to the first workspace: a terminal (a list app) stacks under one of the three instead of a new workspace.
        shell.goTo("agents")
        shell.openPane(
            PaneSpec(
                id: "terminal-2", title: "Rune", sub: "linux-01", symbol: "terminal",
                minHeight: ShellMetrics.listPaneMinHeight
            ) { Color.clear })
        await shot("16c2-fourth-list-app-stacks")
        shell.closePane("terminal-2")
        pane("runners")
        await shot("16d-strip-three-workspaces")
        shell.goTo("terminals")
        await shot("16e-strip-jump-back")
        for id in ["core", "lore", "leyline", "projects"] { pane(id) }
        shell.goTo("agents")
        for (id, name) in [
            ("agents", "Checkout plan review"), ("terminals", "acme-shop logs"), ("brain", "Weekly notes"),
        ] {
            shell.tabNames[id] = name
        }
        await shot("16f-strip-many-apps")
        // More than the strip has room for: the names fold, all but the active one first, then that one too.
        shell.openPane(PaneSpec(id: "notes", title: "Notes", sub: "Weekly review", symbol: "note.text") { Color.clear })
        shell.tabNames["notes"] = "Weekly review notes"
        let wide = [
            "paintbrush.pointed", "text.book.closed", "square.grid.2x2", "point.3.connected.trianglepath.dotted",
        ]
        for (i, symbol) in (wide + wide).enumerated() {
            var s = PaneSpec(id: "full-\(i)", title: "App \(i)", symbol: symbol) { Color.clear }
            s.fullScreenOnly = true
            shell.openPane(s)
        }
        shell.goTo("agents")
        await shot("16g-strip-names-fold")
        for (i, symbol) in (wide + wide).enumerated() {
            var s = PaneSpec(id: "more-\(i)", title: "More \(i)", symbol: symbol) { Color.clear }
            s.fullScreenOnly = true
            shell.openPane(s)
        }
        shell.goTo("agents")
        await shot("16h-strip-icons-only")
        shell.tabNames = [:]
        shell.closeAllPanes()
        shell.show(.home)
        shell.open(.settings)
        await shot("09-settings")
        shell.settings.selected = "notifications"
        await shot("09b-settings-activity")
        shell.settings.selected = "appearance"
        // Advanced opens once a part has its own look: give the launcher one for the shot, then put it back.
        LookPrefs.shared.setCustom(.launcher, CoreLook(mode: .solid, opacity: 0.9))
        shell.closeTopmost()
        shell.open(.settings)
        shell.settings.selected = "appearance"
        await shot("09c-settings-appearance")
        LookPrefs.shared.setCustom(.launcher, nil)
        shell.open(.shortcuts)
        await shot("10-shortcuts")
        shell.overlay = nil
        shell.editingWidgets = true
        await shot("11-home-edit")
        shell.editingWidgets = false
        for scene in AppModel.addWizardScenes {
            app.debugAddWizard(scene)
            await shot("13-add-\(scene)")
        }
        shell.closeDialog()
        // The connection chip and its pop-up (N14), one per state.
        for (name, link, network) in [
            ("live", CoreLink.live, true), ("reconnecting", .reconnecting, true), ("no-network", .offline, false),
            ("no-answer", .offline, true),
        ] {
            shell.coreLink = link
            shell.networkUp = network
            shell.retryAttempt = link == .live ? 0 : 3
            shell.nextRetryAt = link == .live ? nil : Date().addingTimeInterval(8)
            shell.connectionPanelOpen = true
            await shot("14-chip-\(name)")
        }
        shell.connectionPanelOpen = false
        NSApp.terminate(nil)
    }

    /// The window's own pixels through the window server: needs no screen-recording permission.
    private static func capture(_ window: NSWindow, to path: String) -> Bool {
        SnapshotCapture.png(window, to: path)
    }

    private static func menuItems(_ action: Selector) -> Int {
        func count(_ m: NSMenu) -> Int {
            m.items.reduce(0) { $0 + ($1.action == action ? 1 : 0) + ($1.submenu.map(count) ?? 0) }
        }
        return NSApp.mainMenu.map(count) ?? -1
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("SNAP \(s)\n".utf8)) }
}
#endif
