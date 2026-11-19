import Foundation
import Testing

@testable import Terminals

@MainActor struct TerminalOptionsTests {
    @Test func textSizeNamesTheNearestChoice() {
        #expect(TerminalOptions.Size(points: 9) == .small)
        #expect(TerminalOptions.Size(points: 12) == .medium)
        #expect(TerminalOptions.Size(points: 20) == .large)
        for s in TerminalOptions.Size.allCases { #expect(TerminalOptions.Size(points: s.points) == s) }
    }

    @Test func underlineCountsAsALine() {
        #expect(TerminalOptions.Cursor(.underline) == .line && TerminalOptions.Cursor(.bar) == .line)
        #expect(TerminalOptions.Cursor(.block) == .block)
        #expect(TerminalOptions.Cursor.line.shape == .bar)
    }
}
