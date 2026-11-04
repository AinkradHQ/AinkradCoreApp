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
}
