#if DEBUG
import AppKit
import CoreUI
import Lore
import Pairing

/// Debug only. `CORE_LORE_SPACE_SNAPSHOT=<dir> [CORE_THEME=light|dark] [CORE_REDUCE_MOTION=1] [CORE_LORE_SCENES=a,b]
/// [CORE_LORE_LOOK=clear]` walks the Lore space on
/// made-up notes (`LoreDemo`), captures each state, then runs two checks with real key events and logs them: an AI append
/// while typing must not move the caret, and text typed while the Core link is down must be kept and sent when it is back.
@MainActor
enum LoreSpaceSnapshots {
    static func run(_ app: AppModel, dir: String, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        let reduce = env["CORE_REDUCE_MOTION"] == "1"
        // A see-through Look for the walk (the person's own is put back when it ends).
        let clear = env["CORE_LORE_LOOK"] == "clear"
        let look = LookPrefs.shared
        let kept = (look.mode, look.opacity, look.blur)
        if clear {
            look.mode = .blurred
            look.opacity = 0.25
            look.blur = 1
        }
        let only = Set((env["CORE_LORE_SCENES"] ?? "").split(separator: ",").map(String.init))
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = await SnapshotCapture.mainWindow() else { return finish("no main window") }
        let demo = app.debugLoreDemo()
        // The person's Look and sidebars are put back when the walk ends.
        restore = {
            if clear { (look.mode, look.opacity, look.blur) = kept }
            demo.restoreSidebars()
        }
        var n = 0
        func shot(_ name: String) async {
            n += 1
            try? await Task.sleep(for: .seconds(1.2))
            let file =
                "\(dir)/\(String(format: "%02d", n))-\(name)-\(theme)\(reduce ? "-reduce" : "")\(clear ? "-clear" : "")-lore-space.png"
            log("shot \(name) \(SnapshotCapture.png(window, to: file) ? "ok" : "FAILED")")
        }
        for scene in LoreDemo.scenes where only.isEmpty || only.contains(scene) {
            let start = Date()
            await demo.show(scene)
            if scene == "today-blank" {
                // L1: the page takes typing at once.
                while !(window.firstResponder is NSTextView), Date().timeIntervalSince(start) < 3 {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                log(
                    String(
                        format: "TYPING READY after %.0f ms (includes the walk's 700 ms of settling)",
                        Date().timeIntervalSince(start) * 1000))
            }
            await shot(scene)
        }

        // The keyboard: ⌘L to the note list, ↓ ↓ moves its cursor; Esc, Esc back to the note; ⌘3 to the outline, ↓.
        await demo.show("project-note")
        await key("l", [.command], window)
        await key("\u{F701}", [], window, code: 125)
        await key("\u{F701}", [], window, code: 125)
        await shot("keys-list")
        await key("\u{1B}", [], window, code: 53)
        log("KEYS esc gives the note back: \(window.firstResponder is NSTextView ? "yes" : "NO")")
        await key("3", [.command], window)
        await key("\u{F701}", [], window, code: 125)
        await shot("keys-outline")
        if only.contains("latency") || only.isEmpty { await latency(demo, window) }
        if only.contains("sizes") { await sizes(demo, only.contains("sizes-type")) }
        if !only.isEmpty { return finish(nil) }

        // Check 1: typing in the middle, an AI append lands at the end, the caret stays.
        await demo.show("today")
        try? await Task.sleep(for: .seconds(1))
        guard let tv = window.firstResponder as? NSTextView else { return finish("no text view focused") }
        let mid = (tv.string as NSString).range(of: "small notes").location
        tv.setSelectedRange(NSRange(location: mid, length: 0))
        await type("really ", window)
        let before = tv.selectedRange().location
        demo.remoteAppend("\n\nAdded by an AI session: remember the seed order.\n")
        try? await Task.sleep(for: .seconds(2))
        await type("very ", window)
        try? await Task.sleep(for: .seconds(2))
        let after = tv.selectedRange().location
        let core = await demo.coreText()
        log("FOLD caret before \(before) after typing 5 more \(after) → \(after == before + 5 ? "kept" : "MOVED")")
        log(
            "FOLD core has both: \(core.contains("really very small notes") && core.contains("seed order") ? "yes" : "NO")"
        )
        await shot("fold")

        // Check 2: the link drops mid-typing, the text is kept on this Mac, then sent when the link is back.
        demo.setOffline(true)
        await type("Offline line. ", window)
        // Under 3 s after the last key, so the shot also shows the header and key line stepped back while typing.
        try? await Task.sleep(for: .seconds(1.2))
        log("DRAFT while offline: \(demo.syncWords) draft=\(demo.hasDraft)")
        await shot("kept-typing")
        demo.setOffline(false)
        try? await Task.sleep(for: .seconds(2))
        let sent = await demo.coreText()
        log("DRAFT after reconnect: sent=\(sent.contains("Offline line.")) draft=\(demo.hasDraft)")
        await sizes(demo, true)
        finish(nil)
    }

    /// Keystroke to laid-out page on a 6,000-line note, typed with real key events in its middle.
    private static func latency(_ demo: LoreDemo, _ window: NSWindow) async {
        await demo.show("today")
        demo.loadLong(1_000)
        try? await Task.sleep(for: .seconds(1))
        if let tv = demo.textView { window.makeFirstResponder(tv) }
        await type("the quick brown fox jumps over the lazy dog and keeps on running ", window)
        log("LAT long note (6000 lines): \(demo.latency)")
        let dir = ProcessInfo.processInfo.environment["CORE_LORE_SPACE_SNAPSHOT"] ?? "/tmp"
        try? await Task.sleep(for: .seconds(0.8))
        log(
            "shot latency \(SnapshotCapture.png(window, to: "\(dir)/latency-long-note-lore-space.png") ? "ok" : "FAILED")"
        )
    }

    /// The blank page in windows from small to very wide, with the sidebars in every combination: the header, the
    /// prompt (the caret at its start) and the key line must stay whole. Last: the editor moves into these windows.
    private static func sizes(_ demo: LoreDemo, _ typeToo: Bool) async {
        let theme = NSApp.appearance?.name == .aqua ? "day" : "night"
        let dir = ProcessInfo.processInfo.environment["CORE_LORE_SPACE_SNAPSHOT"] ?? "/tmp"
        for size in [
            CGSize(width: 860, height: 560), CGSize(width: 1280, height: 760), CGSize(width: 2000, height: 1180),
        ] {
            for (name, left, right) in [
                ("both", true, true), ("noleft", false, true), ("none", false, false), ("longtitle", true, true),
            ] {
                await demo.show("today-blank")
                if name == "longtitle" { await demo.longTitle() }
                demo.sides(left, right)
                let w = demo.window(size)
                try? await Task.sleep(for: .seconds(1.5))
                if let tv = demo.textView {
                    w.makeFirstResponder(tv)
                    let caret = tv.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
                    let local = tv.convert(w.convertFromScreen(caret), from: nil)
                    log(
                        "SIZE \(Int(size.width))x\(Int(size.height)) \(name) caret x=\(Int(local.minX)) inset=\(Int(tv.textContainerOrigin.x))"
                    )
                }
                try? await Task.sleep(for: .seconds(0.6))
                let file = "\(dir)/size-\(Int(size.width))x\(Int(size.height))-\(name)-\(theme)-lore-space.png"
                log("shot size \(Int(size.width)) \(name) \(SnapshotCapture.png(w, to: file) ? "ok" : "FAILED")")
                if typeToo, name == "noleft", size.width == 1280 {
                    await type("Hello", w)
                    try? await Task.sleep(for: .seconds(0.6))
                    _ = SnapshotCapture.png(w, to: "\(dir)/size-typed-\(theme)-lore-space.png")
                }
                w.orderOut(nil)
                w.contentView = nil
                w.close()
            }
        }
    }

    /// Puts the person's Look back before the app quits.
    private static var restore: (() -> Void)?

    private static func finish(_ why: String?) {
        if let why { log(why) }
        restore?()
        NSApp.terminate(nil)
    }

    private static func type(_ s: String, _ w: NSWindow) async {
        for ch in s {
            guard
                let e = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: w.windowNumber, context: nil, characters: String(ch),
                    charactersIgnoringModifiers: String(ch), isARepeat: false, keyCode: 0)
            else { continue }
            w.sendEvent(e)
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func key(_ ch: String, _ mods: NSEvent.ModifierFlags, _ w: NSWindow, code: UInt16 = 0) async {
        guard
            let e = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: w.windowNumber, context: nil, characters: ch, charactersIgnoringModifiers: ch,
                isARepeat: false, keyCode: code)
        else { return }
        // A ⌘ key goes the way AppKit sends it: the window's controls first, then the menu bar.
        let taken =
            mods.contains(.command)
            && (w.performKeyEquivalent(with: e) || NSApp.mainMenu?.performKeyEquivalent(with: e) == true)
        if !taken { w.sendEvent(e) }
        try? await Task.sleep(for: .milliseconds(400))
    }

    private static func log(_ s: String) { SnapshotCapture.log(s) }
}
#endif
