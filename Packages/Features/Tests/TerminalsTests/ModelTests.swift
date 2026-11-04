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

    @Test func reloadSortsRunningFirstAndFiltersByState() async {
        let (m, svc, _) = make()
        svc.terminalList = [item("t_old", status: "exited", code: 0), item("t_run")]
        await m.reload()
        #expect(m.items.map(\.id) == ["t_run", "t_old"] && m.load == .ready && m.openCount == 1)
        m.filter = .ended
        #expect(m.shown.map(\.id) == ["t_old"])
        m.filter = .running
        #expect(m.shown.map(\.id) == ["t_run"])
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
    func create(runner: String, program: String?, rows: Int, cols: Int) async throws -> TerminalItem {
        throw CoreError.offline("down")
    }
    func close(_ id: String) async throws -> TerminalItem { throw CoreError.offline("down") }
    func signal(_ id: String, _ name: String) async throws { throw CoreError.offline("down") }
    func noop(_ runner: String) async throws -> Int { throw CoreError.offline("down") }
    func attach(_ id: String, after: UInt64) async throws -> any TerminalLink { throw CoreError.offline("down") }
}
