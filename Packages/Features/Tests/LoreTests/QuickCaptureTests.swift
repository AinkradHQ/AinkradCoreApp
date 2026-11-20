import CoreKit
import Foundation
import Testing

@testable import Lore

@MainActor
struct QuickCaptureTests {
    let host = FakeHost()
    let core = FakeLore()
    let model: LoreModel
    let capture: QuickCapture
    let today = LoreModel.key(Date())

    init() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lore-capture-\(UUID().uuidString)")
        model = LoreModel(host: host, page: FakePage(), drafts: LoreDrafts(dir: dir))
        capture = QuickCapture(lore: model, defaults: UserDefaults(suiteName: "capture-\(UUID().uuidString)")!)
        model.service = core
    }

    @Test func appendsUnderAStamp() {
        #expect(QuickCapture.appended("", "Buy seeds", stamp: "09:05") == "### 09:05\n\nBuy seeds\n")
        #expect(
            QuickCapture.appended("# Morning\n\nTea.\n\n", "Buy seeds", stamp: "09:05")
                == "# Morning\n\nTea.\n\n### 09:05\n\nBuy seeds\n")
    }

    @Test func returnAddsToTodayFromTheHeadRev() async {
        core.put(LoreNote(id: "ln_cccccccccccc", kind: "daily", day: today, rev: 4, text: "# Day\n"))
        capture.text = "  Call the bike shop \n"
        await capture.submit()
        #expect(capture.saved?.destination == "Today", "the bar says where it went")
        #expect(capture.text.isEmpty)
        #expect(core.log() == ["today \(today)", "save ln_cccccccccccc 4"])
        let text = core.notes["ln_cccccccccccc"]?.text ?? ""
        #expect(text.hasPrefix("# Day\n\n### ") && text.hasSuffix("\n\nCall the bike shop\n"))
    }

    @Test func aSecondCaptureKeepsWhatAnAIAdded() async {
        core.put(LoreNote(id: "ln_cccccccccccc", kind: "daily", day: today, rev: 1, text: "# Day\n"))
        capture.text = "From the panel"
        await capture.submit()
        _ = core.append("ln_cccccccccccc", "AI line\n")
        capture.close()  // the bar shows "Saved to …" until it closes
        capture.text = "Second"
        await capture.submit()
        let text = core.notes["ln_cccccccccccc"]?.text ?? ""
        #expect(text.contains("From the panel") && text.contains("AI line") && text.contains("Second"))
    }

    @Test func aProjectDestinationMakesANewNote() async {
        capture.destination = .project(id: "7", name: "Atlas")
        capture.text = "Plot map ideas"
        await capture.submit()
        #expect(core.log() == ["create 7"])
        #expect(capture.saved?.destination == "Atlas")
    }

    @Test func inboxIsMadeOnceThenAppendedTo() async {
        capture.destination = .inbox
        capture.text = "First"
        await capture.submit()
        #expect(core.log() == ["list active note -", "create personal"])
        #expect(core.notes["ln_bbbbbbbbbbbb"]?.text.hasPrefix("# Inbox\n") == true)
        core.notes["ln_bbbbbbbbbbbb"]?.title = "Inbox"  // the Core derives it from the heading
        capture.close()
        capture.text = "Second"
        await capture.submit()
        #expect(core.notes["ln_bbbbbbbbbbbb"]?.text.contains("Second") == true)
    }

    @Test func undoPutsTheNoteBackAndReturnsTheText() async {
        core.put(LoreNote(id: "ln_cccccccccccc", kind: "daily", day: today, rev: 1, text: "# Day\n"))
        capture.text = "Oops"
        await capture.submit()
        await capture.undo("Oops")
        #expect(core.notes["ln_cccccccccccc"]?.text == "# Day\n")
        #expect(capture.text == "Oops" && capture.saved == nil)
    }

    @Test func escapeClearsTheText() {
        capture.text = "Never mind"
        capture.cancel()
        #expect(capture.text.isEmpty && !capture.shown)
    }

    @Test func aFailedSendComesBackWithTheText() async {
        core.offline = true
        capture.text = "Keep me"
        await capture.submit()
        #expect(capture.shown)
        #expect(capture.text == "Keep me")
        #expect(capture.error?.hasPrefix("Unable to save") == true)
    }

    @Test func notConnectedKeepsThePanelAndText() async {
        model.service = nil
        capture.text = "Hello"
        await capture.submit()
        #expect(capture.shown && capture.text == "Hello" && capture.error != nil)
    }

    @Test func shortcutNamesAndStorage() {
        #expect(CaptureShortcut.standard.keys == "⇧⌘N")
        #expect(CaptureShortcut.fallback.keys == "⌥⌘N")
        let defaults = UserDefaults(suiteName: "capture-\(UUID().uuidString)")!
        let a = QuickCapture(lore: model, defaults: defaults)
        a.shortcut = .fallback
        #expect(QuickCapture(lore: model, defaults: defaults).shortcut == .fallback)
    }
}
