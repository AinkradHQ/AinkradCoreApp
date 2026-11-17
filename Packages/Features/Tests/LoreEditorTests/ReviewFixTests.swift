import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import LoreEditor

/// Appends `tail` at the end of the first paragraph containing `marker`, as typing would.
@MainActor func typeAfter(_ marker: String, _ tail: String, in c: LoreEditorController) {
    let tv = c.textView
    let r = (tv.string as NSString).range(of: marker)
    tv.setSelectedRange(NSRange(location: NSMaxRange(r), length: 0))
    tv.insertText(tail, replacementRange: tv.selectedRange())
}

@MainActor func ms(_ body: () -> Void) -> Double {
    let t = ContinuousClock.now
    body()
    let d = ContinuousClock.now - t
    return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
}

/// Security review of #147, finding 1: hostile lines must parse in linear time.
@MainActor struct HostileInputTests {
    /// The review's two cases must parse in under 50 ms; the other shapes, just under the plain-text limit, in under 100 ms
    /// (2,000 inline code spans is real formatting work, not backtracking). Debug build.
    @Test(arguments: [
        (String(repeating: "[[", count: 50_000), 50.0),  // 100 KB, over the plain-text limit
        (String(repeating: "**a ", count: 10_000), 50.0),  // 40 KB
        (String(repeating: "[[", count: 2_000), 100.0),  // 4 KB, parsed: the bounds do the work
        (String(repeating: "**a ", count: 1_000), 100.0),
        (String(repeating: "[a](", count: 1_000), 100.0),
        (String(repeating: "https://a.....", count: 290), 100.0),
        (String(repeating: "`a", count: 2_000), 100.0),
        (String(repeating: "_a ", count: 1_300), 100.0),
    ])
    func parsesFast(_ line: String, _ budget: Double) {
        _ = MarkdownReader.parse("warm up\n")
        let t = ms { _ = MarkdownReader.parse(line + "\n") }
        #expect(t < budget, "took \(Int(t)) ms for \(String(line.prefix(6))) x \(line.count)")
        print("PARSE \(String(line.prefix(6))) x \(line.count): \(String(format: "%.1f", t)) ms")
    }

    @Test func overTheLimitIsPlainText() {
        let line = Array(repeating: "**b**", count: 1_000).joined(separator: " ")
        let (text, _) = MarkdownReader.parse(line + "\n")
        #expect(text.string == line + "\n")
        #expect(text.attribute(.loreBold, at: 2, effectiveRange: nil) == nil)
        #expect(editor(line + "\n").markdown() == line + "\n")
    }
}

/// Finding 2: no web previews, no Look Up on links, no Writing Tools, no Open Link from the menu.
@MainActor struct NoFetchTests {
    @Test func writingToolsAreOff() throws {
        let tv = editor("").textView
        if #available(macOS 15.0, *) { #expect(tv.writingToolsBehavior == .none) }
    }

    /// Matched by selector only: these titles are German, and Look Up's is an unknown private selector name.
    @Test func contextMenuDropsOpenLinkLookUpAndShare() {
        let m = NSMenu()
        for (title, sel) in [
            ("Link öffnen", "_openLinkFromMenu:"), ("Link kopieren", "copyLink:"),
            ("„x“ nachschlagen", "_lookUpDefiniteRange:"), ("Mit Google suchen", "_searchWithGoogleFromMenu:"),
            ("Ausschneiden", "cut:"), ("Kopieren", "copy:"), ("Einsetzen", "paste:"), ("Teilen …", "_share:"),
            ("Schreibtools", "showWritingTools:"), ("Übersetzen", "_translate:"),
            ("Übersicht", "toggleQuickLookPreviewPanel:"),
        ] {
            m.addItem(NSMenuItem(title: title, action: NSSelectorFromString(sel), keyEquivalent: ""))
            m.addItem(.separator())
        }
        let services = NSMenuItem(title: "Dienste", action: nil, keyEquivalent: "")
        services.submenu = NSMenu()
        m.addItem(services)
        let left = LoreTextView.safeMenu(m).items.filter { !$0.isSeparatorItem }.map(\.title)
        #expect(left == ["Link kopieren", "Ausschneiden", "Kopieren", "Einsetzen"])
        #expect(m.items.first?.isSeparatorItem == false && m.items.last?.isSeparatorItem == false)
    }

    /// `NSTextView.defaultMenu` is shared by every text view in the app: filtering works on a copy.
    @Test func sharedDefaultMenuIsNotChanged() throws {
        let c = editor("hello [l](https://x.io)\n")
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered,
            defer: false)
        w.contentView = c.scrollView
        let e = try #require(
            NSEvent.mouseEvent(
                with: .rightMouseDown, location: NSPoint(x: 60, y: 280), modifierFlags: [], timestamp: 0,
                windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let before = NSTextView.defaultMenu?.items.count
        let menu = c.textView.menu(for: e)
        #expect(menu !== NSTextView.defaultMenu)
        #expect(NSTextView.defaultMenu?.items.count == before)
        #expect(menu?.items.contains { $0.action == NSSelectorFromString("toggleQuickLookPreviewPanel:") } == false)
    }
}

