#if DEBUG
import AppKit
import Accounts
import Pairing

/// Debug only. `CORE_ACC_SNAPSHOT=<dir> [CORE_THEME=light|dark] [CORE_ACC_SCENES=a,b]` walks every Accounts state on the
/// stand-in data (`AccountsDemo`) by changing the app's own state, captures its window and quits. No key events, no Core.
@MainActor
enum AccountsSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = NSApp.windows.first(where: { $0.title == "Ainkrad Core" }) else {
            return log("no main window")
        }
        let demo = app.debugAccountsDemo()
        let only = env["CORE_ACC_SCENES"].flatMap { $0.isEmpty ? nil : $0 }?.split(separator: ",").map(String.init)
        for (i, scene) in AccountsDemo.scenes.enumerated() where only?.contains(scene) ?? true {
            await demo.show(scene)
            try? await Task.sleep(for: .seconds(1.6))
            let file = "\(dir)/\(String(format: "%02d", i + 1))-\(scene)-\(theme)-app.png"
            log("shot \(scene) \(capture(window, to: file) ? "ok" : "FAILED")")
        }
        NSApp.terminate(nil)
    }

    private static func capture(_ window: NSWindow, to path: String) -> Bool {
        guard
            let image = CGWindowListCreateImage(
                .null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                [.boundsIgnoreFraming, .nominalResolution])
        else { return false }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("SNAP \(s)\n".utf8)) }
}
#endif
