import Testing

@testable import Accounts

struct MonthSpendTests {
    @Test func theAccountsOwnFiguresWin() {
        var a = account(1, "Work")
        a.monthSpendUSDMicros = 12_000_000
        a.monthLimitUSDMicros = 20_000_000
        let m = MonthSpend.of(a, budget: nil)
        #expect(m == MonthSpend(spent: 12_000_000, cap: 20_000_000))
        #expect(m?.share == 0.6 && m?.low == false)
        #expect(MonthSpend(spent: 18_000_000, cap: 20_000_000).low)
    }

    @Test func noFiguresNoBarUntilThereIsACap() {
        let a = account(1, "Work")
        #expect(MonthSpend.of(a, budget: nil) == nil)
        var b = a
        b.monthLimitUSDMicros = 5_000_000
        #expect(MonthSpend.of(b, budget: nil) == MonthSpend(spent: 0, cap: 5_000_000))
    }

    @Test func totalAddsWhatAccountsReport() {
        var a = account(1, "A")
        var b = account(2, "B")
        #expect(MonthSpend.total([a, b]) == nil)
        a.monthSpendUSDMicros = 1_000_000
        a.monthLimitUSDMicros = 4_000_000
        b.monthSpendUSDMicros = 2_000_000
        #expect(MonthSpend.total([a, b]) == MonthSpend(spent: 3_000_000, cap: 4_000_000))
    }
}