@MainActor final class SlowUploader: LoreAttachmentUploader {
    var calls = 0
    func upload(_ file: LoreUpload) async throws -> URL {
        calls += 1
        try await Task.sleep(for: .milliseconds(150))
        return URL(string: "lore-attachment:" + String(repeating: "b", count: 64))!
    }
}

/// Finding 3: an upload that ends after a note switch is dropped.
@MainActor struct UploadAcrossNotesTests {
    @Test func lateUploadNeverLandsInTheNextNote() async throws {
        _ = NSApplication.shared
        let up = SlowUploader()
        let c = LoreEditorController(uploader: up)
        c.load(markdown: "first note\n")
        c.upload(LoreUpload(name: "a.png", type: .png, data: Data([1, 2, 3])), at: 0)
        c.load(markdown: "second note\n")
        try await Task.sleep(for: .milliseconds(400))
        #expect(up.calls == 1)
        #expect(c.markdown() == "second note\n")
    }
}

/// Finding 4: blocks written fresh keep what they had.
@MainActor struct RewriteIntegrityTests {
    nonisolated static let escapes = [
        "a [b] c", "snake_case_name and _x_", "back\\slash", "star * here", "tick ` mark", "[[not a link]]",
        "**not bold**", "*not italic*", "[text](https://not.a.link)", "`not code`", "\\*kept escape\\*",
    ]

    /// Load → edit → reload shows the same text plus the edit, for text full of syntax characters.
    @Test(arguments: escapes) func escapedTextSurvivesARewrite(_ shown: String) {
        let c = editor("")
        c.textView.insertText(shown, replacementRange: NSRange(location: 0, length: 0))
        let once = editor(c.markdown())
        #expect(once.textView.string == shown + "\n")
        typeAfter(shown, " x", in: once)
        #expect(editor(once.markdown()).textView.string == shown + " x\n")
    }

    @Test(arguments: [
        ("* a\n* b\n", "b", "* a\n* b x\n"), ("+ a\n+ b\n", "a", "+ a x\n+ b\n"),
        ("3. a\n4. b\n", "a", "3. a x\n4. b\n"), ("10) a\n11) b\n", "b", "10) a\n11) b x\n"),
        ("* [ ] a\n* [x] b\n", "a", "* [ ] a x\n* [x] b\n"),
    ])
    func listMarkersAndStartsAreKept(_ md: String, _ at: String, _ want: String) {
        let c = editor(md)
        typeAfter(at, " x", in: c)
        #expect(c.markdown() == want)
    }

    @Test func numberedListIsDrawnFromItsStart() {
        let c = editor("3. a\n4. b\n")
        #expect(c.textView.ts.attribute(.loreOrdinal, at: 0, effectiveRange: nil) as? Int == 3)
    }

    @Test func hardBreaksAndIndentationAreKept() {
        let md = "Line one  \n    indented two\\\nthree\n"
        let c = editor(md)
        typeAfter("three", " x", in: c)
        let out = c.markdown()
        #expect(out == "Line one  \n    indented two\\\nthree x\n", "\(out.debugDescription)")
    }
}

/// Finding 5: a file's real type and size are checked before it is read.
@MainActor struct FileChecksTests {
    @Test func symlinkedAndWrongFilesAreRefusedUnread() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let big = dir.appendingPathComponent("big.bin")
        FileManager.default.createFile(atPath: big.path, contents: Data(count: 11 * 1024 * 1024))
        let fakePNG = dir.appendingPathComponent("pic.png")
        try FileManager.default.createSymbolicLink(at: fakePNG, withDestinationURL: big)
        let script = dir.appendingPathComponent("run.sh")
        try Data("echo hi".utf8).write(to: script)
        let png = dir.appendingPathComponent("ok.png")
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try #require(rep.representation(using: .png, properties: [:])).write(to: png)

        let up = FakeUploader()
        _ = NSApplication.shared
        let c = LoreEditorController(uploader: up)
        c.load(markdown: "")
        var notices: [String] = []
        c.onNotice = { notices.append($0) }
        let pb = NSPasteboard(name: .init("lore-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.writeObjects([fakePNG as NSURL, script as NSURL, png as NSURL])
        #expect(c.textView.readPasteboard(pb))
        for _ in 0..<200 where up.got.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(up.got.map(\.name) == ["ok.png"])
        #expect(notices.count == 2)
    }
}

/// Round 2, finding 1: text that was not parsed is written back as it was, never escaped.
@MainActor struct RawTextTests {
    @Test func editNextToAnOverLimitParagraphKeepsItsSyntax() {
        let body = String(repeating: "word ", count: 830) + "**bold** [l](https://x.io) snake_case"
        let c = editor(body + "\n")
        typeAfter("snake_case", " z", in: c)
        #expect(c.markdown() == body + " z\n")
        #expect(editor(c.markdown()).markdown() == body + " z\n")
    }

