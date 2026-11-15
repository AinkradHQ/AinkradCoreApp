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
}
