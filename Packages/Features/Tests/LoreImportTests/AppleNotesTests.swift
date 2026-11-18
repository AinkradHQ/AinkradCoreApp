import Foundation
import Testing

@testable import LoreImport

@Suite struct AppleNotesTests {
    private let root = URL(fileURLWithPath: "/tmp/lore-notes-test")

    @Test func hostileHTMLGivesTextWithoutIt() {
        let html =
            "<p>Hello</p><script>alert('x')</script><style>p{}</style><iframe src='https://e'>frame text</iframe>"
            + "<a href='javascript:alert(1)'>click</a> <a href=' java\nscript:x'>two</a> <a href='https://ok.example/a(b)'>ok</a>"
            + "<img src='https://tracker/x.png'>"
        let md = NoteHTML.convert(html)!.markdown
        #expect(md.contains("Hello"))
        #expect(md.contains("click"))
        for bad in ["alert", "p{}", "frame text", "javascript", "script:", "tracker", "!["] {
            #expect(!md.contains(bad))
        }
        #expect(md.contains("[ok](https://ok.example/a%28b%29)"))
    }

    @Test func deepNestingAndSizeCap() {
        let deep = String(repeating: "<ul><li>", count: 20_000) + "x"
        let out = NoteHTML.convert(deep)!
        #expect(out.markdown.contains("x"))
        #expect(!out.markdown.contains(String(repeating: " ", count: 40)))
        #expect(NoteHTML.convert(String(repeating: "a", count: NoteHTML.maxInput + 1)) == nil)
        let many = (0..<500).map { "<t\($0)>" }.joined()
        #expect(NoteHTML.convert(many)!.warnings.count <= NoteHTML.maxWarnings)
    }

    @Test func entitiesAndBasics() {
        #expect(
            NoteHTML.convert("<h1>T</h1><b>a &amp; b</b> &#x2019;<ul><li>one</li></ul>")!.markdown
                == "# T\n**a & b** \u{2019}\n- one")
    }

    @Test func parsesRecordsAndKeepsOnlyStagedAttachments() {
        let rs = AppleNotesSource.recordSeparator
        let us = AppleNotesSource.unitSeparator
        let inside = root.appendingPathComponent("1-1").path
        let out =
            "x-id-1\nTitle\nAcct\nWork\n<p>a</p>\n<p>b</p>\n\(us)\n"
            + "att1\(us)pic.png\(us)\(inside)\natt2\(us)evil.png\(us)/etc/hosts\natt3\(us)gone\(us)\n\(rs)\n"
            + "x-id-2\ncut off\n"
        let notes = AppleNotesSource.parse(out, stagingRoot: root)
        #expect(notes.count == 1)
        #expect(notes[0].folder == "Work" && notes[0].html == "<p>a</p>\n<p>b</p>")
        #expect(notes[0].attachments.map(\.name) == ["pic.png", "evil.png", "gone"])
        #expect(notes[0].attachments[0].file != nil)
        #expect(notes[0].attachments[1].file == nil && notes[0].attachments[2].file == nil)
    }

    @Test func exportPathsTagsAndAttachmentLinks() {
        let note = AppleNote(
            id: "x-1", title: "../Plan: A", account: "iCloud", folder: ".Work/Home",
            html: "<h1>../Plan: A</h1><p>text</p>",
            attachments: [
                AppleNoteAttachment(name: "a.pdf", file: nil), AppleNoteAttachment(name: "p[1].png", file: nil),
            ])
        let (files, skipped) = AppleNotesExport.prepare([note])
        #expect(skipped.isEmpty && files.count == 1)
        let f = files[0]
        #expect(f.path.hasPrefix("Work-Home/") && f.path.hasSuffix(".md") && !f.path.dropFirst(10).contains("/"))
        #expect(f.markdown.hasPrefix("# ../Plan: A\ntext") || f.markdown.hasPrefix("# ../Plan: A"))
        let text = AppleNotesExport.finish(f, shas: ["ab", nil])
        #expect(text.contains("[a.pdf](lore-attachment:ab)") && text.contains("could not be imported"))
        #expect(AppleNotesExport.prepare([note]).files[0].path == f.path)
    }

    @Test func scriptNeverBuildsAFileNameFromANote() {
        let s = AppleNotesSource.script(stagingRoot: "/tmp/a\"b")
        #expect(s.contains("/tmp/a\\\"b"))
        #expect(!s.contains("do shell script") && !s.contains("ext"))
    }
}
