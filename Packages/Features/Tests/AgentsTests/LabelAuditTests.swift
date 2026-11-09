import CoreUI
import Foundation
import Testing

@testable import Agents

/// Accessibility label audit (A-29): session words are plain, non-empty and never a raw code.
struct AgentLabelAuditTests {
    @Test func everyEndedKindReadsAsWords() {
        for kind in [
            "succeeded", "failed", "stalled", "token_cap", "budget", "cancelled", "lost", "ended", "", "odd_code",
        ] {
            let words = AgentWords.endedWords(kind)
            #expect(!words.isEmpty && !words.contains("_"), "\(kind) -> \(words)")
        }
    }

    @Test func clocksTokensAndMoneyUseSystemFormats() {
        #expect(AgentWords.clock(75) == "1:15" && AgentWords.clock(3725) == "1:02:05")
        #expect(AgentWords.cost(2_500_000) == "$2.50" && AgentWords.cost(nil) == nil)
        #expect(AgentWords.tokens(999) == "999" && AgentWords.tokens(1_500_000).hasSuffix("M"))
    }

    @Test func everySessionStateHasAStatusWord() {
        for e in SessionState.table {
            #expect(!e.label.isEmpty, "\(e.raw) has no word")
        }
    }
}
