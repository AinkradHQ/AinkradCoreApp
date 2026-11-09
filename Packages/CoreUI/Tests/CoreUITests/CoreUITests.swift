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

struct HeatTests {
    @Test func bucketsCountPerSliceAndScaleToTheBusiest() {
        let now = Date(timeIntervalSince1970: 10_000)
        let cells = heatBuckets(
            [now, now.addingTimeInterval(-10), now.addingTimeInterval(-70), now.addingTimeInterval(-9_999)],
            now: now, slice: 60, count: 4)
        #expect(cells == [0, 0, 0.5, 1])
        #expect(heatBuckets([], now: now, slice: 60, count: 3) == [0, 0, 0])
        #expect(heatBuckets([now], now: now, slice: 0, count: 3).isEmpty)
    }
}

struct SurfaceTests {
    @Test func unitsJoinWithANoBreakSpace() {
        #expect(coreUnit("12", "ms") == "12\u{00A0}ms")
    }

    @Test func textScaleHasAFloorAndDefaultsToOne() {
        UserDefaults.standard.removeObject(forKey: MacTextSize.scaleKey)
        #expect(MacTextSize.scale == 1 && MacTextSize.scaled(MacTextSize.meta) == 11)
        UserDefaults.standard.set(0.8, forKey: MacTextSize.scaleKey)
        #expect(MacTextSize.scaled(11) == 10)  // 8.8 would fall under the 10 pt floor
        UserDefaults.standard.removeObject(forKey: MacTextSize.scaleKey)
    }

    @Test func increaseContrastStrengthensEdgeAndSecondaryInk() {
        #expect(Palette.day.contrast(.increased).increased && !Palette.day.increased)
        #expect(Palette.night.contrast(.standard).increased == false)
    }
}
