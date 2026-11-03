#if DEBUG
import AppKit
import Pairing
import Terminals

/// Debug only. `CORE_TERM_SNAPSHOT=<dir> [CORE_THEME=light|dark] [CORE_TERM_SCENES=a,b]` walks every terminal state on the
/// stand-in data (`TerminalsDemo`) by changing the app's own state, captures its window and quits. No key events, no Core.
@MainActor
enum TerminalSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = NSApp.windows.first(where: { $0.title == "Ainkrad Core" }) else {
            return log("no main window")
        }
        let demo = TerminalsDemo(shell: app.shell)
        let only = env["CORE_TERM_SCENES"].flatMap { $0.isEmpty ? nil : $0 }?.split(separator: ",").map(String.init)
        for (i, scene) in TerminalsDemo.scenes.enumerated() where only?.contains(scene) ?? true {
            await demo.show(scene)
            try? await Task.sleep(for: .seconds(1.8))
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
