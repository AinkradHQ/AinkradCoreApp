import CoreKit
import Foundation
import Testing

@testable import Terminals

@MainActor
@Suite(.serialized) struct ModelTests {
    private func make() -> (TerminalsModel, FakeService, FakeHost) {
        let svc = FakeService()
        let host = FakeHost()
        svc.runnerList = [runner()]
        return (TerminalsModel(host: host, service: svc), svc, host)
    }

    @Test func reloadSortsRunningFirst() async {
        let (m, svc, _) = make()
        svc.terminalList = [item("t_old", status: "exited", code: 0), item("t_run")]
        await m.reload()
        #expect(m.items.map(\.id) == ["t_run", "t_old"] && m.load == .ready && m.openCount == 1)
        #expect(m.shown.map(\.id) == ["t_run", "t_old"])
    }

    /// E6-3: the list is grouped by machine, This Mac first; the filter splits real shells from sandboxes.
    @Test func theListGroupsByMachineAndFiltersRealFromSandbox() async {
        let (m, svc, host) = make()
        host.macID = "r_mac"
        svc.runnerList = [runner(), runner("r_mac", name: "Studio")]
        var real = item("t_real", runner: "r_mac")
        real.sandbox = "real"
        var box = item("t_box")
        box.sandbox = "home"
        svc.terminalList = [box, real]
        await m.reload()
        #expect(m.groups.map(\.id) == ["r_mac", "r1"] && m.groups[0].isThisMac)
        #expect(m.shown.map(\.id) == ["t_real", "t_box"])
        m.filter = .sandbox
        #expect(m.shown.map(\.id) == ["t_box"])
        m.filter = .thisMac
        #expect(m.shown.map(\.id) == ["t_real"])
    }

    /// D-17: This Mac's own runner asks for a real shell; every other machine asks for the sandbox home or a project.
    @Test func theFormAsksForTheSandboxTheMachineAllows() async {
        let (m, svc, host) = make()
        host.macID = "r_mac"
        svc.runnerList = [runner(), runner("r_mac", name: "Studio")]
        await m.reload()
        let f = NewTerminalModel(model: m, runner: "r_mac")
        #expect(f.sandbox == "real")
        f.pick("r1")
        #expect(f.sandbox == "home")
        f.inProject = true
        f.projectID = 7
        #expect(f.sandbox == "project:7")
        f.session = "as_x"
        #expect(f.sandbox == nil)
        f.session = nil
        f.projectID = nil
        #expect(f.blockedReason == "Pick a project.")
        // A real shell on this Mac in a project is a cwd: `real` plus the project, never `project:<id>`.
        f.pick("r_mac")
        f.projectID = 7
        #expect(f.sandbox == "real" && f.projectParam == 7)
        f.inProject = false
        #expect(f.projectParam == nil)
    }

    /// ⌘T opens on the last machine used, when it is still ready.
    @Test func quickNewUsesTheLastMachine() async {
        let (m, svc, _) = make()
        svc.runnerList = [runner(), runner("r2", name: "Two")]
        await m.reload()
        let prefs = TerminalPrefs.shared
        let was = prefs.lastRunner
        defer { prefs.lastRunner = was }
        prefs.lastRunner = "r2"
        #expect(m.quickRunner == "r2")
        prefs.lastRunner = "gone"
        #expect(m.quickRunner != "gone")
    }

    @Test func hostLoadIsSampledOnEachLookAndOnlyWhileTheRunnerIsOnline() async {
        let (m, svc, _) = make()
        svc.terminalList = []
        await m.reload()
        await m.reload()
        #expect(m.loadSamples["r1"]?.count == 2)
        svc.runnerList = [runner(online: false)]
        await m.reload()
        #expect(m.loadSamples["r1"]?.count == 2)
    }

    @Test func aFailedLoadShowsTheCoresWords() async {
        let (m, svc, _) = make()
        svc.terminalList = []
        let failing = FailingService()
        let bad = TerminalsModel(host: FakeHost(), service: failing)
        await bad.reload()
        #expect(bad.load == .failed(CoreError.offline("down").localizedDescription))
        _ = (m, svc)
    }

