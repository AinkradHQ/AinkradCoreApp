import Foundation
import Testing

@testable import Accounts

struct HealthTests {
    var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    let now = Date(timeIntervalSince1970: 1_794_000_000)  // 21:20 UTC

    @Test func healthyIsWorking() {
        let l = AccountHealthWords.line(AccountHealthItem(lastSuccessAt: now.addingTimeInterval(-180)), now: now)
        #expect(l.text == "Working" && l.help == "Last went well 3 min ago")
        #expect(AccountHealthWords.line(AccountHealthItem(), now: now).text == "Not used yet")
    }

    @Test func streaksAreCountedInWords() {
        #expect(AccountHealthWords.line(AccountHealthItem(failStreak: 3), now: now).text == "Failing, 3 in a row")
        let a = AccountHealthWords.line(AccountHealthItem(failStreak: 3, authStreak: 2), now: now)
        #expect(a.text == "Sign-in failing, 2 in a row")  // a sign-in problem is the one to act on
        #expect(a.help.contains("auth_streak 2"))  // the code lives in the hover help only
        #expect(!a.text.contains("_"))
    }

    @Test func aRejectedPlanWaitsForTheLimitToReset() {
        let h = AccountHealthItem(
            planStatus: "rejected",
            windows: [
                PlanWindowItem(name: "five_hour", utilization: 1.02, resetsAt: now.addingTimeInterval(1_800)),
                PlanWindowItem(name: "seven_day", utilization: 0.4, resetsAt: now.addingTimeInterval(86_400 * 3)),
            ])
        #expect(
            AccountHealthWords.line(h, now: now, calendar: utc).text == "Waiting for a limit to reset until 21:50")
        #expect(
            AccountHealthWords.line(AccountHealthItem(planStatus: "rejected"), now: now).text
                == "Waiting for a limit to reset")
    }

    @Test func aWarningNamesTheBusiestWindow() {
        let h = AccountHealthItem(
            planStatus: "allowed_warning",
            windows: [PlanWindowItem(name: "seven_day", utilization: 0.87, resetsAt: nil)])
        #expect(AccountHealthWords.line(h, now: now).text == "Close to its 7-day limit, 87% used")
        #expect(AccountHealthWords.line(AccountHealthItem(upstreamClass: "rate_limited"), now: now).tone == .warn)
        #expect(
            AccountHealthWords.line(AccountHealthItem(lastSuccessAt: now, upstreamClass: "ok"), now: now).text
                == "Working")
    }

    @Test func liveCountReadsAsWords() {
        #expect(AccountHealthWords.live(nil) == nil)
        #expect(AccountHealthWords.live(0) == "No sessions now")
        #expect(AccountHealthWords.live(1) == "1 session now")
        #expect(AccountHealthWords.live(4) == "4 sessions now")
    }
}
