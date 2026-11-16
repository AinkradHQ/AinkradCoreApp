#if DEBUG
import AppKit
import QuartzCore
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
                // Another app in front: the menu has no key window to send Paste to, so hand it to the field directly.
                if NSApp.keyWindow !== window {
                    let sent = NSApp.sendAction(#selector(NSText.paste(_:)), to: window.firstResponder, from: nil)
                    note("window not key: Paste sent to the field = \(sent)")
                    try? await Task.sleep(for: .milliseconds(400))
                    return
                }
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
        // ⌘F from the message field: the find bar opens and takes the cursor (the field must let it go).
        a.attachments[s.id] = nil
        window.makeFirstResponder(tv)
        try? await Task.sleep(for: .milliseconds(200))
        if let e = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "f", charactersIgnoringModifiers: "f",
            isARepeat: false, keyCode: 3)
        {
            // As a key press arrives: the window's key equivalents first, then the menu. A window that is not key (another
            // app is in front) never gets the event from the app, so hand it to the window's key equivalents directly.
            if window.isKeyWindow {
                NSApp.sendEvent(e)
            } else {
                note("window not key: ⌘F sent to the window's key equivalents")
                _ = window.performKeyEquivalent(with: e)
            }
        }
        try? await Task.sleep(for: .milliseconds(800))
        func findField(_ v: NSView?) -> NSTextField? {
            guard let v else { return nil }
            if let f = v as? NSTextField, f.placeholderString == "Find in this conversation" { return f }
            for c in v.subviews { if let f = findField(c) { return f } }
            return nil
        }
        note("find bar shown = \(findField(window.contentView) != nil)")
        let fr = window.firstResponder
        let inFind =
            (fr as? NSTextView)?.isFieldEditor == true
            && ((fr as? NSTextView)?.delegate as? NSTextField)?.placeholderString == "Find in this conversation"
        check(
            "⌘F opens find with the cursor in it", inFind,
            "first responder = \(fr.map { String(describing: type(of: $0)) } ?? "none")")
        await key("\u{1B}", 53)
        try? await Task.sleep(for: .milliseconds(300))
        window.makeFirstResponder(tv)
        await key("\u{1B}", 53)
        note("escape: first responder after = \(type(of: window.firstResponder as Any))")
        // Session shortcuts typed in the message field reach the session (ComposerKeys.command): ⇧⌘K puts /compact in the
        // field; ⇧⌘C copies the agent's last words.
        func chord(_ c: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags) {
            window.makeFirstResponder(tv)
            guard
                let e = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: flags,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: code)
            else { return }
            _ = window.performKeyEquivalent(with: e)
        }
        a.drafts[s.id] = ""
        chord("k", 40, [.command, .shift])
        try? await Task.sleep(for: .milliseconds(300))
        check(
            "⇧⌘K from the field puts /compact in it", a.drafts[s.id] == "/compact ",
            "draft = \"\(a.drafts[s.id] ?? "")\"")
        a.drafts[s.id] = ""
        NSPasteboard.general.clearContents()
        chord("c", 8, [.command, .shift])
        try? await Task.sleep(for: .milliseconds(300))
        let last = (a.transcripts[s.id]?.entries ?? []).reversed().lazy.compactMap { e -> String? in
            if case .assistant(let t) = e.kind { t } else { nil }
        }.first
        let copied = NSPasteboard.general.string(forType: .string)
        check("⇧⌘C copies the last answer", last != nil && copied == last, "copied \(copied?.count ?? 0) characters")
        a.shell.toast = nil
        // A click on empty space in the conversation hands the cursor back to the message field. The click goes to this
        // process only.
        window.makeFirstResponder(nil)
        // Empty space between the reading column and the side panel (the sidebar fills the left edge).
        let local = NSPoint(x: window.frame.width * 0.75, y: window.frame.height / 2)
        let screen = window.convertPoint(toScreen: local)
        let top = (NSScreen.screens.first?.frame.height ?? 0) - screen.y
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(
                mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: screen.x, y: top),
                mouseButton: .left)?.postToPid(getpid())
            try? await Task.sleep(for: .milliseconds(80))
        }
        try? await Task.sleep(for: .milliseconds(500))
        note("clicks seen \(ComposerFocus.clicks), acted on \(ComposerFocus.handled)")
        check(
            "a click in the conversation puts the cursor back in the field", window.firstResponder === tv,
            "first responder = \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "none")")
        // The sidebar switches the pane to another session in place: no new tab.
        if let other = a.sessions.items.first(where: { $0.id != s.id }) {
            let before = app.shell.panes.count
            a.switchSession(from: s.id, to: other.id)
            try? await Task.sleep(for: .milliseconds(500))
            check(
                "the sidebar switches sessions in the same pane",
                app.shell.panes.count == before && app.shell.activePane == "agents.s-\(other.id)",
                "panes \(before) → \(app.shell.panes.count), active = \(app.shell.activePane ?? "none")")
        }
    }

    private static func find(_ v: NSView?) -> NSTextView? {
        guard let v else { return nil }
        if let t = v as? NSTextView, t.accessibilityIdentifier() == "agent-composer" { return t }
        for sub in v.subviews { if let t = find(sub) { return t } }
        return nil
    }
}
/// Debug only. `CORE_SCROLL_BENCH=<log> [CORE_BENCH_OFF=anims,panel,sidebar,anchor]`: opens the long demo session and
/// scrolls its transcript with wheel events for 4 s, down then up, while a 240 Hz timer measures how late the main thread
/// runs (a late tick is a frame the scroll could not draw). Appends one line to the log, then quits.
@MainActor
enum ScrollBenchRun {
    static func run(_ app: AppModel, log: String, env: [String: String]) async {
        ScrollBench.off = Set((env["CORE_BENCH_OFF"] ?? "").split(separator: ",").map(String.init))
        defer { NSApp.terminate(nil) }
        try? await Task.sleep(for: .seconds(3))
        guard let window = await SnapshotCapture.mainWindow() else { return }
        let a = app.agents
        for _ in 0..<100 where a.sessions.items.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        app.shell.closeAllPanes()
        a.openSession("as_01JC4X7Q3MZ8N5V2K9R020")
        try? await Task.sleep(for: .seconds(3))
        guard let scroll = ShowcaseShots.transcriptScrollView(window.contentView) else { return }
        for _ in 0..<60 { ShowcaseShots.wheelStep(scroll, dy: 4000) }  // to the top
        try? await Task.sleep(for: .seconds(1))
        var gaps: [Double] = []
        var last = CACurrentMediaTime()
        let start = last
        let timer = Timer(timeInterval: 1.0 / 240, repeats: true) { _ in
            MainActor.assumeIsolated {
                let now = CACurrentMediaTime()
                gaps.append(now - last)
                last = now
                let t = now - start
                // 2 s down, 2 s up, 30 pt per tick.
                ShowcaseShots.wheelStep(scroll, dy: t < 2 ? -30 : 30)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        try? await Task.sleep(for: .seconds(4))
        timer.invalidate()
        let ms = gaps.map { $0 * 1000 }.sorted()
        let p95 = ms.isEmpty ? 0 : ms[Int(Double(ms.count - 1) * 0.95)]
        let stalls = ms.filter { $0 > 25 }.count
        let line = String(
            format: "off=%@ ticks=%d stalls>25ms=%d p95=%.1fms max=%.1fms\n",
            (env["CORE_BENCH_OFF"] ?? "none"), ms.count, stalls, p95, ms.last ?? 0)
        if let h = FileHandle(forWritingAtPath: log) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(toFile: log, atomically: true, encoding: .utf8)
        }
    }
}

/// Debug only. `CORE_SHOWCASE_SHOTS=<dir> [CORE_THEME=light|dark]` (with `CORE_DEMO=1`): opens the demo session holding every kind
/// of content, captures its transcript a page at a time from the top, then a waiting session with its pinned approval.
@MainActor
enum ShowcaseShots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        // Every run starts with the sidebar and the panel shown (a toggle step must not leak into the next run).
        UserDefaults.standard.set(true, forKey: "agents.sessionSidebar")
        UserDefaults.standard.set(true, forKey: "agents.sessionPanel")
        defer { NSApp.terminate(nil) }
        try? await Task.sleep(for: .seconds(3))
        guard let window = await SnapshotCapture.mainWindow() else { return }
        let a = app.agents
        for _ in 0..<100 where a.sessions.items.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        app.shell.closeAllPanes()
        a.openSession("as_01JC4X7Q3MZ8N5V2K9R020")
        try? await Task.sleep(for: .seconds(2.5))
        // Scrolled with wheel events, as a person scrolls: SwiftUI ignores a clip view moved behind its back, and its lazy
        // column then draws nothing at the new offset.
        let scroll = transcriptScroll(window.contentView)
        let page = max((scroll?.contentView.bounds.height ?? 600) - 80, 200)
        for _ in 0..<40 { wheel(scroll, dy: 2000) }  // to the top
        try? await Task.sleep(for: .seconds(1))
        var n = 1
        var last = -1.0
        while n <= 8 {
            _ = SnapshotCapture.png(window, to: "\(dir)/showcase-\(n)-\(theme).png")
            // Two frames 0.6 s apart on the first page: the working sub-agent's highlight has moved between them.
            if n == 1 {
                try? await Task.sleep(for: .milliseconds(600))
                _ = SnapshotCapture.png(window, to: "\(dir)/showcase-1b-\(theme).png")
            }
            let y = scroll?.contentView.bounds.origin.y ?? 0
            if y == last { break }
            last = y
            wheel(scroll, dy: -page)
            try? await Task.sleep(for: .seconds(1))
            n += 1
        }
        app.shell.closeAllPanes()
        a.openSession("as_01JC4X7Q3MZ8N5V2K9R001")
        try? await Task.sleep(for: .seconds(2.5))
        _ = SnapshotCapture.png(window, to: "\(dir)/pinned-approval-\(theme).png")
        // ⌃⌘S and ⌥⌘I hide the sidebar and the panel; the toggles stay where the mockup has them. Then both come back.
        func chord(_ c: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags) {
            guard let tv = composer(window.contentView) else { return }
            window.makeFirstResponder(tv)
            if let e = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: c, charactersIgnoringModifiers: c, isARepeat: false, keyCode: code)
            {
                _ = window.performKeyEquivalent(with: e)
            }
        }
        chord("s", 1, [.command, .control])
        chord("i", 34, [.command, .option])
        // Mid-way: the sidebar and the panel are still sliding out (the toggles animate, with Reduce Motion too).
        try? await Task.sleep(for: .milliseconds(110))
        _ = SnapshotCapture.png(window, to: "\(dir)/sliding-\(theme).png")
        try? await Task.sleep(for: .seconds(1))
        _ = SnapshotCapture.png(window, to: "\(dir)/hidden-\(theme).png")
        chord("s", 1, [.command, .control])
        chord("i", 34, [.command, .option])
        try? await Task.sleep(for: .seconds(1))
        // A toast shows at the top of the window, never over the controls at the bottom.
        app.shell.showToast("Closed AI Sessions. It keeps running.")
        try? await Task.sleep(for: .seconds(1))
        _ = SnapshotCapture.png(window, to: "\(dir)/toast-\(theme).png")
        app.shell.toast = nil
        // Typing during a turn turns the composer's one button from Stop into Queue.
        a.drafts["as_01JC4X7Q3MZ8N5V2K9R001"] = "Also add a test for the 429 path."
        try? await Task.sleep(for: .seconds(1))
        _ = SnapshotCapture.png(window, to: "\(dir)/typed-\(theme).png")
        a.drafts["as_01JC4X7Q3MZ8N5V2K9R001"] = ""
        // Two messages typed during the turn wait above the field.
        for t in ["Also add a test for the 429 path.", "And mention the limit in the PR description."] {
            a.drafts["as_01JC4X7Q3MZ8N5V2K9R001"] = t
            a.enqueue("as_01JC4X7Q3MZ8N5V2K9R001")
        }
        try? await Task.sleep(for: .seconds(1))
        _ = SnapshotCapture.png(window, to: "\(dir)/queued-\(theme).png")
        a.queued["as_01JC4X7Q3MZ8N5V2K9R001"] = []
        // ⇧⌘R from the message field: the Review pane with its diffs (the status report session has files touched).
        app.shell.closeAllPanes()
        a.openSession("as_01JC4X7Q3MZ8N5V2K9R020")
        try? await Task.sleep(for: .seconds(2.5))
        if let tv = composer(window.contentView) {
            window.makeFirstResponder(tv)
            if let e = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15)
            {
                _ = window.performKeyEquivalent(with: e)
            }
            try? await Task.sleep(for: .seconds(1))
            _ = SnapshotCapture.png(window, to: "\(dir)/review-\(theme).png")
        }
        app.shell.closeAllPanes()
        a.openSession("as_01JC4X7Q3MZ8N5V2K9R001")
        try? await Task.sleep(for: .seconds(2))
        // ⌘ held: every button shows its key. The key goes to this process only, never to other apps.
        CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: true).map {
            $0.flags = .maskCommand
            $0.postToPid(getpid())
        }
        try? await Task.sleep(for: .seconds(1))
        _ = SnapshotCapture.png(window, to: "\(dir)/keys-\(theme).png")
        CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: false).map { $0.postToPid(getpid()) }
        try? await Task.sleep(for: .milliseconds(500))
        // The AI Sessions list on its own.
        app.shell.closeAllPanes()
        a.openList()
        try? await Task.sleep(for: .seconds(2))
        _ = SnapshotCapture.png(window, to: "\(dir)/list-\(theme).png")
        // Two sessions side by side: each pane is narrow, so the header shows its compact form.
        app.shell.closeAllPanes()
        a.openSession("as_01JC4X7Q3MZ8N5V2K9R020")
        a.openSession("as_01JC4X7Q3MZ8N5V2K9R001")
        try? await Task.sleep(for: .seconds(2.5))
        _ = SnapshotCapture.png(window, to: "\(dir)/split-\(theme).png")
        app.shell.closeAllPanes()
        a.openSession("as_01JC4X7Q3MZ8N5V2K9R001")
        try? await Task.sleep(for: .seconds(2))
        // ⌘/ from the message field: the list of the screen's keys.
        if let tv = composer(window.contentView) {
            window.makeFirstResponder(tv)
            if let e = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                characters: "/", charactersIgnoringModifiers: "/", isARepeat: false, keyCode: 44)
            {
                _ = window.performKeyEquivalent(with: e)
            }
            try? await Task.sleep(for: .seconds(1))
            _ = SnapshotCapture.png(window, to: "\(dir)/shortcuts-\(theme).png")
        }
    }

    private static func composer(_ v: NSView?) -> NSTextView? {
        guard let v else { return nil }
        if let t = v as? NSTextView, t.accessibilityIdentifier() == "agent-composer" { return t }
        for sub in v.subviews { if let t = composer(sub) { return t } }
        return nil
    }

    static func wheelStep(_ scroll: NSScrollView, dy: Double) { wheel(scroll, dy: dy) }
    static func transcriptScrollView(_ v: NSView?) -> NSScrollView? { transcriptScroll(v) }

    /// One scroll-wheel step of `dy` points (positive scrolls up), handed straight to the scroll view.
    private static func wheel(_ scroll: NSScrollView?, dy: Double) {
        guard let scroll,
            let cg = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(dy), wheel2: 0, wheel3: 0),
            let e = NSEvent(cgEvent: cg)
        else { return }
        scroll.scrollWheel(with: e)
    }

    /// The tallest scroll view in the window: the transcript.
    private static func transcriptScroll(_ v: NSView?) -> NSScrollView? {
        var best: NSScrollView?
        func walk(_ v: NSView) {
            if let s = v as? NSScrollView, (s.documentView?.frame.height ?? 0) > (best?.documentView?.frame.height ?? 0)
            {
                best = s
            }
            v.subviews.forEach(walk)
        }
        if let v { walk(v) }
        return best
    }
}
#endif
