#if DEBUG
import AppKit
import Lore
import Pairing

/// Debug only, part of the Lore walk (`CORE_LORE_SCENES=menu`): the header's More menu, Rename in place with real
/// keys, Delete and its Undo, ⌘⌫ in the list, and the header beside Leyline's for the same kit.
@MainActor
enum LoreMenuWalk {
    static func run(_ app: AppModel, _ demo: LoreDemo, _ window: NSWindow, tag: String) async {
        let dir = ProcessInfo.processInfo.environment["CORE_LORE_SPACE_SNAPSHOT"] ?? "/tmp"
        func shot(_ name: String) async {
            try? await Task.sleep(for: .seconds(1.2))
            let ok = SnapshotCapture.png(window, to: "\(dir)/menu-\(name)-\(tag)-lore-space.png")
            log("shot \(name) \(ok ? "ok" : "FAILED")")
        }

        // The header, then Leyline's, for the side-by-side.
        await demo.show("project-note")
        await shot("header")

        // The list's right-click menu is native: SwiftUI opens it only from a real click (a sent event does not), so
        // the walk shows the same actions through the header's More, and checks them below.
        // The header's More: its glass menu (Rename…, Copy Link, Delete), opened with a click on the tile.
        await demo.show("project-note")
        try? await Task.sleep(for: .seconds(1))
        click(NSPoint(x: 621, y: window.frame.height - 76), window)
        await shot("more-menu")
        // A second click on the tile closes it (the menu's Esc listens to the app's events, not a sent one).
        click(NSPoint(x: 621, y: window.frame.height - 76), window)

        // Rename in place: the field has the name; ⌘A, a new name, Return.
        await demo.show("rename")
        await shot("rename")
        await LoreSpaceSnapshots.key("a", [.command], window)
        await LoreSpaceSnapshots.type("Launch plan", window)
        await shot("rename-typed")
        await LoreSpaceSnapshots.key("\r", [], window, code: 36)
        try? await Task.sleep(for: .seconds(1))
        log("CHECK rename title=\(demo.noteTitle) \(demo.noteTitle == "Launch plan" ? "ok" : "NOT RENAMED")")
        await shot("renamed")

        // Delete from the menu: the toast offers Undo; Undo brings it back and opens it.
        await demo.show("deleted")
        await shot("deleted")
        let gone = await demo.trashed("ln_demoprojecta")
        log("CHECK delete trashed=\(gone) toast=\(demo.toastText) open=\(demo.noteTitle)")
        demo.undoToast()
        try? await Task.sleep(for: .seconds(1))
        let back = await demo.trashed("ln_demoprojecta")
        log("CHECK undo trashed=\(back) open=\(demo.noteTitle) \(back ? "NOT RESTORED" : "ok")")

        // ⌘⌫ in the list: ⌘L, ↑ puts the cursor on the last Recents row (Launch checklist).
        await demo.show("project-note")
        await LoreSpaceSnapshots.key("l", [.command], window)
        await LoreSpaceSnapshots.key("\u{F700}", [], window, code: 126)
        await shot("cmd-delete-cursor")
        // SwiftUI's `.delete` key equivalent is U+0008; a sent U+007F event is not matched to it.
        await LoreSpaceSnapshots.key("\u{8}", [.command], window, code: 51)
        try? await Task.sleep(for: .seconds(1))
        let keyed = await demo.trashed("ln_demoprojecta")
        log("CHECK cmd-delete trashed=\(keyed) \(keyed ? "ok" : "NOT DELETED") toast=\(demo.toastText)")
        await shot("cmd-delete")

        await app.debugLeylineDemo().show("list")
        await shot("leyline-header")
    }

    private static func click(_ p: NSPoint, _ window: NSWindow) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard
                let e = NSEvent.mouseEvent(
                    with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            else { continue }
            NSApp.sendEvent(e)
        }
    }

    private static func log(_ s: String) { SnapshotCapture.log(s) }
}
#endif
