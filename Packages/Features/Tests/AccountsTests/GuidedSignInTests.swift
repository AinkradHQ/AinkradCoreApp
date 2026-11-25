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

    @Test func antigravityTakesOnlyAMenuNumberOrACodeLikeTheCore() {
        let agy = "agy-sub"
        for ok in ["1", "12", "4/0AbCdEf-gh_ij", String(repeating: "a", count: 256)] {
            #expect(GuidedInput.check(ok, provider: agy) == .send(ok), "\(ok.prefix(8))")
        }
        #expect(GuidedInput.check(String(repeating: "a", count: 257), provider: agy) == .tooLong)
        for bad in ["a", "123", "abcdefg", "abcd efgh", "abcd.efgh", "x1", "٣١"] {
            #expect(GuidedInput.check(bad, provider: agy) == .badCharacters, "\(bad)")
        }
        #expect(GuidedInput.words(.badCharacters, provider: agy)?.hasSuffix(GuidedInput.agyHint) == true)
    }

    @Test func aTypedLineIsOneShortPrintableLine() {
        #expect(GuidedInput.check("  1\n") == .send("1"))
        #expect(GuidedInput.check("   \n") == .empty)
        #expect(GuidedInput.check(String(repeating: "a", count: 257)) == .tooLong)
        #expect(GuidedInput.check(String(repeating: "a", count: 256)) == .send(String(repeating: "a", count: 256)))
        #expect(GuidedInput.check("one\ntwo") == .badCharacters)
        #expect(GuidedInput.check("K7QM-4XZP_9") == .send("K7QM-4XZP_9"))
        // OpenCode's menu filters by typing: any printable line goes, spaces and punctuation included.
        for ok in ["open router", "a/b", "a;b", "é", "a.b"] {
            #expect(GuidedInput.check(ok, provider: "opencode-sub") == .send(ok), "\(ok)")
        }
        for bad in ["a\u{7}b", "a\tb", "a\u{1B}[0m"] {
            #expect(GuidedInput.check(bad) == .badCharacters, "\(bad)")
        }
        #expect(GuidedInput.words(.badCharacters)?.hasSuffix(GuidedInput.hint) == true)
        #expect(GuidedInput.words(.tooLong)?.hasSuffix(GuidedInput.hint) == true)
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
        #expect(
            none.none && none.chosen == nil && none.why(provider: "Antigravity").hasPrefix("No runner is connected"))
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

/// The review fixes (E7): the start of a sign-in, the secret toggle's rule, the notes.
@MainActor struct GuidedReviewFixTests {
    func provider(_ id: String, harness: String) -> ProviderItem {
        ProviderItem(
            id: id, name: id, harness: harness, authVar: "T", baseURL: "", delivery: [],
            loginMethods: ["runner_login"], models: [], pricedAt: nil, builtin: true)
    }

    func ready(_ svc: FakeService) async -> AccountsModel {
        let m = AccountsModel(host: FakeHost())
        svc.runnerList = [
            AccountRunner(
                id: "r_1", name: "linux-01", online: true, commands: ["login-bound:agy", "login-bound:opencode"])
        ]
        svc.orderOn = true
        m.use(svc)
        return m
    }

    /// The approved Add an AI account mockup (2026-11-25): no consent step, the sign-in starts at once and the risk line
    /// sits under the checklist.
    @Test(.timeLimit(.minutes(1))) func antigravityStartsAtOnceWithTheRiskLine() async {
        let svc = FakeService()
        let m = await ready(svc)
        m.signInTick = 0.002
        svc.loginItem = LoginItem(
            id: "lg", provider: "agy-sub", label: "agy", runner: "r_1", state: "failed", url: nil, reason: "stop",
            accountID: nil)
        let flow = AddAccountFlow()
        await flow.choose(provider("agy-sub", harness: "agy"), m)
        #expect(svc.log.contains { $0.hasPrefix("startLogin agy-sub") }, "it started without asking")
        #expect(AddCards.risky("agy-sub") && !AddCards.risky("codex-sub") && !AddCards.risky("claude-sub"))
    }

