#if DEBUG
import AppKit
import Pairing
import Terminals

/// Debug only. `CORE_MACHINES_SNAPSHOT=<dir> [CORE_THEME=light|dark] [CORE_MACHINES_SCENES=a,b]` walks every Machines state
/// on made-up machines (`MachinesDemo`): the list, a machine's page, offline, a phone, a Mac that only signs in, Add machine,
/// the empty list and an unreachable Core. It captures its own window and quits. No key events, no Core.
@MainActor
enum MachinesSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = await SnapshotCapture.mainWindow() else { return log("no main window") }
        let demo = app.debugMachinesDemo()
        let only = env["CORE_MACHINES_SCENES"].flatMap { $0.isEmpty ? nil : $0 }?.split(separator: ",").map(String.init)
        for (i, scene) in MachinesDemo.scenes.enumerated() where only?.contains(scene) ?? true {
            await demo.show(scene)
            try? await Task.sleep(for: .seconds(1.8))
            let file = "\(dir)/\(String(format: "%02d", i + 1))-\(scene)-\(theme).png"
            log("shot \(scene) \(SnapshotCapture.png(window, to: file) ? "ok" : "FAILED")")
        }
        NSApp.terminate(nil)
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("SNAP \(s)\n".utf8)) }
}
#endif
