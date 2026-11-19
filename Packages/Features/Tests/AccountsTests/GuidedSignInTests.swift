import CoreKit
import Foundation
import Testing

@testable import Accounts

private func runner(_ id: String, online: Bool = true, can: [String] = ["login-bound:opencode"]) -> AccountRunner {
    AccountRunner(id: id, name: "box-\(id)", online: online, commands: Set(can))
}

/// Runner-bound sign-in (E7-4, E7-5, E7-5b): which screen a provider uses, the runner choice, the typed line, the polling.
struct GuidedLoginRulesTests {
    @Test func theCoresLoginMethodsPickTheScreenAndIdsAreOnlyTheFallback() {
        #expect(SignInStyle.of("x", methods: ["device_code"]) == .deviceCode)
        #expect(SignInStyle.of("x", methods: ["runner_login"]) == .guided)
        #expect(SignInStyle.of("x", methods: ["browser_code"]) == .paste)
        #expect(SignInStyle.of("codex-sub") == .deviceCode)
        #expect(SignInStyle.of("opencode-sub") == .guided && SignInStyle.of("agy-sub") == .guided)
        #expect(SignInStyle.of("claude-sub") == .paste && !SignInStyle.of("claude-sub").runnerBound)
        #expect(SignInStyle.of("agy-sub").runnerBound)
    }

    @Test func theRiskNoteShowsForPlansWithRulesOfTheirOwn() {
        #expect(SignInStyle.showsRisk("codex-sub") && SignInStyle.showsRisk("agy-sub"))
        #expect(!SignInStyle.showsRisk("opencode-sub"))
    }

    @Test func aTypedLineIsOneShortPrintableLine() {
        #expect(GuidedInput.check("  1\n") == .send("1"))
        #expect(GuidedInput.check("   \n") == .empty)
        #expect(GuidedInput.check(String(repeating: "a", count: 513)) == .tooLong)
        #expect(GuidedInput.check(String(repeating: "a", count: 512)) == .send(String(repeating: "a", count: 512)))
        #expect(GuidedInput.check("one\ntwo") == .notOneLine)
        #expect(GuidedInput.words(.notOneLine) == "Send one line at a time.")
    }

    @Test func theScreenIsReadQuicklyWhileItChangesAndSlowerWhileStillNeverPastTheCap() {
        var b = PollBackoff()
        #expect(b.seconds == 1)
        for _ in 0..<20 { b.note(changed: false) }
        #expect(b.seconds == PollBackoff.cap)
        b.note(changed: true)
        #expect(b.seconds == PollBackoff.floor)
        b.note(changed: false)
        b.reset()
        #expect(b.seconds == PollBackoff.floor)
    }

    @Test func onlyAnOnlineRunnerThatListsTheHarnessCanSignIn() {
        let list = [
            runner("a"), runner("b", online: false), runner("c", can: ["login"]),
            runner("d", can: ["login-bound:opencode"]),
        ]
        let c = RunnerChoice.make(runners: list, harness: "opencode")
        #expect(c.eligible.map(\.id) == ["a", "d"] && c.needsPick && c.selected == "a" && c.only == nil)
        #expect(RunnerChoice.make(runners: list, harness: "opencode", keep: "d").selected == "d")
        #expect(RunnerChoice.make(runners: list, harness: "opencode", keep: "b").selected == "a")
        let one = RunnerChoice.make(runners: [runner("a"), runner("b", online: false)], harness: "opencode")
        #expect(one.only?.id == "a" && !one.needsPick && !one.none)
    }

    @Test func whenNoRunnerCanTheWordsSayWhy() {
        let none = RunnerChoice.make(runners: [], harness: "agy")
        #expect(none.none && none.chosen == nil && none.why(provider: "Antigravity").hasPrefix("No runner is connected"))
        let off = RunnerChoice.make(runners: [runner("a", online: false)], harness: "opencode")
        #expect(off.why(provider: "OpenCode").hasPrefix("None of your runners is online"))
        let old = RunnerChoice.make(runners: [runner("a", can: [])], harness: "opencode")
        #expect(old.why(provider: "OpenCode").hasPrefix("No online runner can sign in to OpenCode"))
    }

    @Test func aBoundAccountSaysWhereItRuns() {
        #expect(RunnerBinding(name: "linux-01").words == "Runs only on linux-01")
        #expect(RunnerBinding(name: nil).words == "Runs on one runner only")
    }
}

