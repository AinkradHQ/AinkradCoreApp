#if DEBUG
import AppKit
import Agents
import Pairing
import Shell
import SwiftUI

/// Debug only. `CORE_AGENTS_SNAPSHOT=<dir>` (with `CORE_DEMO=1`, the prototype's agents world) walks every agents screen and state
/// by setting the app's own state, and captures its own window. No key events, nothing leaves the app.
@MainActor
enum AgentsSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = NSApp.windows.first(where: { $0.title == "Ainkrad" }) else {
            return log("no main window")
        }
        let shell = app.shell
        let a = app.agents
        a.debugDropHost()
        for item in shell.bell.items where !item.id.hasPrefix("agents.") { shell.bell.remove(item.id) }
        for _ in 0..<100 where a.sessions.items.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        func id(_ n: Int) -> String { String(format: "as_01JC4X7Q3MZ8N5V2K9R%03d", n) }
        var n = 0
        func shot(_ name: String, wait: Double = 1.2) async {
            try? await Task.sleep(for: .seconds(wait))
            n += 1
            let file = "\(dir)/\(String(format: "%02d", n))-\(name)-\(theme)-app.png"
            log("shot \(n) \(name) \(capture(window, to: file) ? "ok" : "FAILED")")
        }
        func only(_ open: () -> Void) {
            shell.closeAllPanes()
            shell.overlay = nil
            shell.bellOpen = false
            shell.closeDialog()
            open()
        }
        func list(_ mode: String, _ name: String) async {
            a.debugList(mode)
            only { a.openList() }
            await shot(name)
            a.debugList("normal")
        }
        a.debugPermission("allowed")
        log("key=\(window.isKeyWindow) fr=\(String(describing: window.firstResponder))")

        // The list, in each state the prototype shows.
        only { a.openList() }
        await shot("list-normal")
        a.filter = .needsYou
        await shot("list-needs-you")
        a.filter = .active
        await shot("list-active")
        a.filter = .ended
        await shot("list-ended")
        a.filter = .all
        await list("loading", "list-loading")
        await list("empty", "list-empty")
        await list("failed", "list-error")
        a.debugLink("reconnecting")
        await shot("list-reconnecting")
        a.debugLink("live")
        a.debugPermission("notAsked")
        await shot("list-notification-ask")
        a.debugPermission("allowed")

        // Sessions: one pane for every state.
        for (n, name) in [
            (1, "waiting"), (4, "starting"), (5, "interrupted"), (11, "lost"), (6, "ended-succeeded"),
            (9, "ended-failed"),
            (10, "ended-cancelled"), (8, "ended-token-cap"), (7, "ended-stalled"),
        ] {
            only { a.openSession(id(n)) }
            await shot("session-\(name)")
        }
        // Both panes side by side, as the workspace shows them.
        only {
            a.openList()
            a.openSession(id(1))
        }
        await shot("workspace-list-and-session")
        a.debugLink("reconnecting")
        only { a.openSession(id(1)) }
        await shot("session-reconnecting")
        a.debugLink("live")

        // Approval card states in a session.
        only { a.openSession(id(1)) }
        if let r = a.debugFirstPending(session: id(1)) {
            a.debugNotice(
                r.id, title: "Cancelled, nothing was done.", detail: "Try again when you are ready.",
                symbol: "hand.raised", tone: "queue")
            await shot("approval-touchid-cancelled")
            a.debugNotice(
                r.id, title: "Touch ID didn't match. Nothing was done.",
                detail: "The Secure Enclave could not sign the request. Try again.", symbol: "exclamationmark.triangle")
            await shot("approval-touchid-failed")
            a.debugNotice(
                r.id, title: "Approving did not go through.", detail: "no such request waits",
                symbol: "exclamationmark.triangle")
            await shot("approval-refused")
            a.debugNotice(r.id, title: "", detail: "", symbol: "")
        }
        a.debugSessionNotice(id(1), title: "Sending did not go through.", detail: "Touch ID did not match.")
        await shot("session-send-failed")
        a.debugSessionNotice(id(1), title: "", detail: "")
        // Decide: one approved, one denied, one expired.
        if let r = a.debugFirstPending(session: id(1)) { await a.decide(r, approved: true) }
        await shot("approval-approved")
        if let r = a.debugFirstPending(session: id(3)) { await a.decide(r, approved: false) }
        only { a.openSession(id(3)) }
        await shot("approval-denied")
        await a.debugExpired(session: id(4))
        only { a.openSession(id(4)) }
        await shot("approval-expired")

        // The inbox, the bell, a new approval arriving.
        a.openInbox()
        await shot("inbox")
        shell.closeDialog()
        a.debugList("normal")
        await a.debugArrive(session: id(4))
        shell.bellOpen = true
        await shot("bell-approvals")
        shell.bellOpen = false

        // New session.
        a.openNewSession()
        await shot("new-session")
        shell.closeDialog()
        shell.toggleLauncher()
        await shot("launcher")
        shell.launcherOpen = false

        // Settings, Notifications.
        for (p, name) in [("notAsked", "not-asked"), ("denied", "denied"), ("allowed", "allowed")] {
            a.debugPermission(p)
            shell.settings.selected = "notifications"
            shell.open(.settings)
            await shot("settings-notifications-\(name)")
            shell.overlay = nil
        }
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
