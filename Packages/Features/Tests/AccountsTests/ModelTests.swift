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
        svc.chainList = [
            ChainItem(
                id: 1, name: "daily", isDefault: true,
                entries: [ChainEntryItem(pool: 1, provider: "anthropic", harness: "claude", model: nil)]),
            ChainItem(
                id: 2, name: "careful", isDefault: false,
                entries: [ChainEntryItem(pool: 2, provider: "anthropic", harness: "claude", model: "claude-opus")]),
        ]
        svc.chainBindingList = [ChainBindingItem(agent: "atlas", chain: 2)]
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
        #expect(m.chains(using: m.pools[1]).map(\.name) == ["careful"])
        #expect(m.agents(of: m.chains[1]).map(\.agent) == ["atlas"])
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

    @Test func closingTheDialogByAnyRouteStopsARunningSignIn() async {
        let (m, svc, _) = await make()
        m.signIn = SignInFlow(stage: .working, login: "lg", label: "plan")
        m.dialogClosed()
        for _ in 0..<50 where m.signIn != nil { await Task.yield() }
        #expect(m.signIn == nil)
        #expect(svc.log.contains("cancelLogin lg"))
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

    @Test func quickPoolMakesAnEmptyPoolWithGeneratedNameAndSelectsIt() async {
        let (m, svc, host) = await make()
        #expect(m.nextPoolName() == "pool-3")
        #expect(PoolName.isValid(m.nextPoolName()))
        await m.quickPool()
        #expect(svc.log == ["createPool pool-3 anthropic"])
        #expect(m.selectedPool?.name == "pool-3" && m.selectedPool?.members.isEmpty == true)
        #expect(host.reasons.count == 1 && host.shell.dialog == nil)
        // The next one is free again.
        #expect(m.nextPoolName() == "pool-4")
    }

    @Test func quickPoolOpensTheSheetWithTheReasonWhenItCannot() async {
        let (m, svc, host) = await make()
        svc.failure = CoreError.http(status: 409, code: "conflict", message: "That name is taken.")
        await m.quickPool()
        #expect(host.shell.dialog?.id == "pool-new")
        #expect(m.writeError["new-pool"] == "That name is taken. (conflict)")
        // No provider at all: no write is tried.
        let (n, s2, h2) = await make()
        s2.providerList = []
        await n.reload()
        await n.quickPool()
        #expect(s2.log.isEmpty && h2.shell.dialog?.id == "pool-new")
        #expect(n.writeError["new-pool"] == "No provider yet. Connect an account first.")
    }

    @Test func quickPoolWithADeclinedTouchIDChangesNothingAndOpensNothing() async {
        let (m, svc, host) = await make()
        host.declines = true
        await m.quickPool()
        #expect(svc.log.isEmpty && host.shell.dialog == nil)
    }

    @Test func aPoolEntryPairInTheLauncher() async {
        let (m, _, host) = await make()
        m.install()
        #expect(host.shell.launcher.entry("new-pool")?.isAction == true)
        #expect(host.shell.launcher.entry("new-pool-advanced")?.title == "New pool (advanced)…")
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
        let (m, svc, _) = await make()
        #expect(await m.bind(agent: "atlas", to: m.chain(1)!))
        #expect(m.chainBindings.map(\.chain) == [1])
        await m.unbind("atlas")
        #expect(m.chainBindings.isEmpty)
        #expect(svc.log.contains("bindAgent atlas 1") && svc.log.contains("unbindAgent atlas"))
    }

    @Test func chainsLoadAndNeverCallTheDeprecatedBindings() async {
        let (m, _, _) = await make()
        #expect(m.chains.map(\.name) == ["daily", "careful"])
        #expect(m.selectedChain?.name == "daily")
        #expect(m.chainsAllowed)
    }

    @Test func aDeviceWithoutAdminSeesNoChainsAndTheRestStillLoads() async {
        let host = FakeHost()
        let m = AccountsModel(host: host)
        let svc = FakeService()
        svc.poolList = [pool(1, "Default", def: true)]
        svc.chainsFailure = CoreError.forbiddenScope
        m.use(svc)
        await m.reload()
        #expect(m.load == .ready)
        #expect(!m.chainsAllowed && m.chains.isEmpty && m.chainBindings.isEmpty)
        #expect(m.pools.count == 1)
    }

    @Test func creatingAndEditingAChainAsksForTouchID() async {
        let (m, svc, host) = await make()
        let two = [ChainEntryDraft(pool: 1, model: "m1"), ChainEntryDraft(pool: 2, model: nil)]
        #expect(await m.createChain(name: " work ", entries: two))
        #expect(svc.log.contains("createChain work 1:m1,2:-"))
        #expect(host.reasons.last?.contains("work") == true)
        let work = m.chains.first { $0.name == "work" }!
        #expect(m.chainSelection == work.id)
        #expect(await m.replace(work, name: "work2", entries: [ChainEntryDraft(pool: 2, model: nil)]))
        #expect(m.chains.first { $0.id == work.id }?.entries.count == 1)
        host.declines = true
        #expect(!(await m.createChain(name: "nope", entries: [ChainEntryDraft(pool: 1, model: nil)])))
        #expect(!m.chains.contains { $0.name == "nope" })
    }

    @Test func settingTheDefaultDeletingAndTheCoreRefusing() async {
        let (m, svc, _) = await make()
        await m.makeDefault(m.chain(2)!)
        #expect(m.chains.first { $0.isDefault }?.id == 2)
        m.host.shell.toast?.undo?()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(m.chains.first { $0.isDefault }?.id == 1)
        #expect(await m.delete(m.chain(2)!))
        #expect(m.chainBindings.isEmpty)
        svc.failure = CoreError.http(status: 409, code: "conflict", message: "pool in use")
        #expect(!(await m.createChain(name: "x", entries: [ChainEntryDraft(pool: 1, model: nil)])))
        #expect(m.writeError["chain"]?.contains("conflict") == true)
    }

    @Test func chainRulesCheckNameCountAndDuplicates() {
        let one = [ChainEntryDraft(pool: 1, model: nil)]
        #expect(ChainRules.issue(name: "daily", entries: one) == nil)
        #expect(ChainRules.issue(name: "Daily", entries: one) != nil)
        #expect(ChainRules.issue(name: "daily", entries: []) != nil)
        func pools(_ n: Int) -> [ChainEntryDraft] { (1...n).map { ChainEntryDraft(pool: Int64($0), model: nil) } }
        #expect(ChainRules.issue(name: "daily", entries: pools(5)) != nil)
        #expect(ChainRules.issue(name: "daily", entries: one + one) != nil)
        #expect(ChainRules.issue(name: "daily", entries: pools(4)) == nil)
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

struct RefusalKindTests {
    @Test func aRuleOfTheCoreNeedsDifferentInputButOutagesAndLimitsDoNot() {
        #expect(AccountsModel.isRule(.http(status: 409, code: "conflict", message: "pool used twice")))
        #expect(AccountsModel.isRule(.badRequest(message: "bad")))
        #expect(!AccountsModel.isRule(.http(status: 500, code: "internal", message: "")))
        #expect(!AccountsModel.isRule(.http(status: 429, code: "rate_limited", message: "")))
        #expect(!AccountsModel.isRule(.forbiddenScope))
        #expect(!AccountsModel.isRule(.offline("down")))
        #expect(!AccountsModel.isRule(nil))
    }
}

@MainActor
struct ConnectCommandTests {
    @Test func aNewKeyIsAnAddNeverAKeyOnTheCommandLine() {
        let c = ConnectDialog.addCommand(provider: "claude", label: "Work", replacing: nil)
        #expect(c == "ainkradctl account add claude --label 'Work' --key-file <file with the key>")
        #expect(!c.contains("curl") && !c.contains("Authorization"))
    }

    @Test func aReplacementRotatesTheAccount() {
        let c = ConnectDialog.addCommand(provider: "claude", label: "Work", replacing: 7)
        #expect(c == "ainkradctl account rotate 7 --key-file <file with the new key>")
    }

    @Test func aLabelWithAQuoteStaysOneWord() {
        #expect(ConnectDialog.addCommand(provider: "p", label: "Bob's", replacing: nil).contains("'Bob'\\''s'"))
    }
}