@MainActor
struct GuidedSignInModelTests {
    func make() async -> (AccountsModel, FakeService) {
        let model = AccountsModel(host: FakeHost())
        model.signInTick = 0.002
        let svc = FakeService()
        svc.orderOn = true
        svc.providerList.append(
            ProviderItem(
                id: "opencode-sub", name: "OpenCode", harness: "opencode", authVar: "T", baseURL: "", delivery: [],
                loginMethods: ["runner_login"], models: [], pricedAt: nil, builtin: true))
        model.use(svc)
        await model.reload()
        return (model, svc)
    }

    func login(_ state: String, account: Int64? = nil) -> LoginItem {
        LoginItem(
            id: "lg", provider: "opencode-sub", label: "opencode", runner: "r_1", state: state, url: nil, reason: nil,
            accountID: account)
    }

    @Test func aGuidedSignInShowsTheScreenTypesOneLineAndEndsDone() async {
        let (m, svc) = await make()
        svc.loginItem = login("open_url")
        let run = Task { await m.startSignIn(provider: "opencode-sub", label: "opencode", runner: "r_1") }
        #expect(await until { m.signIn?.screen == ["Which provider?"] })
        guard case .guided? = m.signIn?.stage else {
            Issue.record("not guided: \(String(describing: m.signIn?.stage))")
            return
        }
        #expect(await m.sendGuidedInput("dummy-line"))
        #expect(svc.log.contains("sendLoginInput lg 10"))
        #expect(m.signIn?.inputError == nil)
        // The line is not kept anywhere on the flow.
        #expect(!String(describing: m.signIn).contains("dummy-line"))
        svc.loginItem = login("done", account: 9)
        #expect(await until { m.signIn?.stage == .done(account: 9) })
        #expect(m.signIn?.screen == [], "the screen is dropped when the sign-in ends")
        #expect(m.boundSeen[9] == "r_1")
        await run.value
        // Polling stopped with the sign-in: no more screen reads.
        let reads = svc.screenReads
        try? await Task.sleep(for: .milliseconds(60))
        #expect(svc.screenReads == reads)
    }

    @Test func aFailedSignInStopsPollingAndDropsTheScreen() async {
        let (m, svc) = await make()
        svc.loginItem = login("open_url")
        let run = Task { await m.startSignIn(provider: "opencode-sub", label: "opencode", runner: "r_1") }
        #expect(await until { !(m.signIn?.screen.isEmpty ?? true) })
        svc.loginItem = LoginItem(
            id: "lg", provider: "opencode-sub", label: "opencode", runner: "r_1", state: "failed", url: nil,
            reason: "wrong code", accountID: nil)
        #expect(await until { m.signInEnded })
        #expect(m.signIn?.screen == [])
        await run.value
    }

    @Test func aRefusedLineIsExplainedWithoutRepeatingIt() async {
        let (m, svc) = await make()
        svc.loginItem = login("open_url")
        let run = Task { await m.startSignIn(provider: "opencode-sub", label: "opencode", runner: "r_1") }
        #expect(await until { m.guidedOpen })
        #expect(await m.sendGuidedInput("   ") == false)
        #expect(!svc.log.contains { $0.hasPrefix("sendLoginInput") }, "an empty line is not sent")
        svc.inputFailure = CoreError.http(status: 409, code: "runner_failed", message: "secret-looking-line")
        #expect(await m.sendGuidedInput("dummy-line") == false)
        #expect(m.signIn?.inputError == "The runner did not answer. Check that it is online, then try again.")
        svc.loginItem = login("done", account: 1)
        await run.value
    }

    @Test func cancelCallsTheCancelRouteAndForgetsTheScreen() async {
        let (m, svc) = await make()
        svc.loginItem = login("open_url")
        let run = Task { await m.startSignIn(provider: "opencode-sub", label: "opencode", runner: "r_1") }
        #expect(await until { !(m.signIn?.screen.isEmpty ?? true) })
        await m.cancelSignIn()
        #expect(svc.log.contains("cancelLogin lg") && m.signIn == nil)
        await run.value
    }

    @Test func aBoundAccountShowsWhereItRunsFromTheCoreOrWhereItSignedIn() async {
        let (m, svc) = await make()
        svc.accountList = [account(5, "oc", provider: "opencode-sub"), account(6, "key")]
        svc.runnerList = [AccountRunner(id: "r_1", name: "linux-01", online: true)]
        svc.bound = [5: "r_1"]
        await m.reload()
        #expect(m.account(5)?.runnerBinding?.words == "Runs only on linux-01")
        #expect(m.account(6)?.runnerBinding == nil)
        svc.bound = [:]
        await m.reload()
        #expect(m.account(5)?.runnerBinding?.words == "Runs on one runner only", "bound by its provider")
    }
}
