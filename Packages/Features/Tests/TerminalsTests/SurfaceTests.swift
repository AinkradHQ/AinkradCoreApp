import Foundation
import Testing

@testable import Terminals

@MainActor
@Suite struct SurfaceTests {
    @Test func whatIsOnScreenReadsBackAsText() {
        let s = TerminalSurface()
        s.feed(Data("first line\r\n$ echo hi\r\nhi\r\n$ ".utf8))
        let text = s.visibleText()
        #expect(
            text.contains("first line") && text.contains("hi\r\n") || text.contains("hi\n"),
            "got \(text.debugDescription)")
        #expect(text.contains("$ echo hi"), "got \(text.debugDescription)")
    }

    @Test func aSnapshotClearsBeforeItDraws() {
        let s = TerminalSurface()
        s.feed(Data("old screen\r\n".utf8))
        s.feed(Data("new screen".utf8), repaint: true)
        #expect(!s.visibleText().contains("old screen") && s.visibleText().contains("new screen"))
    }

    /// Reopening a terminal replays its history; a device-attributes query `claude` sent earlier must not be answered
    /// again, or the answer lands in the shell as typed text (Oracle, 2026-11-21). A live query is still answered.
    @Test func historyIsDrawnWithoutAnsweringItsQuestions() {
        let s = TerminalSurface()
        var sent = Data()
        s.onInput = { sent.append($0) }
        s.feed(Data("\u{1b}[c".utf8), replay: true)
        #expect(sent.isEmpty, "got \(sent.debugDescription)")
        s.feed(Data("\u{1b}[c".utf8))
        #expect(!sent.isEmpty)
    }
}
