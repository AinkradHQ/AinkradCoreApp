import CoreKit
import Foundation
import Shell
import Testing

@testable import Agents

@MainActor
struct ChainBindingTests {
    private func make(host: FakeHost? = FakeHost()) async -> (AgentsModel, FakeAgentsAPI, FakeHost?) {
        let api = FakeAgentsAPI()
        api.chainList = [
            ChainOption(id: 1, name: "Everyday", isDefault: false, steps: ["claude · sonnet"]),
            ChainOption(id: 2, name: "Careful", isDefault: true, steps: ["claude · opus"]),
        ]
        api.bindingList = [AgentBinding(agent: "atlas", chain: 1)]
        api.agentList = ["atlas"]
        let defaults = UserDefaults(suiteName: "agents-chain-tests-\(UUID())")!
        let m = AgentsModel(shell: ShellModel(), notifier: FakeNotifier(), defaults: defaults, host: host)
        m.isAdmin = true
        m.attach(api)
        await m.reloadAll()
        return (m, api, host)
    }

    @Test func listsBoundAgentsWithTheirChainAndTheDefault() async {
        let (m, _, _) = await make()
        #expect(m.bindingsPhase == .ready)
        #expect(m.knownAgents == ["atlas"])
        #expect(m.chain(of: "atlas")?.name == "Everyday")
        #expect(m.chain(of: "nobody") == nil)
        #expect(m.defaultChain?.name == "Careful")
    }

    @Test func bindingNeedsTouchIDAndMovesTheAgent() async {
        let (m, api, host) = await make()
        let careful = m.chains[1]
        #expect(await m.bind("atlas", to: careful))
        #expect(m.chain(of: "atlas")?.name == "Careful" && m.bindings.count == 1)
        #expect(api.calls.contains("bind atlas 2"))
        #expect(host?.asked.count == 1)
        #expect(await m.bind(" ines ", to: m.chains[0]))
        #expect(m.knownAgents == ["atlas", "ines"])
        #expect(m.bindings.map(\.agent).sorted() == ["atlas", "ines"])
    }

    @Test func aDeclinedTouchIDChangesNothingAndSaysWhy() async {
        let host = FakeHost()
        host.notice = InlineNotice(title: "Touch ID was cancelled.")
        let (m, api, _) = await make(host: host)
        #expect(!(await m.bind("atlas", to: m.chains[1])))
        #expect(m.chain(of: "atlas")?.name == "Everyday")
        #expect(m.bindingNotices["atlas"]?.title == "Touch ID was cancelled.")
        #expect(!api.calls.contains { $0.hasPrefix("bind ") })
    }

    @Test func aBadAgentIdNeverReachesTheCore() async {
        let (m, api, _) = await make()
        #expect(!(await m.bind("two words", to: m.chains[0])))
        #expect(!(await m.bind("", to: m.chains[0])))
        #expect(!api.calls.contains { $0.hasPrefix("bind ") })
    }

    @Test func unbindingAsksFirstThenFallsBackToTheDefault() async {
        let (m, api, _) = await make()
        m.confirmUnbind("atlas")
        let sheet = m.shell.sheet
        #expect(sheet?.title == "Unbind atlas?" && sheet?.message.contains("Careful") == true)
        sheet?.actions.first { $0.destructive }?.run()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(m.bindings.isEmpty && api.calls.contains("unbind atlas"))
    }

    @Test func aRefusalForScopeMakesThePageReadOnly() async {
        let (m, api, _) = await make()
        try? await Task.sleep(for: .milliseconds(150))  // attach's own first load must not take the scripted failure
        api.failNext = CoreError.forbiddenScope
        #expect(!(await m.bind("atlas", to: m.chains[1])))
        #expect(m.bindingsReadOnly)
    }

    @Test func aFailedReadIsAStateWithPlainWords() async {
        let api = FakeAgentsAPI()
        api.failNext = CoreError.http(status: 500, code: "internal", message: "no")
        let m = AgentsModel(
            shell: ShellModel(), notifier: FakeNotifier(), defaults: UserDefaults(suiteName: "x-\(UUID())")!)
        m.attach(api)
        await m.loadBindings()
        guard case .failed(let why) = m.bindingsPhase else {
            Issue.record("not failed")
            return
        }
        #expect(!why.isEmpty)
    }

    @Test func thePoolHookIsOffUntilTheCoreTakesAPoolId() {
        #expect(!SessionPoolHook.isAvailable)
    }
}
