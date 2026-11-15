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
        // CORE_COMPOSER_KEEP_HOST=1 keeps Touch ID in the way of a send, as in a person's own demo run.
        let keepHost = ProcessInfo.processInfo.environment["CORE_COMPOSER_KEEP_HOST"] == "1"
        if !keepHost { a.debugDropHost() }
        note("touch id gate: \(keepHost ? "on" : "off")")
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
        // A message with a file: the words, then the file as @path.
        let file = URL(fileURLWithPath: NSTemporaryDirectory() + "self-test.png")
        a.attachments[s.id] = [file]
        a.drafts[s.id] = "see this"
        try? await Task.sleep(for: .milliseconds(300))
        await key("\r", 36)
        try? await Task.sleep(for: .seconds(1.5))
        check(
            "a file goes with the message", draft().isEmpty && (a.attachments[s.id] ?? []).isEmpty,
            "draft = \(draft().debugDescription), attachments left = \((a.attachments[s.id] ?? []).count)")
        note("notice after sending: \(a.notices[s.id].map { "\($0.title) \($0.detail ?? "")" } ?? "none")")

        // ⌘V through the app's menu, as a person pastes. The clipboard is put back afterwards.
        let pb = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { t in item.data(forType: t).map { (t, $0) } })
        }
        defer {
            pb.clearContents()
            pb.writeObjects(
                saved.map { d in
                    let item = NSPasteboardItem()
                    for (t, v) in d { item.setData(v, forType: t) }
                    return item
                })
        }
        func commandV() async {
            if let e = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)
            {
                let byMenu = NSApp.mainMenu?.performKeyEquivalent(with: e) ?? false
                if !byMenu { window.sendEvent(e) }
                note("⌘V handled by the menu = \(byMenu)")
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        a.attachments[s.id] = nil
        let doc = URL(fileURLWithPath: NSTemporaryDirectory() + "self-test.txt")
        try? "x".write(to: doc, atomically: true, encoding: .utf8)
        pb.clearContents()
        pb.writeObjects([doc as NSURL])
        await commandV()
        check(
            "pasting a file attaches it", (a.attachments[s.id] ?? []) == [doc],
            "attachments = \(a.attachments[s.id] ?? [])")
        a.attachments[s.id] = nil
        pb.clearContents()
        pb.writeObjects([
            NSImage(size: NSSize(width: 4, height: 4), flipped: false) { r in
                NSColor.red.setFill()
                r.fill()
                return true
            }
        ])
        await commandV()
        check(
            "pasting an image attaches it", (a.attachments[s.id] ?? []).count == 1,
            "attachments = \(a.attachments[s.id] ?? [])")
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
