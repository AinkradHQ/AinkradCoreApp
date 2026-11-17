#if DEBUG
import AppKit
import CoreUI
import LoreEditor
import SwiftUI

/// Debug only. `CORE_LORE_SNAPSHOT=<dir> [CORE_THEME=light|dark] [CORE_REDUCE_MOTION=1]` puts the Lore editor on a page
/// island over the wallpaper (the Lore space, R6-01, is not here yet), walks it with real key events, captures the window,
/// logs the typing latency on the 10,000-word sample note and the round trip, and quits. `dir == nil` (`CORE_LORE_DEMO=1`)
/// leaves the page open to type in. No Core is reached.
@MainActor
enum LoreSnapshots {
    static func run(dir: String?, env: [String: String]) async {
        let theme = env["CORE_THEME"] == "light" ? "day" : "night"
        let reduce = env["CORE_REDUCE_MOTION"] == "1"
        NSApp.appearance = NSAppearance(named: theme == "day" ? .aqua : .darkAqua)
        try? await Task.sleep(for: .seconds(3))
        guard let window = await SnapshotCapture.mainWindow(), let root = window.contentView else {
            return log("no main window")
        }
        let editor = LoreEditorController(titles: LoreStubTitles(LoreSampleNote.noteTitles))
        editor.onNotice = { log("notice: \($0)") }
        let page = NSHostingView(rootView: LorePage(editor: editor))
        page.frame = root.bounds
        // The page replaces the window's content for the walk (a subview over the SwiftUI root was never drawn).
        window.contentView = page
        editor.load(markdown: LoreSampleNote.markdown)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(1))
        editor.focus()
        guard let dir else { return }
        let tv = window.firstResponder as? NSTextView
        var n = 0
        func shot(_ name: String) async {
            n += 1
            try? await Task.sleep(for: .seconds(1))
            let file = "\(dir)/\(String(format: "%02d", n))-\(name)-\(theme)\(reduce ? "-reduce" : "")-lore.png"
            log("shot \(name) \(SnapshotCapture.png(window, to: file) ? "ok" : "FAILED")")
        }
        log("round trip sample: \(editor.markdown() == LoreSampleNote.markdown ? "identical" : "CHANGED")")
        await shot("sample-top")

        // The middle of the note: lists, tasks, code and a table.
        if let tv {
            let at = (tv.string as NSString).range(of: "| Item").location
            tv.scrollRangeToVisible(NSRange(location: max(0, at), length: 0))
            tv.setSelectedRange(NSRange(location: max(0, at), length: 0))
        }
        await shot("sample-blocks")

        // A note typed from scratch with every shortcut, as in the R0-01 demo.
        editor.load(markdown: "")
        await type("# Morning pages", window)
        await key(.ret, window)
        await type("A calm paragraph with **bold**, *italic* and `inline code` in it.", window)
        await key(.ret, window)
        await type("- first item", window)
        await key(.ret, window)
        await type("second item", window)
        await key(.ret, window)
        await key(.tab, window)
        await type("nested item", window)
        await key(.ret, window)
        await key(.backtab, window)
        await type("back to the top level", window)
        await key(.ret, window)
        await key(.ret, window)
        await type("[] buy paper", window)
        await key(.ret, window)
        await type("call the printer", window)
        await key(.ret, window)
        await key(.ret, window)
        await type("1. one", window)
        await key(.ret, window)
        await type("two", window)
        await key(.ret, window)
        await key(.ret, window)
        await type("> A quiet quote.", window)
        await key(.ret, window)
        await key(.ret, window)
        await type("See [[ga", window)
        await shot("link-picker")
        await key(.ret, window)
        await type("for details.", window)
        await key(.ret, window)
        await type("```", window)
        await type("let x = 1", window)
        await key(.ret, window)
        await type("print(x)", window)
        await key(.ret, window)
        await key(.ret, window)
        await type("Done for today.", window)
        let typed = editor.markdown()
        log("typed note markdown:\n\(typed)")
        editor.load(markdown: typed)
        log("round trip typed: \(editor.markdown() == typed ? "identical" : "CHANGED")")
        await shot("typed-note")

        // Find (⌘F): the native find bar over the sample note.
        editor.load(markdown: LoreSampleNote.markdown)
        editor.focus()
        await key(.find, window)
        await type("harbor", window)
        await shot("find-bar")

        // Typing latency, in the middle of the 10,000-word note (the R0-01 meter: key press → laid out).
        editor.load(markdown: LoreSampleNote.markdown)
        editor.focus()
        if let tv = window.firstResponder as? NSTextView {
            let ns = tv.string as NSString
            let pr = ns.paragraphRange(for: NSRange(location: ns.length / 2, length: 0))
            tv.setSelectedRange(NSRange(location: NSMaxRange(pr) - 1, length: 0))
            tv.scrollRangeToVisible(pr)
        }
        editor.resetLatency()
        let prose = Array("the quiet lantern hums over the harbor while we write a few more lines. ")
        for i in 0..<300 {
            if i > 0 && i % 90 == 0 {
                send("\r", 36, [], window)
            } else {
                send(String(prose[i % prose.count]), 0, [], window)
            }
            try? await Task.sleep(for: .milliseconds(12))
        }
        let s = editor.latency
        log(String(format: "LATENCY 10k-word note, middle: p50 %.2f ms, p95 %.2f ms, %d keys", s.p50, s.p95, s.n))
        await shot("typing-middle")
        NSApp.terminate(nil)
    }

    private enum Key { case ret, tab, backtab, find }

    private static func key(_ k: Key, _ w: NSWindow) async {
        switch k {
        case .ret: send("\r", 36, [], w)
        case .tab: send("\t", 48, [], w)
        case .backtab: send("\u{19}", 48, .shift, w)
        case .find: send("f", 3, .command, w)
        }
        try? await Task.sleep(for: .milliseconds(60))
    }

    private static func type(_ s: String, _ w: NSWindow) async {
        for ch in s {
            send(String(ch), 0, [], w)
            try? await Task.sleep(for: .milliseconds(14))
        }
    }

    private static func send(_ chars: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags, _ w: NSWindow) {
        guard
            let e = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                isARepeat: false, keyCode: code)
        else { return }
        // A key equivalent (⌘F) goes through the app's own path, as a real one does.
        if flags.contains(.command) {
            NSApp.sendEvent(e)
        } else {
            w.sendEvent(e)
        }
    }

    private static func log(_ s: String) { SnapshotCapture.log(s) }
}

/// The editor on a page island over the wallpaper: how the Lore space (R6-01) will hold it.
private struct LorePage: View {
    let editor: LoreEditorController
    var body: some View {
        ZStack {
            WallpaperView().ignoresSafeArea()
            LoreEditor(editor)
                .coreFrame(radius: Radius.pane)
                .frame(maxWidth: Space.s8 * 30)
                .padding(.horizontal, Space.s8)
                .padding(.vertical, Space.s8 + Space.s6)
        }
        .coreTheme()
    }
}
#endif
