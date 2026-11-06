import CoreKit
import Foundation
import Testing

@testable import Accounts

@MainActor
struct ModelTests {
    func make() async -> (AccountsModel, FakeService, FakeHost) {
        let host = FakeHost()
        let model = AccountsModel(host: host)
        let svc = FakeService()
        svc.accountList = [
            account(1, "claude-main"), account(2, "claude-spare", state: "cooling"),
            account(3, "old", state: "disabled"),
        ]
        svc.poolList = [pool(1, "Default", def: true, members: [1, 2]), pool(2, "Client", members: [])]
        svc.bindingList = [BindingItem(agent: "atlas", provider: "anthropic", poolID: 2)]
        model.use(svc)
        await model.reload()
        return (model, svc, host)
    }

    @Test func loadsEverythingAndDerivesTheViews() async {
        let (m, _, _) = await make()
        #expect(m.load == .ready)
        #expect(m.readyCount == 1)
        #expect(m.needLook.map(\.label) == ["claude-spare"])
        #expect(m.firstReady(in: m.pools[0])?.label == "claude-main")
        #expect(m.candidates(for: m.pools[1]).count == 3)
        #expect(m.bindings(of: m.pools[1]).map(\.agent) == ["atlas"])
    }

    @Test func testingAKeyNeedsNoTouchIDAndSaysWhyWhenRefused() async {
        let (m, svc, host) = await make()
        await m.test(m.account(1)!)
        #expect(svc.log.contains("test 1"))
        #expect(host.reasons.isEmpty)
        #expect(m.testing == nil && m.testNote[1] == nil)
        svc.failure = CoreError.http(status: 409, code: "no_runner", message: "none")
        await m.test(m.account(1)!)
        #expect(m.testNote[1]?.hasPrefix("No runner is online") == true)
    }

    @Test func sessionLimitsGoBehindTouchIDAndClearWithNil() async {
        let (m, svc, host) = await make()
        #expect(await m.setLimits(m.account(1)!, tokens: 500_000, usdMicros: nil))
        #expect(svc.log.contains("setSessionLimits 1 500000 nil"))
        #expect(host.reasons.count == 1)
        #expect(LimitWords.usd(2_500_000) == "$2.50")
        #expect(LimitWords.tokens(nil) == "no token limit")
    }

    @Test func anExpiredSignInEndsInsteadOfWaitingForever() async {
        let (m, svc, _) = await make()
        svc.loginItem = LoginItem(
            id: "lg", provider: "claude-sub", label: "plan", runner: "r", state: "expired", url: nil, reason: "expired",
            accountID: nil)
        await m.startSignIn(provider: "claude-sub", label: "plan")
        guard case .failed(let why)? = m.signIn?.stage else {
            Issue.record("still \(String(describing: m.signIn?.stage))")
            return
        }
        #expect(why.hasPrefix("Nothing happened for 10 minutes"))
    }

    @Test func budgetStandingCountsWhatWasRaisedAndTheHardStop() {
        func b(
            cap: Int64, usd: Int64?, spent: Int64, usdSpent: Int64, raised: Int64 = 0, stop: Bool = true,
            ex: Bool = false
        )
            -> BudgetItem
        {
            BudgetItem(
                id: 1, kind: "account", subject: "1", company: nil, period: "day", periodKey: "2026-11-06",
                tokenCap: cap, usdCap: usd, spent: spent, usdSpent: usdSpent, held: 0, raised: raised, raisedUSD: 0,
                warnAt: 80, hardStop: stop, exhausted: ex)
        }
        #expect(b(cap: 100, usd: nil, spent: 10, usdSpent: 0).standing == .fine)
        #expect(b(cap: 100, usd: nil, spent: 85, usdSpent: 0).standing == .warning)
        #expect(b(cap: 100, usd: nil, spent: 100, usdSpent: 0, raised: 100).standing == .fine)
        #expect(b(cap: 0, usd: 10, spent: 999, usdSpent: 10, ex: true).standing == .stopped)
        #expect(b(cap: 0, usd: 10, spent: 0, usdSpent: 10, stop: false, ex: true).standing == .over)
        #expect(b(cap: 0, usd: 10, spent: 999, usdSpent: 1).tokenShare == nil)
    }

