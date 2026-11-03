import Foundation
import Testing

@testable import CoreUI

struct StatesTests {
    @Test func knownValuesDecode() throws {
        let s = try JSONDecoder().decode(SessionState.self, from: Data(#""interrupted""#.utf8))
        #expect(s == .interrupted)
        #expect(s.label == "Resuming" && s.tone == .warn && s.symbol == "arrow.clockwise")
        #expect(RunState(rawValue: "timed_out") == .timedOut)
        #expect(AccountState(rawValue: "over_budget").label == "Budget reached")
    }

    @Test func unknownValuesKeepTheirRawWord() throws {
        let s = try JSONDecoder().decode(TerminalState.self, from: Data(#""frozen""#.utf8))
        #expect(s == .unknown("frozen"))
        #expect(s.label == "frozen" && s.tone == .queue)
        #expect(String(data: try JSONEncoder().encode(s), encoding: .utf8) == #""frozen""#)
    }

    @Test func everyKnownStateRoundTrips() {
        func check<S: CoreState>(_: S.Type) {
            for e in S.table { #expect(S(rawValue: e.raw) == e.state && e.state.rawValue == e.raw) }
        }
        check(AccountState.self)
        check(SessionState.self)
        check(SessionOutcome.self)
        check(TerminalState.self)
        check(IssueState.self)
        check(RunState.self)
    }
}

struct TokenTests {
    @Test func radiiAreRoundedRectsNotPills() {
        #expect(Radius.control == 8 && Radius.chip == 6)
        #expect(
            [Radius.chip, Radius.control, Radius.cardMac, Radius.row, Radius.pane, Radius.panel].allSatisfy {
                $0 > 0 && $0 <= 18
            })
    }

    @Test func durationsAreNonZero() {
        #expect(
            [Motion.press, Motion.hover, Motion.ui, Motion.move, Motion.reveal, Motion.tick, Motion.stagger].allSatisfy
            { $0 > 0 })
    }
}
