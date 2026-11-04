#if DEBUG
import AppKit
import Pairing
import Shell

/// Debug only. `CORE_HOME_SNAPSHOT=<dir> [CORE_THEME=light|dark]` (with `CORE_DEMO=1`) walks first-run setup, Home (normal, edit
/// mode, gallery, quick action hover) and the bell by changing the app's own state, captures its window and quits. No key events.
@MainActor
enum HomeSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = NSApp.windows.first(where: { $0.title == "Ainkrad Core" }) else {
            return log("no main window")
        }
        let shell = app.shell
        func shot(_ name: String, wait: Double = 1.8) async {
            try? await Task.sleep(for: .seconds(wait))
            let file = "\(dir)/\(name)-\(theme)-app.png"
            log("shot \(name) \(capture(window, to: file) ? "ok" : "FAILED")")
        }
        for (i, scene) in ["empty", "address", "bootstrap", "typed", "sas", "approved"].enumerated() {
            app.debugFirstRun(scene)
            await shot("setup-\(i + 1)-\(scene)")
        }
        app.debugShowDesktop()
        await shot("home", wait: 2.5)
        shell.debugForceQuickHover = true
        await shot("quick-hover")
        shell.debugForceQuickHover = false
        shell.editingWidgets = true
        await shot("home-edit")
        shell.editingWidgets = false
        shell.addingWidget = true
        await shot("gallery")
        shell.addingWidget = false
        shell.toggleBell()
        await shot("bell")
        shell.bellOpen = false
        NSApp.terminate(nil)
    }

    private static func capture(_ window: NSWindow, to path: String) -> Bool {
        guard
            let image = CGWindowListCreateImage(
                .null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                [.boundsIgnoreFraming, .nominalResolution])
        else { return false }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("SNAP \(s)\n".utf8)) }
}
#endif
