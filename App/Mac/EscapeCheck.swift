#if DEBUG
import AppKit
import Pairing
import Shell
import SwiftUI

/// Debug only. `CORE_ESC_CHECK=<dir>` drives Esc and typing through `NSApp.sendEvent` (the app's own event path: local
/// monitors, key equivalents and `onKeyPress` all see it; nothing reaches other apps), logs the shell state after each key
/// and saves a few pictures. Needs `CORE_DEMO=1`.
@MainActor
enum EscapeCheck {
    static func run(_ app: AppModel, dir: String) async {
        try? await Task.sleep(for: .seconds(4))
        guard let window = NSApp.windows.first(where: { $0.title == "Ainkrad" }) else { return log("no main window") }
        let shell = app.shell
        func settle(_ s: Double = 0.5) async { try? await Task.sleep(for: .seconds(s)) }
        func state(_ label: String) {
            log(
                "\(label): launcher=\(shell.launcherOpen) sheet=\(shell.sheet != nil) dialog=\(shell.dialog?.id ?? "-") top=\(shell.topDialog?.id ?? "-") overlay=\(shell.overlay.map { "\($0)" } ?? "-") bell=\(shell.bellOpen)"
            )
        }
        func key(_ code: UInt16, _ chars: String) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard
                    let e = NSEvent.keyEvent(
                        with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, characters: chars,
                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)
                else { continue }
                NSApp.sendEvent(e)
            }
        }
        func esc() { key(53, "\u{1b}") }
        func shot(_ name: String) async {
            await settle(0.8)
            log("shot \(name) \(capture(window, to: "\(dir)/\(name).png") ? "ok" : "FAILED")")
        }

        // A. launcher: opens, takes typing at once (50 ms, under the old 80 ms wait), Esc closes.
        shell.toggleLauncher()
        await settle(0.05)
        for (c, ch) in [(2, "d"), (14, "e"), (9, "v")] { key(UInt16(c), ch) }
        await shot("launcher-typed-at-once")
        state("A launcher open")
        esc()
        await settle()
        state("A after esc")

        // B. a sheet over the launcher: Esc closes the sheet, the next Esc the launcher.
        shell.toggleLauncher()
        await settle()
        shell.presentSheet(title: "End this session?", message: "It stops now.", actions: [ShellSheetAction("Cancel")])
        await settle()
        state("B sheet over launcher")
        esc()
        await settle()
        state("B after esc 1 (sheet gone, launcher stays)")
        esc()
        await settle()
        state("B after esc 2 (launcher gone)")

        // C. a dialog that cannot be dismissed ignores Esc; a dismissible dialog over Settings closes first.
        shell.presentOnTop(ShellDialog(id: "step-up", dismissible: false) { Text("Touch ID") })
        await settle()
        esc()
        await settle()
        state("C step-up after esc (stays)")
        shell.closeTopDialog()
        shell.open(.settings)
        await settle()
        shell.present(ShellDialog(id: "demo-dialog") { Text("A dialog").padding(40) })
        await settle()
        esc()
        await settle()
        state("D dialog over settings, esc 1 (dialog gone)")
        esc()
        await settle()
        state("D esc 2 (settings gone)")

        // E. a pane's own back (Accounts detail) runs when nothing is above it, and not before.
        await app.debugAccountsDemo().show("account-ready")
        await shot("pane-detail-before")
        esc()
        await settle(1.2)
        await shot("pane-detail-after-plain-esc-closed")
        await app.debugAccountsDemo().show("account-ready")
        await settle(1.0)
        shell.toggleLauncher()
        await settle()
        esc()
        await shot("pane-detail-launcher-esc-1-detail-stays")
        esc()
        await settle(1.2)
        await shot("pane-detail-launcher-esc-2-closed")
        state("E done")
        log(
            "E after launcher esc 2: accountDetailOpen=\(app.debugAccountsDetailOpen) (must be false: the pane took focus back)"
        )

        // F. the same through a dialog and Settings: the pane answers Esc once they are gone.
        await app.debugAccountsDemo().show("account-ready")
        await settle(1.0)
        shell.open(.settings)
        await settle()
        esc()  // Settings closes
        await settle()
        esc()  // the pane's own back
        await settle(1.2)
        log("F after settings esc 1 and pane esc: accountDetailOpen=\(app.debugAccountsDetailOpen) (must be false)")
        NSApp.terminate(nil)
    }

    private static func capture(_ window: NSWindow, to path: String) -> Bool {
        guard
            let image = CGWindowListCreateImage(
                .null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                [.boundsIgnoreFraming, .nominalResolution]),
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func log(_ s: String) { FileHandle.standardError.write(Data("ESC \(s)\n".utf8)) }
}
#endif
