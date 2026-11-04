#if DEBUG
import AppKit
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
        if env["CORE_EXIT_FS_ATTEMPT"] != nil {
            try? await Task.sleep(for: .seconds(3))
            NSApp.windows.first { $0.title == "Ainkrad Core" }?.toggleFullScreen(nil)
        }
        if let dir = env["CORE_GALLERY_SNAPSHOT"] { return await GallerySnapshot.run(dir: dir, env: env) }
        if let dir = env["CORE_PAIR_SNAPSHOT"] { return await PairingSnapshots.run(app, dir: dir, env: env) }
        if let dir = env["CORE_TERM_SNAPSHOT"] { return await TerminalSnapshots.run(app, dir: dir, env: env) }
        guard let dir = env["CORE_SNAPSHOT"] else { return }
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = NSApp.windows.first(where: { $0.title == "Ainkrad Core" }) else {
            return log("no main window")
        }
        log("fullscreen=\(window.styleMask.contains(.fullScreen)) size=\(window.frame.size)")
        log("zoomButtonEnabled=\(window.standardWindowButton(.zoomButton)?.isEnabled ?? false)")
        log("exitItems=\(menuItems(#selector(NSWindow.toggleFullScreen(_:))))")
        window.toggleFullScreen(nil)  // try to leave: it must come back
        try? await Task.sleep(for: .seconds(4))
        log("afterExitAttempt fullscreen=\(window.styleMask.contains(.fullScreen))")

        func shot(_ name: String) async {
            try? await Task.sleep(for: .seconds(1.6))
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-o", "-l", String(window.windowNumber), "\(dir)/\(name)-\(theme)-app.png"]
            try? p.run()
            p.waitUntilExit()
            log("shot \(name) status=\(p.terminationStatus)")
        }
        func pane(_ id: String) { shell.openPane(SampleWorld.samplePane(id, shell)) }

        await shot("01-home")
        shell.toggleLauncher()
        await shot("02-launcher")
        shell.toggleBell()
        await shot("03-bell")
        shell.bellOpen = false
        pane("agents")
        await shot("04-ws1")
        pane("terminals")
        await shot("05-ws2")
        pane("runners")
        await shot("06-ws3")
        shell.setSeam(0, leftFraction: 0.5)
        await shot("12-seam")
        shell.closePane("runners")
        pane("runners")
        pane("core")
        pane("citadel")
        await shot("07-wsstrip")
        shell.toggleFocusMode()
        await shot("08-focus")
        shell.toggleFocusMode()
        shell.closeAllPanes()
        shell.show(.home)
        shell.open(.settings)
        await shot("09-settings")
        shell.open(.shortcuts)
        await shot("10-shortcuts")
        shell.overlay = nil
        shell.editingWidgets = true
        await shot("11-home-edit")
        NSApp.terminate(nil)
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
