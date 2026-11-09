import CoreKit
import Foundation
import Testing

@testable import Accounts

@MainActor
struct KeyEntryTests {
    func make(gate: GateState = GateState(mode: 1, providerAccounts: 1)) async -> (AccountsModel, FakeService, FakeHost)
    {
        let host = FakeHost()
        let model = AccountsModel(host: host)
        let svc = FakeService()
        svc.gateState = gate
        model.use(svc)
        try? await Task.sleep(for: .milliseconds(50))
        return (model, svc, host)
    }

    func filled(_ m: AccountsModel, target: AccountItem? = nil) async -> KeyEntryFlow {
        let f = KeyEntryFlow(target: target)
        await f.load(m)
        f.key = "sk-secret-1234"
        return f
    }

    @Test func createThenTestEndsConnectedAndWipesTheKey() async {
        let (m, svc, host) = await make()
        let f = await filled(m)
        await f.connect(m, provider: "anthropic")
        guard case .done(_, let ms, _) = f.stage else {
            Issue.record("not done: \(f.stage)")
            return
        }
        #expect(ms == 300)
        #expect(f.key.isEmpty)
        #expect(svc.lastKey == "sk-secret-1234")
        #expect(svc.log.contains("createAccount anthropic Work r_1"))
        #expect(svc.log.last?.hasPrefix("test ") == true)
        #expect(host.reasons.count == 1)
    }

    @Test func aFailedTestKeepsTheAccountToRemoveOrReplace() async {
        let (m, svc, _) = await make()
        svc.tested = TestedItem(result: "auth_failed", latencyMs: 80)
        let f = await filled(m)
        await f.connect(m, provider: "anthropic")
        guard case .failed(let why, let id) = f.stage else {
            Issue.record("not failed")
            return
        }
        #expect(why.contains("Key refused") && id != nil)
        f.tryAnother()
        f.key = "sk-other"
        await f.connect(m, provider: "anthropic")
        #expect(svc.log.contains { $0.hasPrefix("replaceSecret") })
        #expect(svc.log.filter { $0.hasPrefix("createAccount") }.count == 1)
        svc.tested = TestedItem(result: "auth_failed", latencyMs: 80)
        f.tryAnother()
        f.key = "x"
        await f.connect(m, provider: "anthropic")
        await f.remove(m)
        #expect(svc.log.contains { $0.hasPrefix("deleteAccount") })
        #expect(f.stage == .form && f.target == nil)
    }

    @Test(arguments: [
        ("secrets_disabled", "turned off"), ("real_secret_refused", "real keys"),
        ("login_required", "signs in with your plan"), ("conflict", "already have an account"),
        ("limit_reached", "as many accounts"), ("secrets_unavailable", "can't store keys"),
    ])
    func eachRefusalHasPlainWords(code: String, word: String) async {
        let (m, svc, _) = await make()
        svc.failure = CoreError.http(status: 409, code: code, message: "raw")
        let f = await filled(m)
        await f.connect(m, provider: "anthropic")
        guard case .failed(let why, let id) = f.stage else {
            Issue.record("not failed")
            return
        }
        #expect(why.contains(word) && id == nil)
        #expect(!why.contains("raw"))
        #expect(f.stage != .form)
    }

    @Test func aBadInputIsExplained() {
        #expect(KeyEntryFlow.keyWords(CoreError.badRequest(message: "x")).contains("didn't accept"))
    }

    @Test func theGateCardTurnsKeysOnInOneTouch() async {
        let (m, svc, host) = await make(gate: GateState(mode: 0, providerAccounts: 0))
        let f = await filled(m)
        #expect(f.needsGate && !f.ready(rotating: false))
        await f.enableKeys(m)
        #expect(
            svc.log.filter { $0.hasPrefix("switch") } == [
                "switch secrets.mode 1", "switch secrets.provider_accounts 1",
            ])
        #expect(host.reasons.count == 1)
        #expect(!f.needsGate && f.ready(rotating: false))
    }

    @Test func aTestKeysCoreOnlyNeedsRealKeysOn() async {
        let (m, svc, _) = await make(gate: GateState(mode: 1, providerAccounts: 0))
        let f = await filled(m)
        await f.enableKeys(m)
        #expect(svc.log.filter { $0.hasPrefix("switch") } == ["switch secrets.provider_accounts 1"])
    }

    @Test func closingWipesTheKey() async {
        let (m, _, _) = await make()
        let f = await filled(m)
        f.wipe()
        #expect(f.key.isEmpty)
    }

    @Test func rotatingReplacesTheSecretThenTests() async {
        let (m, svc, _) = await make()
        svc.accountList = [account(1, "main")]
        let f = await filled(m, target: svc.accountList[0])
        #expect(f.ready(rotating: true))
        await f.connect(m, provider: "anthropic")
        guard case .done(let id, _, _) = f.stage else {
            Issue.record("not done")
            return
        }
        #expect(id == 1 && f.key.isEmpty)
        #expect(svc.log.contains("replaceSecret 1 keep") && svc.log.contains("test 1"))
        #expect(!svc.log.contains { $0.hasPrefix("createAccount") })
    }

    @Test func aDeclinedTouchIDChangesNothing() async {
        let (m, svc, host) = await make()
        host.declines = true
        let f = await filled(m)
        await f.connect(m, provider: "anthropic")
        #expect(f.stage == .form && f.key == "sk-secret-1234" && svc.log.isEmpty)
    }
}
