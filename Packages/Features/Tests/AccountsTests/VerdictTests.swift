import Foundation
import Testing

@testable import Accounts

struct VerdictTests {
    func limit(used: Int64, cap: Int64 = 100, exhausted: Bool = false) -> LimitItem {
        LimitItem(unit: "tokens", windowSecs: 86_400, cap: cap, used: used, warnPercent: 80, exhausted: exhausted)
    }
    func budget(spent: Int64, hardStop: Bool = true, subject: String = "1") -> BudgetItem {
        BudgetItem(
            id: 1, kind: "account", subject: subject, company: nil, period: "month", periodKey: "2026-11",
            tokenCap: 100,
            usdCap: nil, spent: spent, usdSpent: 0, held: 0, raised: 0, raisedUSD: 0, warnAt: 80, hardStop: hardStop,
            exhausted: false)
    }
    func test(_ r: String, _ a: AccountItem) -> AccountItem {
        var a = a
        a.lastTest = (Date(), r)
        return a
    }

    @Test func aPlainActiveAccountInAPoolIsReady() {
        let v = AccountVerdict.of(account(1, "a"))
        #expect(v.isReady && v.usable && v.label == "Ready" && v.cause == nil)
        #expect(AccountVerdict.of(account(1, "a"), inPool: false).kind == .noPool)
    }

    @Test func anAccountAtALimitIsNeverReady() {
        let v = AccountVerdict.of(account(1, "a"), limits: [limit(used: 100)])
        #expect(v.kind == .limitReached && !v.isReady && v.tone == .fail && v.cause == .limits)
        #expect(AccountVerdict.of(account(1, "a"), limits: [limit(used: 5, exhausted: true)]).kind == .limitReached)
        #expect(AccountVerdict.of(account(1, "a"), limits: [limit(used: 90)]).kind == .limitNear)
    }

    @Test func aRefusedKeyIsNeverReady() {
        let v = AccountVerdict.of(test("auth_failed", account(1, "a")))
        #expect(v.kind == .keyRefused && !v.usable && v.cause == .keyTest)
        #expect(AccountVerdict.of(test("ok", account(1, "a"))).isReady)
    }

    @Test func budgetsAreReadForTheirOwnAccountOnly() {
        #expect(AccountVerdict.of(account(1, "a"), budgets: [budget(spent: 100)]).kind == .budgetStopped)
        #expect(AccountVerdict.of(account(1, "a"), budgets: [budget(spent: 100, hardStop: false)]).kind == .budgetNear)
        #expect(AccountVerdict.of(account(1, "a"), budgets: [budget(spent: 85)]).kind == .budgetNear)
        #expect(AccountVerdict.of(account(1, "a"), budgets: [budget(spent: 100, subject: "2")]).isReady)
    }

    @Test func worstCauseWinsAndStatesAreCovered() {
        let both = AccountVerdict.of(
            test("auth_failed", account(1, "a")), limits: [limit(used: 100)], budgets: [budget(spent: 100)])
        #expect(both.kind == .keyRefused)
        #expect(AccountVerdict.of(account(1, "a", state: "disabled"), limits: [limit(used: 100)]).kind == .turnedOff)
        #expect(AccountVerdict.of(account(1, "a", state: "unhealthy")).tone == .fail)
        #expect(AccountVerdict.of(account(1, "a", state: "cooling")).kind == .resting)
        #expect(AccountVerdict.of(account(1, "a", state: "cooling"), limits: [limit(used: 100)]).kind == .limitReached)
        #expect(AccountVerdict.of(account(1, "a", state: "limited")).kind == .limited)
        #expect(AccountVerdict.of(account(1, "a", state: "weird")).label == "weird")
        #expect(!AccountVerdict.of(account(1, "a", state: "disabled")).needsLook)
    }

    @MainActor @Test func cardsAndCountsUseTheSameVerdict() async {
        let m = AccountsModel(host: FakeHost())
        let svc = FakeService()
        svc.accountList = [test("auth_failed", account(1, "refused")), account(2, "fine")]
        svc.poolList = [pool(1, "main", def: true, members: [1, 2])]
        m.use(svc)
        await m.reload()
        #expect(m.readyCount == 1)
        #expect(m.needLook.map(\.label) == ["refused"])
        #expect(m.firstReady(in: m.pools[0])?.label == "fine")
    }

    @Test func numbersAreGroupedAndWordedAndParsedBack() {
        #expect(AccountsNumbers.tokens(2_000_000) == "2\u{00A0}million tokens")
        #expect(
            AccountsNumbers.tokens(328_000) == "328,000\u{00A0}tokens"
                || AccountsNumbers.tokens(328_000).contains("328"))
        #expect(AccountsNumbers.parseWhole(AccountsNumbers.grouped(80_000_000)) == 80_000_000)
        #expect(AccountsNumbers.parseWhole("80 000 000") == 80_000_000)
        #expect(AccountsNumbers.parseDecimal("2.50") == 2.5)
        #expect(AccountsNumbers.parseDecimal(AccountsNumbers.dollarsField(2_500_000)) == 2.5)
    }
}