    @Test func openingATerminalOpensItsPaneAndAttachesWhenNobodyElseHoldsIt() async {
        let (m, svc, host) = make()
        svc.terminalList = [item("t_1")]
        svc.attachResults = [.success(FakeLink())]
        await m.reload()
        m.openTerminal("t_1")
        #expect(host.shell.panes.map(\.id) == ["terminal-t_1"])
        #expect(await until { m.sessions["t_1"]?.isAttached == true })
        // The pane closing detaches, never ends.
        host.shell.closePane("terminal-t_1")
        m.paneClosed("t_1")
        #expect(m.sessions["t_1"] == nil && svc.closed.isEmpty)
    }

    @Test func aTerminalHeldElsewhereWaitsForAnExplicitAttach() async {
        let (m, svc, _) = make()
        svc.terminalList = [item("t_1", attached: 1)]
        await m.reload()
        m.openTerminal("t_1")
        #expect(m.sessions["t_1"]?.link == Link.none && svc.attachAfters.isEmpty)
    }

    @Test func newTerminalOpensItAndRefusalsStayInTheSheet() async {
        let (m, svc, host) = make()
        await m.reload()
        m.openNew()
        let form = m.newTerminal!
        #expect(form.runner == "r1" && form.canOpen)
        svc.createResult = .failure(.http(status: 409, code: "runner_offline", message: "m"))
        await form.submit()
        #expect(form.error?.code == "runner_offline" && host.shell.dialog != nil)
        svc.createResult = .success(item("t_new"))
        svc.terminalList = [item("t_new")]
        svc.attachResults = [.success(FakeLink())]
        form.program = " zsh "
        await form.submit()
        #expect(svc.created.last?.program == "zsh" && svc.created.last?.runner == "r1")
        #expect(host.shell.dialog == nil && host.shell.panes.map(\.id) == ["terminal-t_new"])
        #expect(host.reasons.contains { $0.contains("This approval covers this terminal only.") })
    }

    @Test func aSessionsTerminalNamesTheSessionAndFallsBackToHomeWhenItsFolderIsUnknown() async {
        let (m, svc, _) = make()
        await m.reload()
        svc.createResult = .success(item("t_new"))
        svc.terminalList = [item("t_new")]
        svc.attachResults = [.success(FakeLink()), .success(FakeLink())]
        let form = NewTerminalModel(model: m, runner: "r1")
        form.session = "as_1"
        await form.submit()
        #expect(svc.created.map(\.session) == ["as_1"] && form.error == nil)
        svc.sessionResult = .failure(.http(status: 409, code: "session_folder_unknown", message: "m"))
        let again = NewTerminalModel(model: m, runner: "r1")
        again.session = "as_1"
        await again.submit()
        #expect(svc.created.suffix(2).map(\.session) == ["as_1", nil] && again.error == nil)
    }

    @Test func aRunnerWithoutPtyCannotBeOpened() async {
        let (m, svc, _) = make()
        svc.runnerList = [runner(pty: false)]
        await m.reload()
        m.openNew()
        #expect(m.newTerminal?.runner == nil && m.newTerminal?.canOpen == false)
    }

    @Test func runnerProblemsGoToTheBellAndComeOff() async {
        let (m, svc, host) = make()
        svc.runnerList = [runner(online: false)]
        await m.reload()
        #expect(host.shell.bell.items.map(\.id) == ["runner-r1"])
        svc.runnerList = [runner()]
        await m.reload()
        #expect(host.shell.bell.items.isEmpty)
        #expect(host.shell.launcher.entry("runner-r1") != nil)
    }

    @Test func eventsTriggerOneRefetchForABurst() async {
        let (m, svc, _) = make()
        svc.terminalList = [item("t_a")]
        for _ in 0..<5 { m.event(kind: "terminal.opened") }
        m.event(kind: "device.revoked")
        #expect(await until { m.items.count == 1 })
    }
}