    /// Accounts on the Core: the wizard never asks for a runner, even when several could run the sign-in.
    @Test func theWizardHasNoRunnerStepAndNamesNoRunner() async {
        let svc = FakeService()
        let m = await ready(svc)
        svc.runnerList = ["r_1", "r_2"].map {
            AccountRunner(id: $0, name: $0, online: true, commands: ["login-bound:agy", "login-bound:opencode"])
        }
        m.signInTick = 0.002
        svc.loginItem = LoginItem(
            id: "lg", provider: "agy-sub", label: "agy", runner: "r_2", state: "failed", url: nil, reason: "stop",
            accountID: nil)
        let flow = AddAccountFlow()
        await flow.choose(provider("agy-sub", harness: "agy"), m)
        // The sign-in starts through the Core with no runner named.
        let starts = svc.log.filter { $0.hasPrefix("startLogin") }
        #expect(starts == ["startLogin agy-sub \(flow.keyFlow.label)"], "\(starts)")
        #expect(flow.runners == nil)
        #expect(RunnerBinding.forSignIn("codex-sub").words == "Signed in on the Core · works on every runner")
        #expect(RunnerBinding.forSignIn("agy-sub").why == RunnerBinding.agyWhy)
    }

    @Test func whereTheLoginLivesDecidesTheLineAndMoveToCore() async {
        let svc = FakeService()
        svc.orderOn = true
        svc.accountList = [
            account(1, "codex-old", provider: "codex-sub"), account(2, "codex-new", provider: "codex-sub"),
            account(3, "agy", provider: "agy-sub"),
        ]
        let m = await ready(svc)
        svc.bound = [1: "r_1", 3: "r_1"]
        svc.notes = [
            1: AccountNotes(held: "runner"), 2: AccountNotes(held: "core"), 3: AccountNotes(held: "runner"),
        ]
        await m.reload()
        await m.reloadBindings(svc)
        let old = m.account(1)!
        let new = m.account(2)!
        let agy = m.account(3)!
        #expect(new.runnerBinding?.words == "Signed in on the Core · works on every runner")
        #expect(old.runnerBinding?.words == "Runs only on linux-01" && old.runnerBinding?.movable == true)
        #expect(m.moreActions(old).contains(.moveToCore))
        #expect(!m.moreActions(new).contains(.moveToCore) && !m.moreActions(agy).contains(.moveToCore))
        #expect(agy.runnerBinding?.detail.contains("keychain") == true)
        await m.moveToCore(old)
        #expect(svc.log.contains("moveToCore 1"))
    }

    @Test(.timeLimit(.minutes(1))) func openCodeNeedsNoConsent() async {
        let flow = AddAccountFlow()
        let svc = FakeService()
        let m = await ready(svc)
        m.signInTick = 0.002
        // With one runner and no consent to ask, choosing starts the sign-in and follows it until it ends.
        let choosing = Task { await flow.choose(provider("opencode-sub", harness: "opencode"), m) }
        for _ in 0..<400 where !svc.log.contains(where: { $0.hasPrefix("startLogin opencode-sub") }) {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(svc.log.contains { $0.hasPrefix("startLogin opencode-sub") }, "it started without asking")
        // Wait for the page to reach the host before closing, or a slow parallel run cancels first.
        for _ in 0..<400 where (m.host as? FakeHost)?.opened.isEmpty != false {
            try? await Task.sleep(for: .milliseconds(5))
        }
        await m.cancelSignIn()  // closing the dialog ends the follow
        await choosing.value
        #expect((m.host as? FakeHost)?.opened.isEmpty == false, "the sign-in page went to the host, not a browser")
    }

    @Test func theNotesLandOnTheAccountAndTheRemovalToast() async {
        let svc = FakeService()
        svc.orderOn = true
        svc.accountList = [account(1, "agy-main")]
        let m = await ready(svc)
        await m.reload()
        guard let id = m.accounts.first?.id else {
            Issue.record("no account")
            return
        }
        svc.notes = [id: AccountNotes(wipeNote: AccountNotes.keyringWords, modelsEnforced: false)]
        await m.reloadBindings(svc)
        #expect(m.account(id)?.wipeNote == AccountNotes.keyringWords && m.account(id)?.modelsEnforced == false)
        svc.notes = [:]
        await m.reloadBindings(svc)
        #expect(m.account(id)?.wipeNote == nil && m.account(id)?.modelsEnforced == nil)
    }

    @Test func theNotesReadLeniently() {
        #expect(AccountNotes.wipe(note: nil, flag: nil) == nil && AccountNotes.wipe(note: " ", flag: false) == nil)
        #expect(AccountNotes.wipe(note: "Sign out on box.", flag: true) == "Sign out on box.")
        #expect(AccountNotes.wipe(note: nil, flag: true) == AccountNotes.keyringWords)
        #expect(AccountNotes.removedWords("Antigravity", note: nil) == "Antigravity removed")
        #expect(AccountNotes.removedWords("Antigravity", note: "Sign out.") == "Antigravity removed. Sign out.")
        #expect(AccountNotes.unenforcedWords.hasPrefix("This account's sessions cannot restrict models"))
    }
}