    @Test func raisingABudgetNamesItsPeriodAndAsksForTouchID() async {
        let (m, svc, host) = await make()
        let budget = BudgetItem(
            id: 7, kind: "account", subject: "1", company: nil, period: "day", periodKey: "2026-11-06", tokenCap: 0,
            usdCap: 1_000_000, spent: 0, usdSpent: 1_000_000, held: 0, raised: 0, raisedUSD: 0, warnAt: 80,
            hardStop: true, exhausted: true)
        #expect(m.budgetName(budget) == "claude-main")
        #expect(await m.raiseBudget(budget, tokens: nil, usdMicros: 500_000))
        #expect(svc.log.contains("raiseBudget 7 2026-11-06 0 500000"))
        #expect(host.reasons.count == 1)
    }

    @Test func modelIdsMustBeExactAndUnpricedTokensAreCounted() async {
        #expect(CostWords.modelIssue("claude-sonnet-4-5") == nil)
        #expect(CostWords.modelIssue("claude-latest-latest") != nil)
        #expect(CostWords.modelIssue("x/y:online") != nil)
        #expect(CostWords.modelIssue("two words") != nil)
        let (m, svc, host) = await make()
        svc.costList = [
            CostItem(
                id: 1, at: Date(), accountID: 1, provider: "anthropic", model: "m", session: "s", input: 10, output: 5,
                cache: 0, costMicros: nil, basis: "unpriced", approximate: false),
            CostItem(
                id: 2, at: Date(), accountID: 1, provider: "anthropic", model: "m", session: "s", input: 100, output: 0,
                cache: 0, costMicros: 9, basis: "list_price", approximate: false),
        ]
        await m.reloadCosts()
        #expect(m.costsLoad == .ready && m.unpricedTokens == 15)
        #expect(
            await m.savePrice(
                PriceDraft(provider: "anthropic", model: "m", input: 3, output: 15, cache: 0, pricedAt: Date())))
        #expect(svc.log.contains("setPrice anthropic m 3 15 0"))
        #expect(host.reasons.count == 1)
    }

    @Test func providerRulesMatchCores() async {
        #expect(ProviderRules.id(from: "OpenRouter EU") == "openrouter-eu")
        #expect(ProviderRules.id(from: "42 Labs") == "labs")
        #expect(ProviderRules.urlIssue("https://openrouter.ai/api") == nil)
        #expect(ProviderRules.urlIssue("https://openrouter.ai:443/api") == nil)
        #expect(ProviderRules.urlIssue("http://openrouter.ai") != nil)
        #expect(ProviderRules.urlIssue("https://openrouter.ai:8443") != nil)
        #expect(ProviderRules.urlIssue("https://10.0.0.1") != nil)
        #expect(ProviderRules.urlIssue("https://xn--e1afmkfd.xn--p1ai") != nil)
        #expect(ProviderRules.urlIssue("https://localhost") != nil)
        #expect(ProviderRules.urlIssue("https://user@openrouter.ai") != nil)
        #expect(ProviderRules.prefixIssue("sk-or-v1-") == nil)
        #expect(ProviderRules.prefixIssue("sk-") != nil)
        #expect(ProviderRules.testPathIssue("/key") == nil)
        #expect(ProviderRules.testPathIssue("/../x") != nil)
        let (m, svc, host) = await make()
        let d = ProviderDraft(
            id: "openrouter", name: "OpenRouter", harness: "codex", baseURL: "https://openrouter.ai/api",
            keyPrefix: "sk-or-v1-", testPath: nil, models: [])
        #expect(await m.saveProvider(d, replacing: false))
        #expect(svc.log.contains("saveProvider openrouter codex OPENAI_API_KEY sk-or-v1- false"))
        #expect(host.reasons.count == 1)
    }

    @Test func stateWordsKeepUnknownRawAndNeverAlarm() {
        #expect(AccountPhase("active").label == "Ready")
        #expect(AccountPhase("weird").label == "weird")
        #expect(!AccountPhase("weird").needsLook)
        #expect(AccountPhase("unhealthy").needsLook)
    }

    @Test func gateStatesAreHonest() {
        #expect(GateState(mode: 0, providerAccounts: 0).kind == .off)
        #expect(GateState(mode: 1, providerAccounts: 0).kind == .throwaway)
        #expect(GateState(mode: 1, providerAccounts: 1).kind == .real)
        #expect(GateState(mode: 2, providerAccounts: 1).kind == .other)
        #expect(GateState(mode: nil, providerAccounts: 1).kind == .unknown)
    }

    @Test func createAndDeletePoolAskForTouchID() async {
        let (m, svc, host) = await make()
        #expect(await m.createPool(name: " Research ", provider: "anthropic"))
        #expect(svc.log.contains("createPool Research anthropic"))
        #expect(m.pools.contains { $0.name == "Research" })
        #expect(m.selectedPool?.name == "Research")
        let made = m.pools.first { $0.name == "Research" }!
        #expect(await m.delete(made))
        #expect(!m.pools.contains { $0.name == "Research" })
        #expect(host.reasons.count == 2)
    }

    @Test func aDeclinedTouchIDChangesNothingAndSaysNoError() async {
        let (m, svc, host) = await make()
        host.declines = true
        #expect(await m.createPool(name: "X", provider: "anthropic") == false)
        #expect(svc.log.isEmpty)
        #expect(m.writeError["new-pool"] == nil)
    }

    @Test func aRefusalIsKeptInWordsWithItsCode() async {
        let (m, svc, _) = await make()
        svc.failure = CoreError.http(status: 409, code: "conflict", message: "The default pool cannot be deleted.")
        #expect(await m.delete(m.pools[0]) == false)
        #expect(m.writeError["delete-pool-1"] == "The default pool cannot be deleted. (conflict)")
        #expect(m.readOnly == false)
    }

    @Test func forbiddenScopeMakesTheDeviceReadOnly() async {
        let (m, svc, _) = await make()
        svc.failure = CoreError.forbiddenScope
        #expect(await m.createPool(name: "X", provider: "anthropic") == false)
        #expect(m.readOnly)
    }

    @Test func membersAreAppendedAndRemovedWithUndo() async {
        let (m, svc, _) = await make()
        let client = m.pools[1]
        #expect(await m.add(m.account(1)!, to: client))
        #expect(m.pool(2)?.members == [1])
        await m.remove(m.account(1)!, from: m.pool(2)!)
        #expect(m.pool(2)?.members == [])
        m.host.shell.toast?.undo?()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(m.pool(2)?.members == [1])
        #expect(svc.log.filter { $0.hasPrefix("add 2 1") }.count == 2)
    }

    @Test func bindingValidatesAgentIdsAndRebinds() async {
        #expect(AccountsModel.validAgent("agent-1.a:b_c"))
        #expect(!AccountsModel.validAgent(""))
        #expect(!AccountsModel.validAgent("has space"))
        #expect(!AccountsModel.validAgent(String(repeating: "a", count: 65)))
        let (m, _, _) = await make()
        #expect(await m.bind(agent: "atlas", to: m.pool(1)!))
        #expect(m.bindings.map(\.poolID) == [1])
        await m.unbind(m.bindings[0])
        #expect(m.bindings.isEmpty)
    }

    @Test func turnOffAndCapAndDelete() async {
        let (m, svc, _) = await make()
        await m.setEnabled(m.account(1)!, false)
        #expect(m.account(1)?.phase == .disabled)
        #expect(await m.setCap(m.account(1)!, 0))
        #expect(m.account(1)?.cap == 0)
        #expect(await m.delete(m.account(2)!))
        #expect(m.account(2) == nil)
        #expect(m.pool(1)?.members == [1])
        #expect(svc.log.contains("deleteAccount 2"))
    }

    @Test func offlineHostPausesWrites() async {
        let (m, svc, host) = await make()
        host.pausedReason = "offline"
        #expect(await m.createPool(name: "X", provider: "anthropic") == false)
        #expect(svc.log.isEmpty)
        #expect(host.shell.toast?.message == "offline")
    }

    @Test func connectOpensOnlyTheProvidersPage() async {
        let (m, _, _) = await make()
        var opened: [URL] = []
        m.opener = { opened.append($0) }
        m.openProviderPage("anthropic")
        m.openProviderPage("custom")
        #expect(opened.map(\.host) == ["console.anthropic.com"])
    }

    @Test func failedLoadShowsTheCoresWords() async {
        let host = FakeHost()
        let m = AccountsModel(host: host)
        let svc = FakeService()
        svc.failure = nil
        m.use(svc)
        await m.reload()
        #expect(m.state(for: CoreError.forbiddenScope) == .forbidden)
        #expect(
            m.state(for: CoreError.offline("down"))
                == .failed(code: "offline", message: "The Core cannot be reached: down"))
    }

    @Test func aPoolNameFollowsTheCoresRule() {
        #expect(PoolName.isValid("client-work") && PoolName.isValid("e5-08.test_2"))
        #expect(!PoolName.isValid("Client work") && !PoolName.isValid("2fast") && !PoolName.isValid(""))
        #expect(!PoolName.isValid(String(repeating: "a", count: 65)))
    }
}