struct FailingService: TerminalService {
    func terminals() async throws -> [TerminalItem] { throw CoreError.offline("down") }
    func terminal(_ id: String) async throws -> TerminalItem { throw CoreError.offline("down") }
    func runners() async throws -> [RunnerItem] { throw CoreError.offline("down") }
    func create(runner: String, program: String?, session: String?, rows: Int, cols: Int) async throws -> TerminalItem {
        throw CoreError.offline("down")
    }
    func close(_ id: String) async throws -> TerminalItem { throw CoreError.offline("down") }
    func signal(_ id: String, _ name: String) async throws { throw CoreError.offline("down") }
    func noop(_ runner: String) async throws -> Int { throw CoreError.offline("down") }
    func attach(_ id: String, after: UInt64) async throws -> any TerminalLink { throw CoreError.offline("down") }
}

@MainActor
@Suite(.serialized) struct OfflineRunnerTests {
    private func make(_ runners: [RunnerItem]) async -> (TerminalsModel, FakeService) {
        let svc = FakeService()
        svc.runnerList = runners
        let m = TerminalsModel(host: FakeHost(), service: svc)
        await m.reload()
        return (m, svc)
    }

    @Test func openIsOffWithAPlainReasonWhenTheRunnerIsOffline() async {
        let (m, _) = await make([runner(online: false)])
        let form = NewTerminalModel(model: m, runner: "r1")
        #expect(!form.canOpen && form.blockedReason == "That runner is offline.")
        await form.submit()  // still asked: it answers in words, not silence
        #expect(form.error?.title == "That runner is offline.")
    }

    @Test func noRunnerChosenSaysSo() async {
        let (m, _) = await make([runner(online: false)])
        let form = NewTerminalModel(model: m, runner: nil)
        #expect(form.blockedReason == "Pick a runner to open it on.")
    }

    @Test func anOnlineRunnerIsNotBlocked() async {
        let (m, _) = await make([runner()])
        #expect(NewTerminalModel(model: m, runner: "r1").blockedReason == nil)
    }

    @Test func theBellSaysItInPlainWords() async {
        let (m, _) = await make([runner(online: false)])
        let sub = m.shell.bell.items.first { $0.kind == .runner }?.sub ?? ""
        #expect(sub == "Its terminals can't be reached until it's back.")
        #expect(!sub.contains("runner_offline") && !sub.contains("runner."))
    }

    /// A runner started with --terminal-user refuses private terminals; the sheet says how to fix it.
    @Test func aTerminalUserRunnerRefusalSaysWhatToDo() {
        let e = CoreError.http(
            status: 400, code: "invalid_args",
            message:
                "private terminals need shells that run as the runner's own user: start the runner without --terminal-user"
        )
        let r = NewTerminalModel.refusal(e, runner: "mac-studio")
        #expect(r.title == "This runner was started with --terminal-user; restart it without it to open terminals.")
    }

    /// A terminal ended with `exit` is reaped, and the Core answers 404 `not_found` for it. 404 means gone: it leaves the list
    /// (so its row stops polling), and Close on it just removes it instead of failing.
    @Test func notFoundMeansGone() async {
        #expect(TerminalItem.isGone(CoreError.http(status: 404, code: "not_found", message: "no such terminal")))
        #expect(!TerminalItem.isGone(CoreError.rateLimited(retryAfter: nil)))
        #expect(!TerminalItem.isGone(CoreError.http(status: 409, code: "conflict", message: "busy")))

        let (m, svc) = await make([runner()])
        svc.terminalList = [item("t_1"), item("t_2")]
        await m.reload()
        let s = m.session(for: "t_1")!
        svc.terminalList = [item("t_2")]  // `exit` in t_1: reaped on the Core; this app's list is stale
        await s.refresh()
        #expect(m.items.map { $0.id } == ["t_2"] && s.item.isEnded)

        // Close on a terminal the Core already forgot: no error, it just leaves the list.
        let s2 = m.session(for: "t_2")!
        svc.terminalList = []
        #expect(await s2.end())
        #expect(m.items.isEmpty)
    }

    /// Close on an ended terminal takes it off the list at once and asks the Core to forget it.
    @Test func closeOnAnEndedTerminalRemovesIt() async {
        let (m, svc) = await make([runner()])
        svc.terminalList = [item("t_x", status: "exited", code: 0)]
        await m.reload()
        TileAction.run(.end, "t_x", m)
        #expect(m.items.isEmpty)
        #expect(await until { svc.closed == ["t_x"] })
    }
}
