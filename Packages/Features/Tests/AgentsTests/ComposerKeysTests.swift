import AppKit
import Testing

@testable import Agents

/// The composer's field hands Return, ↑, ↓, Tab and Esc to the composer itself (2026-11-15: Return sometimes made a new
/// line instead of sending, and the command list ignored the arrows).
@MainActor
struct ComposerKeysTests {
    private func field(_ log: @escaping (String) -> Void, takes: Bool = true) -> KeyTextView {
        let tv = KeyTextView()
        tv.keys = ComposerKeys(
            submit: { shift in
                log(shift ? "shift-return" : "return")
                return takes && !shift
            },
            up: {
                log("up")
                return takes
            },
            down: {
                log("down")
                return takes
            },
            tab: {
                log("tab")
                return takes
            },
            escape: {
                log("escape")
                return takes
            })
        return tv
    }

    @Test func everyKeyReachesTheComposer() {
        var seen: [String] = []
        let tv = field { seen.append($0) }
        for s in [
            #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.moveUp(_:)),
            #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertTab(_:)),
            #selector(NSResponder.cancelOperation(_:)),
        ] {
            tv.doCommand(by: s)
        }
        #expect(seen == ["return", "up", "down", "tab", "escape"])
        #expect(tv.string.isEmpty)  // nothing was typed into the field
    }

    @Test func returnTheComposerDoesNotTakeIsANewLine() {
        let tv = field({ _ in }, takes: false)
        tv.isEditable = true
        tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(tv.string == "\n")
    }

    @Test func composingWithAnInputMethodKeepsReturn() {
        var seen: [String] = []
        let tv = field { seen.append($0) }
        tv.isEditable = true
        tv.setMarkedText(
            "ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 0, length: 0))
        tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(seen.isEmpty)
    }

    // MARK: attachments (a private pasteboard: the person's clipboard is never touched)

    private func board() -> NSPasteboard {
        let pb = NSPasteboard(name: .init("ainkrad.composer.tests"))
        pb.clearContents()
        return pb
    }

    @Test func pastedFilesBecomeAttachments() {
        let pb = board()
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        pb.writeObjects([url as NSURL])
        #expect(KeyTextView.files(from: pb) == [url])
    }

    @Test func aPastedScreenshotIsSavedAsAFile() throws {
        let pb = board()
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { r in
            NSColor.red.setFill()
            r.fill()
            return true
        }
        pb.writeObjects([image])
        let files = try #require(KeyTextView.files(from: pb))
        #expect(files.count == 1 && files[0].pathExtension == "png")
        #expect(FileManager.default.fileExists(atPath: files[0].path))
        try? FileManager.default.removeItem(at: files[0])
    }

    @Test func wordsCopiedWithAnImageStillPasteAsWords() {
        let pb = board()
        pb.declareTypes([.string, .tiff], owner: nil)
        pb.setString("hello", forType: .string)
        pb.setData(NSImage(size: NSSize(width: 2, height: 2)).tiffRepresentation, forType: .tiff)
        #expect(KeyTextView.files(from: pb) == nil)
    }

    @Test func theMessageCarriesItsFilesAfterItsWords() {
        let f = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.txt")]
        #expect(AgentsModel.outgoing(words: "look", files: f) == "look\n\n@/tmp/a.png @/tmp/b.txt")
        #expect(AgentsModel.outgoing(words: "", files: f) == "@/tmp/a.png @/tmp/b.txt")
        #expect(AgentsModel.outgoing(words: "only words", files: []) == "only words")
    }
}
