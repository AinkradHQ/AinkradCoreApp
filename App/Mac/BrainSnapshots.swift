#if DEBUG
import AppKit
import Brain
import Pairing

/// Debug only. `CORE_BRAIN_SNAPSHOT=<dir> [CORE_THEME=light|dark] [CORE_BRAIN_SCENES=a,b]` walks every Brain state on the
/// sample data (`BrainDemo`) by changing the app's own state, captures its window and quits. No key events, no Core.
@MainActor
enum BrainSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = await SnapshotCapture.mainWindow() else {
            return log("no main window")
        }
        let demo = app.debugBrainDemo()
        let only = env["CORE_BRAIN_SCENES"].flatMap { $0.isEmpty ? nil : $0 }?.split(separator: ",").map(String.init)
        for (i, scene) in BrainDemo.scenes.enumerated() where only?.contains(scene) ?? true {
            await demo.show(scene)
            try? await Task.sleep(for: .seconds(1.6))
            let file = "\(dir)/\(String(format: "%02d", i + 1))-\(scene)-\(theme)-brain.png"
            log("shot \(scene) \(capture(window, to: file) ? "ok" : "FAILED")")
        }
        NSApp.terminate(nil)
    }

    private static func capture(_ window: NSWindow, to path: String) -> Bool {
        SnapshotCapture.png(window, to: path)
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("SNAP \(s)\n".utf8)) }
}
#endif
