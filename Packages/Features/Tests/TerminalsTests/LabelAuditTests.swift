import Foundation
import Testing

@testable import Terminals

/// Accessibility label audit (A-29): the terminal filters are words, not codes.
struct TerminalsLabelAuditTests {
    @Test func everyFilterIsAWord() {
        for f in TerminalFilter.allCases { #expect(!f.rawValue.isEmpty && !f.rawValue.contains("_")) }
    }
}
