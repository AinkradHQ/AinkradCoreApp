#if DEBUG
import AppKit
import Agents
import Pairing
import SwiftUI

/// Debug only. `CORE_COMPOSER_TEST=<log file>` (with `CORE_DEMO=1`): opens a live AI session and drives its message field with
/// real key events sent through the window (the same path as typing: window → first responder → the field), then writes
/// what happened at each step and quits. No global input, so it never takes over the person's keyboard or pointer.
@MainActor
enum ComposerSelfTest {
    static func run(_ app: AppModel, log path: String) async {
        var lines: [String] = []
        func note(_ s: String) { lines.append(s) }
        defer {
            try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
        try? await Task.sleep(for: .seconds(3))
        guard let window = await SnapshotCapture.mainWindow() else { return note("FAIL no main window") }
        let a = app.agents
        a.debugDropHost()  // no Touch ID in a test run
        for _ in 0..<100 where a.sessions.items.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        guard let s = a.sessions.items.first(where: { a.canWrite($0) }) else { return note("FAIL no writable session") }
        app.shell.closeAllPanes()
        a.openSession(s.id)
        try? await Task.sleep(for: .seconds(2))
        guard let tv = find(window.contentView) else { return note("FAIL no message field in the window") }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(tv)
        try? await Task.sleep(for: .milliseconds(300))
        note("focus: field is first responder = \(window.firstResponder === tv)")

        func draft() -> String { a.drafts[s.id] ?? "" }
        func key(_ chars: String, _ code: UInt16, _ mods: NSEvent.ModifierFlags = []) async {
            if let e = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: chars,
                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)
            {
                window.sendEvent(e)
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        func typeText(_ text: String) async { for c in text { await key(String(c), 0) } }
        func check(_ name: String, _ ok: Bool, _ detail: String) { note("\(ok ? "PASS" : "FAIL") \(name): \(detail)") }

        a.drafts[s.id] = ""
        await typeText("hi")
        check("typing", draft() == "hi", "draft = \(draft().debugDescription)")
        await key("\r", 36, .shift)
        check("shift-return makes a new line", draft() == "hi\n", "draft = \(draft().debugDescription)")
        a.drafts[s.id] = ""
        try? await Task.sleep(for: .milliseconds(200))
        await typeText("/co")
        check("slash opens commands", draft() == "/co", "draft = \(draft().debugDescription)")
        await key("\u{F701}", 125)  // ↓
        await key("\t", 48)  // Tab takes the highlighted command
        check("arrow + tab picks a command", draft() == "/context ", "draft = \(draft().debugDescription)")
        a.drafts[s.id] = "/co"
        try? await Task.sleep(for: .milliseconds(200))
        await key("\r", 36)  // Return fills the first command
        check("return fills the command", draft() == "/compact ", "draft = \(draft().debugDescription)")
        a.drafts[s.id] = "hello from the test"
        try? await Task.sleep(for: .milliseconds(200))
        let before = a.transcripts[s.id]?.entries.count ?? -1
        await key("\r", 36)
        try? await Task.sleep(for: .seconds(1.5))
        let after = a.transcripts[s.id]?.entries.count ?? -1
        check(
            "return sends", draft().isEmpty, "draft after = \(draft().debugDescription), entries \(before) → \(after)")
        await key("\u{1B}", 53)
        note("escape: first responder after = \(type(of: window.firstResponder as Any))")
    }

    private static func find(_ v: NSView?) -> NSTextView? {
        guard let v else { return nil }
        if let t = v as? NSTextView, t.accessibilityIdentifier() == "agent-composer" { return t }
        for sub in v.subviews { if let t = find(sub) { return t } }
        return nil
    }
}
#endif
