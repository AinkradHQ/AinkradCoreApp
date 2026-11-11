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

    @Test func theBannerCountsTheAccountsThatNeedALook() {
        #expect(AccountsBannerWords.headline(need: 1) == "1 account needs a look.")
        #expect(AccountsBannerWords.headline(need: 3) == "3 accounts need a look.")
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
        #expect(AccountVerdict.of(account(1, "a"), budgets: [budget(spent: 100, hardStop: false)]).kind == .budgetOver)
        #expect(
            AccountVerdict.of(account(1, "a"), budgets: [budget(spent: 100, hardStop: false)]).label == "Over budget")
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
        let en = Locale(identifier: "en_US")
        let de = Locale(identifier: "de_DE")
        func p(_ s: String, _ l: Locale) -> Double? { AccountsNumbers.parseDecimal(s, locale: l) }
        #expect(p("2,50", en) == 2.5 && p("2.50", en) == 2.5 && p("1,234.50", en) == 1234.5)
        #expect(p("2,50", de) == 2.5 && p("2.50", de) == 2.5 && p("1.234,50", de) == 1234.5)
        #expect(p("2.500", en) == 2.5 && p("2.500", de) == 2500 && p("1,234", en) == 1234 && p("1,234", de) == 1.234)
        #expect(p("1,234,567", en) == 1_234_567 && p("1.234.567", de) == 1_234_567)
        #expect(p("1.2.3", en) == nil && p("1,2,3", de) == nil && p("2.50,3", de) == nil && p("1,23.4", en) == nil)
        #expect(p("12", en) == 12 && p("abc", en) == nil && p("", en) == nil && p("nan", en) == nil)
        #expect(AccountsNumbers.parseDecimal(AccountsNumbers.dollarsField(2_500_000)) == 2.5)
    }
}
