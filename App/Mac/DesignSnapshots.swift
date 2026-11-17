#if DEBUG
import AppKit
import Design
import Pairing

/// Debug only. `CORE_DESIGN_SNAPSHOT=<dir> [CORE_THEME=light|dark] [CORE_REDUCE_MOTION=1] [CORE_DESIGN_SCENES=a,b]` walks
/// every Design state on the stand-in data (`DesignDemo`) by changing the app's own state, captures its window and quits.
/// No key events, no Core. `CORE_REDUCE_MOTION=1` only names the files `-reduce`: the runner turns the system's Reduce Motion
/// on, and the design system's components follow it.
@MainActor
enum DesignSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        let reduce = env["CORE_REDUCE_MOTION"] == "1"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = await SnapshotCapture.mainWindow() else {
            return log("no main window")
        }
        let demo = app.debugDesignDemo()
        let only = env["CORE_DESIGN_SCENES"].flatMap { $0.isEmpty ? nil : $0 }?.split(separator: ",").map(String.init)
        for (i, scene) in DesignDemo.scenes.enumerated() where only?.contains(scene) ?? true {
            await demo.show(scene)
            try? await Task.sleep(for: .seconds(1.6))
            let file =
                "\(dir)/\(String(format: "%02d", i + 1))-\(scene)-\(theme)\(reduce ? "-reduce" : "")-design.png"
            log("shot \(scene) \(SnapshotCapture.png(window, to: file) ? "ok" : "FAILED")")
        }
        NSApp.terminate(nil)
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("SNAP \(s)\n".utf8)) }
}
#endif
