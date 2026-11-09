import CoreUI
import Foundation
import Testing

@testable import Agents

struct RouteTests {
    var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    let now = Date(timeIntervalSince1970: 1_794_000_000)  // a fixed day, 21:20 UTC

    @Test func chainStepIsCountedFromOne() {
        let r = SessionRoute(chainID: 1, chainPos: 1, steps: ["claude · sonnet", "codex · default model"])
        #expect(SessionCues.chain(r, name: "daily") == "daily · step 2 of 2")
        #expect(SessionCues.chain(r, name: nil) == "Chain · step 2 of 2")
        #expect(SessionCues.step(r) == "codex · default model")
        #expect(SessionCues.chain(SessionRoute(account: 3), name: nil) == nil)
    }

    @Test func waitingSaysWhenItTriesAgain() {
        let w = SessionWaiting(
            since: now.addingTimeInterval(-300), until: now.addingTimeInterval(600),
            why: "every account the chain can use is cooling, limited or at its cap")
        let t = SessionCues.waiting(w, now: now, calendar: utc, locale: Locale(identifier: "en_GB"))
        #expect(t.title == "Waiting for an account")
        #expect(
            t.text.hasPrefix(
                "Every account the chain can use is cooling, limited or at its cap. It tries again from 21:30."))
        #expect(t.text.hasSuffix("It has waited since 21:15."))
    }

    @Test func movedNamesTheCauseInWords() {
        let left = SessionRoute(attempt: 0, failedOverTo: "as_01JC4X7Q3MZ8N5V2K9R012", failoverClass: "rate_limited")
        #expect(SessionCues.moved(left)?.text.contains("hit a rate limit") == true)
        #expect(SessionCues.moved(left)?.text.contains("…K9R012") == true)
        let took = SessionRoute(attempt: 1, failoverOf: "as_x")
        #expect(SessionCues.moved(took)?.title == "Moved here from another account")
        #expect(SessionCues.moved(took)?.text.contains("attempt 2") == true)
        #expect(SessionCues.moved(SessionRoute()) == nil)
        #expect(SessionCues.reason("budget_pool") == "reached its budget")
        #expect(SessionCues.reason("zzz") == "had a problem")
    }

    @Test func aRunThatCouldNotMoveSaysWhy() {
        let e = FailoverEnd(result: "ended", why: "no account is available", reasons: ["entry 1: cooling until 14:00"])
        let t = SessionCues.notMoved(e)
        #expect(t?.text == "No account is available. Chain step 1: cooling until 14:00.")
        #expect(SessionCues.notMoved(FailoverEnd(result: "moved")) == nil)
    }

    @Test func upstreamAndRepickedAreSentences() {
        #expect(SessionCues.upstream("ok") == nil && SessionCues.upstream(nil) == nil)
        #expect(SessionCues.upstream("quota") == "This account is out of quota.")
        #expect(SessionCues.upstream("weird") == "The provider reported a problem.")
        #expect(SessionCues.repicked(0) == nil && SessionCues.repicked(1)?.hasPrefix("One account") == true)
        #expect(SessionCues.repicked(2) == "2 accounts refused to start before this one did.")
    }

    @Test func budgetStopReadsAsOne() {
        func s(_ o: SessionOutcome?, _ why: String? = nil) -> AgentSessionInfo {
            AgentSessionInfo(
                id: "as_1", runner: "d_1", harness: "claude", state: .ended, outcome: o, outcomeReason: why,
                createdAt: now, updatedAt: now)
        }
        #expect(s(SessionOutcome(rawValue: "budget")).stoppedByBudget)
        #expect(s(.cancelled, "The pool Budget ran out").stoppedByBudget)
        #expect(!s(.cancelled, "asked to stop").stoppedByBudget)
        #expect(!s(.tokenCap).stoppedByBudget)
        #expect(AgentWords.status(s(.cancelled, "budget"), waiting: false).label == "Ended: budget reached")
        #expect(AgentWords.status(s(.cancelled), waiting: false).label == "Cancelled")
    }

    @Test func attemptLineSaysWhatHappened() {
        var moved = AgentSessionInfo(
            id: "as_1", runner: "d", harness: "claude", state: .ended, outcome: .cancelled, createdAt: now,
            updatedAt: now, route: SessionRoute(attempt: 0, failedOverTo: "as_2", failoverClass: "quota"))
        #expect(SessionCues.attempt(moved) == "Attempt 1 · claude · moved on: ran out of quota")
        moved.route = SessionRoute(attempt: 1, failoverOf: "as_1")
        moved.state = .running
        moved.outcome = nil
        #expect(SessionCues.attempt(moved) == "Attempt 2 · claude · working now")
    }
}
