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
