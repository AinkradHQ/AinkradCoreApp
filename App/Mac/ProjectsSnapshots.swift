#if DEBUG
import AppKit
import Pairing
import Projects

/// Debug only. `CORE_PROJECTS_SNAPSHOT=<dir> [CORE_THEME=light|dark] [CORE_REDUCE_MOTION=1] [CORE_PROJECTS_SCENES=a,b]` walks
/// every Projects state on the stand-in data (`ProjectsDemo`) by changing the app's own state, captures its window and quits.
/// No key events, no Core. `CORE_REDUCE_MOTION=1` makes the screens behave as if Reduce Motion were on (the system setting
/// cannot be set from inside the app).
@MainActor
enum ProjectsSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        let reduce = env["CORE_REDUCE_MOTION"] == "1"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        ProjectsDemo.forceReduceMotion(reduce)
        try? await Task.sleep(for: .seconds(3))
        guard let window = await SnapshotCapture.mainWindow() else {
            return log("no main window")
        }
        let demo = app.debugProjectsDemo()
        let only = env["CORE_PROJECTS_SCENES"].flatMap { $0.isEmpty ? nil : $0 }?.split(separator: ",").map(String.init)
        for (i, scene) in ProjectsDemo.scenes.enumerated() where only?.contains(scene) ?? true {
            await demo.show(scene)
            try? await Task.sleep(for: .seconds(1.6))
            let file =
                "\(dir)/\(String(format: "%02d", i + 1))-\(scene)-\(theme)\(reduce ? "-reduce" : "")-projects.png"
            log("shot \(scene) \(SnapshotCapture.png(window, to: file) ? "ok" : "FAILED")")
        }
        NSApp.terminate(nil)
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("SNAP \(s)\n".utf8)) }
}
#endif
