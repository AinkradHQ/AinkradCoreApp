#if DEBUG
import AppKit
import Pairing
import Shell

/// Debug only. `CORE_UPDATES_SNAPSHOT=<dir> [CORE_THEME=light|dark] [CORE_REDUCE_MOTION=1]` (with `CORE_DEMO=1`) opens
/// Settings, Updates on made-up data and walks the mockup's states (`Designs/core/0-10/review/updates`): up to date, an
/// update ready, updating (install, the restart gap, reconnected, health), the runners following, done, went back, one
/// runner updating, and this app downloading and ready. Captures the window per state and quits. No Core is reached.
/// `CORE_REDUCE_MOTION=1` draws the page's Reduce Motion fallback without touching the Mac's setting.
@MainActor
enum UpdatesSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        let reduce = env["CORE_REDUCE_MOTION"] == "1"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = await SnapshotCapture.mainWindow() else { return log("no main window") }
        let shell = app.shell
        app.debugShowDesktop()
        app.debugPairedSetup(false)
        let u = shell.updates
        u.debugReduceMotion = reduce
        u.macRunnerID = "mac"
        u.appVersion = "0.10.1"
        u.checkApp = {}
        u.installApp = {}
        shell.coreUpdateNews = {}
        shell.home.health = CoreHealthFacts(version: "0.10.2", uptimeSecs: 86_400 * 3)
        shell.corePage.debugSet(prefs: CorePagePrefs(autoUpdate: true, updateHour: 3))
        shell.open(.settings)
        shell.settings.selected = "updates"

        let old = "0.10.2"
        let new = "0.10.3"
        func runners(_ v: String, buildBox: String? = nil, behind: Bool = false) -> [UpdatableRunner] {
            [
                UpdatableRunner(id: "host", name: "Core host", version: v, behind: behind, builtIn: true),
                UpdatableRunner(id: "bb", name: "build-box", version: buildBox ?? v, behind: behind),
                UpdatableRunner(id: "lab", name: "lab-pi", version: v, behind: behind),
                UpdatableRunner(id: "mac", name: "Studio laptop", version: "0.10.1"),
            ]
        }
        func status(_ phase: CoreUpdateStatus.Phase, current: String = old, error: String? = nil) -> CoreUpdateStatus {
            var s = CoreUpdateStatus()
            s.current = current
            s.phase = phase
            s.available = phase == .done || current == new ? nil : new
            s.to = phase == .idle ? nil : new
            s.error = error
            return s
        }
        let checked = CoreUpdateCheck(at: Date().addingTimeInterval(-120), status: .upToDate, current: new)
        let ready = CoreUpdateCheck(
            at: Date().addingTimeInterval(-120), status: .available, current: old, latest: new, latestRunner: new)
        /// A run `secs` into its current step, with the steps before it done in their usual times.
        func run(_ step: CoreRun.Step, secs: Double, gap: Double? = nil, back: Bool = false) -> CoreRun {
            let now = Date()
            var r = CoreRun(from: old, to: new, at: now.addingTimeInterval(-60))
            for s in CoreRun.Step.allCases where s.rawValue < step.rawValue { r.took[s] = s.expected }
            r.step = step
            r.stepAt = now.addingTimeInterval(-secs)
            r.gapSince = gap.map { now.addingTimeInterval(-$0) }
            r.backAt = back ? now.addingTimeInterval(-0.5) : nil
            return r
        }

        let scenes: [(String, () -> Void)] = [
            ("1-up-to-date", { u.debugSet(check: checked, runners: runners(new), core: status(.idle, current: new)) }),
            ("2-core-update-ready", { u.debugSet(check: ready, runners: runners(old), core: status(.idle)) }),
            (
                "3a-updating-install",
                { u.debugSet(check: ready, runners: runners(old), core: status(.install), run: run(.install, secs: 3)) }
            ),
            (
                "3b-updating-restart-gap",
                {
                    u.debugSet(
                        check: ready, runners: runners(old), core: status(.install),
                        run: run(.restart, secs: 2.5, gap: 2.5))
                }
            ),
            (
                "3c-updating-reconnected",
                {
                    u.debugSet(
                        check: ready, runners: runners(old), core: status(.install, current: new),
                        run: run(.restart, secs: 5, back: true))
                }
            ),
            (
                "3d-updating-health",
                {
                    u.debugSet(
                        check: ready, runners: runners(old), core: status(.health, current: new),
                        run: run(.health, secs: 2))
                }
            ),
            (
                "3e-runners-follow",
                {
                    var rs = runners(old, behind: true)
                    rs[0].version = new
                    rs[0].behind = false
                    u.debugSet(
                        check: ready, runners: rs, core: status(.done, current: new), queue: ["bb", "lab"],
                        updating: ["bb": Date().addingTimeInterval(-9)], chaining: true)
                }
            ),
            (
                "4-done",
                {
                    u.debugSet(
                        check: checked, runners: runners(new), core: status(.done, current: new),
                        finished: UpdatesFinished(version: new, runners: 3, seconds: 31))
                }
            ),
            (
                "5-rolled-back",
                {
                    u.debugSet(
                        check: ready, runners: runners(old), core: status(.rolledBack, error: "health_failed"),
                        retryAt: Date().addingTimeInterval(248))
                }
            ),
            (
                "6-runner-updating",
                {
                    var rs = runners(new, buildBox: old)
                    rs[1].behind = true
                    u.debugSet(
                        check: checked, runners: rs, core: status(.idle, current: new),
                        updating: ["bb": Date().addingTimeInterval(-12)])
                }
            ),
            (
                "7a-mac-downloading",
                {
                    u.appDownloading = "0.10.2"
                    u.debugSet(check: checked, runners: runners(new), core: status(.idle, current: new))
                }
            ),
            (
                "7b-mac-ready",
                {
                    u.appDownloading = nil
                    u.appReady = "0.10.2"
                    u.debugSet(check: checked, runners: runners(new), core: status(.idle, current: new))
                }
            ),
        ]
        let only = env["CORE_UPDATES_SCENES"].flatMap { $0.isEmpty ? nil : $0 }?.split(separator: ",").map(String.init)
        for (name, set) in scenes where only?.contains { name.hasPrefix($0) } ?? true {
            set()
            try? await Task.sleep(for: .seconds(1.8))
            let file = "\(dir)/\(name)-\(theme)\(reduce ? "-reduce" : "")-app.png"
            log("shot \(name) \(SnapshotCapture.png(window, to: file) ? "ok" : "FAILED")")
        }
        shell.overlay = nil
        NSApp.terminate(nil)
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("SNAP \(s)\n".utf8)) }
}
#endif