    @Test func spanOverItsBoundStaysAsWritten() {
        let md = "A **" + String(repeating: "x", count: 300) + "** and snake_case.\n"
        let c = editor(md)
        typeAfter("snake_case.", " More", in: c)
        #expect(c.markdown() == md.replacingOccurrences(of: "snake_case.", with: "snake_case. More"))
    }

    @Test func typedSyntaxNextToRawTextIsEscaped() {
        let c = editor("plain_text here\n")
        typeAfter("here", " *not italic*", in: c)
        #expect(editor(c.markdown()).textView.string == "plain_text here *not italic*\n")
    }
}

/// Round 2, finding 2: the whole load is bounded.
@MainActor struct BoundedLoadTests {
    @Test func spansPerParagraphAreCapped() {
        let line = Array(repeating: "`a`", count: 300).joined(separator: " ")
        let (text, _) = MarkdownReader.parse(line + "\n")
        var spans = 0
        text.enumerateAttribute(.loreCode, in: NSRange(location: 0, length: text.length)) { v, _, _ in
            if v != nil { spans += 1 }
        }
        #expect(spans == MarkdownReader.spansPerParagraph)
        let c = editor(line + "\n")
        let end = (c.textView.string as NSString).length - 1
        c.textView.setSelectedRange(NSRange(location: end, length: 0))
        c.textView.insertText(" z", replacementRange: c.textView.selectedRange())
        #expect(c.markdown() == line + " z\n")
    }

    @Test func twoMegabyteHostileNoteLoadsInUnderTwoSeconds() {
        let para = String(String(repeating: "`a", count: 2_045).prefix(4_090))
        let note = Array(repeating: para, count: 480).joined(separator: "\n\n") + "\n"
        #expect(note.utf8.count > 1_960_000)
        _ = NSApplication.shared
        let c = LoreEditorController()
        let t = ms { c.load(markdown: note) }
        print("LOAD 2 MB hostile note: \(Int(t)) ms")
        #expect(t < 2_000)
        #expect(c.markdown() == note)
    }
}

/// Round 2, decision 3: soft-wrapped lines flow as one paragraph; hard breaks stay.
@MainActor struct SoftWrapTests {
    @Test func softWrapsFlowHardBreaksStay() {
        let c = editor("one\ntwo\nthree  \n  four\n")
        #expect(c.textView.string == "one two three  \u{2028}  four\n")
        #expect(c.markdown() == "one\ntwo\nthree  \n  four\n")
        typeAfter("four", " x", in: c)
        #expect(c.markdown() == "one two three  \n  four x\n")
    }
}

/// Round 3: tags stay tags, and replaced text is never raw.
@MainActor struct RoundThreeTests {
    @Test func tagAtLineStartSurvivesAnEditLater() {
        let md = "#tag first *x and more\n"
        let c = editor(md)
        typeAfter("more", " z", in: c)
        #expect(c.markdown() == "#tag first *x and more z\n")
    }

    @Test func typedTagAtLineStartIsNotEscaped() {
        let c = editor("")
        for ch in "#project notes" { c.textView.insertText(String(ch), replacementRange: c.textView.selectedRange()) }
        #expect(c.markdown() == "#project notes\n")
    }

    @Test func headingLikeLineIsStillEscaped() {
        let c = editor("")
        c.textView.insertText("# not a heading", replacementRange: NSRange(location: 0, length: 0))
        #expect(c.markdown() == "\\# not a heading\n")
    }

    /// Find & Replace goes through shouldChangeText → replaceCharacters → didChangeText, like this.
    @Test func replacedTextInARawParagraphIsEscaped() throws {
        let c = editor("plain words here and snake_case\n")
        let tv = c.textView
        let r = (tv.string as NSString).range(of: "words")
        let evil = "[Login](https://evil.io)"
        #expect(tv.shouldChangeText(in: r, replacementString: evil))
        tv.ts.replaceCharacters(in: r, with: evil)
        tv.didChangeText()
        let md = c.markdown()
        #expect(md == "plain \\[Login\\](https://evil.io) here and snake_case\n")
        let again = editor(md).textView
        // No disguised link: the only link is the bare address itself, shown as text (an autolink).
        var linked: [String] = []
        again.ts.enumerateAttribute(.link, in: NSRange(location: 0, length: again.ts.length)) { v, r, _ in
            if v != nil { linked.append((again.string as NSString).substring(with: r)) }
        }
        #expect(linked == ["https://evil.io"])
        #expect(again.string == "plain \(evil) here and snake_case\n")
    }
}
