#if DEBUG
import AppKit
import Pairing
import Shell

/// Debug only. `CORE_UPDATES_SNAPSHOT=<dir> [CORE_THEME=light|dark]` (with `CORE_DEMO=1`) opens Settings, Updates on made-up
/// data, one scene per state (up to date, available, installing, rolled back, no feed, an older Core, the app ready to install),
/// captures the window and quits. No Core is reached, no key events.
@MainActor
enum UpdatesSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = await SnapshotCapture.mainWindow() else { return log("no main window") }
        let shell = app.shell
        app.debugShowDesktop()
        app.debugPairedSetup(false)
        let u = shell.updates
        u.appVersion = "0.10.2"
        u.checkApp = {}
        shell.startCoreUpdate = {}
        shell.coreUpdateNews = {}
        shell.home.health = CoreHealthFacts(version: "0.10.2", uptimeSecs: 86_400 * 3)
        shell.corePage.debugSet(prefs: CorePagePrefs(autoUpdate: true, updateHour: 3))
        let runners = [
            UpdatableRunner(id: "r1", name: "Attic box", version: "0.10.1", behind: true),
            UpdatableRunner(id: "r2", name: "Studio tower", version: "0.10.2"),
            UpdatableRunner(id: "r3", name: "Garage pi", version: "0.10.0", online: false, behind: true),
            UpdatableRunner(id: "r4", name: "This Mac", version: "0.10.1", behind: true, builtIn: true),
        ]
        func status(_ phase: CoreUpdateStatus.Phase, available: String? = nil, error: String? = nil) -> CoreUpdateStatus
        {
            var s = CoreUpdateStatus()
            s.current = "0.10.2"
            s.phase = phase
            s.available = available
            s.to = phase == .idle ? nil : "0.10.3"
            s.progress = phase == .install ? 0.55 : phase == .done ? 1 : 0.2
            s.error = error
            return s
        }
        let at = Date().addingTimeInterval(-60)
        func check(_ st: CoreUpdateCheck.Status, latest: String? = nil, reason: String? = nil) -> CoreUpdateCheck {
            CoreUpdateCheck(at: at, status: st, current: "0.10.2", latest: latest, latestRunner: latest, reason: reason)
        }
        shell.open(.settings)
        shell.settings.selected = "updates"
        let scenes: [(String, CoreUpdateStatus, CoreUpdateCheck?, [UpdatableRunner], Set<String>)] = [
            (
                "up-to-date", status(.idle), check(.upToDate),
                runners.map { r in
                    var r = r
                    r.behind = false
                    return r
                }, []
            ),
            ("available", status(.idle, available: "0.10.3"), check(.available, latest: "0.10.3"), runners, []),
            ("installing", status(.install), check(.available, latest: "0.10.3"), runners, ["r1"]),
            (
                "rolled-back", status(.rolledBack, error: "health_failed"), check(.available, latest: "0.10.3"),
                runners, []
            ),
            (
                "feed-unavailable", status(.idle),
                check(.feedUnavailable, reason: "The release server did not answer."), runners, []
            ),
        ]
        for (name, s, c, rs, asked) in scenes {
            shell.coreUpdate = s
            u.debugSet(check: c, runners: rs, asked: asked)
            await shot(window, dir, "updates-\(name)", theme)
        }
        // An older Core: no update routes, no prefs; the app half still works and has a download ready.
        shell.coreUpdate = status(.idle)
        shell.corePage.debugSet(prefs: CorePagePrefs(), supported: false)
        u.source = nil
        u.appReady = "0.10.3"
        u.installApp = {}
        await shot(window, dir, "updates-older-core-app-ready", theme)
        shell.overlay = nil
        NSApp.terminate(nil)
    }

    private static func shot(_ window: NSWindow, _ dir: String, _ name: String, _ theme: String) async {
        try? await Task.sleep(for: .seconds(1.8))
        let file = "\(dir)/\(name)-\(theme)-app.png"
        log("shot \(name) \(SnapshotCapture.png(window, to: file) ? "ok" : "FAILED")")
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("SNAP \(s)\n".utf8)) }
}
#endif
