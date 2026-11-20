import CoreKit
import Foundation
import Testing

@testable import Accounts

@MainActor
struct ProviderLimitsTests {
    func make() async -> (AccountsModel, FakeService) {
        let model = AccountsModel(host: FakeHost())
        let svc = FakeService()
        svc.orderOn = true
        svc.accountList = [
            account(1, "main", provider: "claude-sub"), account(2, "key", provider: "anthropic"),
            account(3, "second", provider: "claude-sub"), account(4, "router", provider: "openrouter"),
        ]
        model.use(svc)
        await model.reload()
        return (model, svc)
    }

    @Test func thePickerListsEachProviderOfTheOrderOnceInOrder() async {
        let (m, _) = await make()
        #expect(m.limitProviders == ["claude-sub", "anthropic", "openrouter"])
        #expect(
            m.limitOptions.map(\.value) == [.provider("claude-sub"), .provider("anthropic"), .provider("openrouter")])
        #expect(m.limitTarget == .provider("claude-sub"), "the first provider until one is picked")
        #expect(AccountLimitRules.providers(of: []).isEmpty)
    }

    @Test func limitsOpenedFromARowKeepThatAccountsRowsAsTheFirstChoice() async {
        let (m, _) = await make()
        m.limitsTarget = .account(2)
        #expect(m.limitTarget == .account(2))
        #expect(m.limitOptions.first?.value == .account(2))
        #expect(m.limitOptions.count == 4)
        m.limitsTarget = .account(99)
        #expect(m.limitTarget == .provider("claude-sub"), "an account that is gone falls back to a provider")
    }

    @Test func aProviderLimitIsABudgetOfKindProviderWithAMessageCap() async {
        let (m, svc) = await make()
        let d = AccountLimitRules.draft(target: .provider("anthropic"), period: "week", messages: 900, warn: 80)
        #expect(d.kind == "provider" && d.subject == "anthropic" && d.messageCap == 900 && d.hardStop)
        #expect(await m.saveBudget(d, editing: false))
        #expect(svc.log.contains("setBudget provider anthropic week 0 msgs=900"))
    }

    @Test func rowsOfOneTargetNeverShowAnotherTargetsBudgets() {
        func b(_ id: Int64, _ kind: String, _ subject: String, _ period: String) -> BudgetItem {
            BudgetItem(
                id: id, kind: kind, subject: subject, company: nil, period: period, periodKey: "k", tokenCap: 0,
                usdCap: nil, spent: 0, usdSpent: 0, held: 0, raised: 0, raisedUSD: 0, warnAt: 80, hardStop: true,
                exhausted: false, messageCap: 50, messages: 1)
        }
        let all = [
            b(1, "provider", "anthropic", "week"), b(2, "provider", "anthropic", "hour5"),
            b(3, "account", "2", "day"), b(4, "provider", "openrouter", "day"),
        ]
        #expect(AccountLimitRules.rows(all, target: .provider("anthropic")).map(\.id) == [2, 1])
        #expect(AccountLimitRules.rows(all, target: .account(2)).map(\.id) == [3])
        #expect(AccountLimitRules.rows(all, account: 2).map(\.id) == [3])
    }
}

@MainActor
struct RemoveWithUndoTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func make() async -> (AccountsModel, FakeService) {
        let model = AccountsModel(host: FakeHost())
        let svc = FakeService()
        svc.orderOn = true
        svc.accountList = [account(1, "a"), account(2, "b", provider: "openrouter"), account(3, "c")]
        svc.orderEntries = svc.accountList.map { AIOrderEntry(account: $0.id, provider: nil, harness: nil, model: nil) }
        svc.undoUntil = t0.addingTimeInterval(10)
        model.now = { [t0] in t0 }
        model.use(svc)
        await model.reload()
        return (model, svc)
    }

    @Test func removeIsAtOnceThenUndoPutsTheRowBackInItsOldPlace() async {
        let (m, svc) = await make()
        #expect(m.orderIDs == [1, 2, 3])
        #expect(await m.removeWithUndo(m.account(2)!))
        #expect(m.orderIDs == [1, 3])
        #expect(m.removed?.index == 1 && m.removed?.until == t0.addingTimeInterval(10))
        #expect(svc.log.contains("removeAccount 2"))
        #expect(!svc.log.contains("deleteAccount 2"), "no confirmation path, no hard delete")
        #expect(m.host.shell.toast?.message == "OpenRouter removed")

        await m.undoRemoval(2)
        #expect(svc.log.contains("restoreAccount 2"))
        #expect(m.orderIDs == [1, 2, 3], "the Core seats it last; the app moves it back")
        #expect(svc.log.contains("setAIOrder - 1,2,3"))
        #expect(m.removed == nil)
    }

    @Test func undoAfterTheWindowIsToldNotTried() async {
        let (m, svc) = await make()
        await m.removeWithUndo(m.account(2)!)
        m.now = { [t0] in t0.addingTimeInterval(10.5) }
        await m.undoRemoval(2)
        #expect(!svc.log.contains("restoreAccount 2"))
        #expect(m.removed == nil)
        #expect(m.orderIDs == [1, 3])
    }

    @Test func placedClampsAndKeepsTheOthersInOrder() {
        #expect(AccountsModel.placed([1, 3, 2], id: 2, at: 1) == [1, 2, 3])
        #expect(AccountsModel.placed([1, 3], id: 2, at: 9) == [1, 3, 2])
        #expect(AccountsModel.placed([1, 3], id: 2, at: -4) == [2, 1, 3])
    }

    @Test func aCoreThatSeatsItBackInPlaceNeedsNoSecondWrite() {
        #expect(AccountsModel.placed([1, 2, 3], id: 2, at: 1) == [1, 2, 3])
    }
}
