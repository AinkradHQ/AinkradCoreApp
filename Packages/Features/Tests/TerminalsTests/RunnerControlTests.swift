import CoreKit
import Foundation
import Testing

@testable import Terminals

@MainActor
@Suite(.serialized) struct RunnerControlTests {
    private func make() -> (TerminalsModel, FakeService, RunnerItem) {
        let svc = FakeService()
        var r = runner()
        r.policy = RunnerPolicy(terminals: true, agents: false, capacity: 2)
        svc.runnerList = [r]
        return (TerminalsModel(host: FakeHost(), service: svc), svc, r)
    }

    @Test func aPolicyChangeKeepsTheOtherSwitchesAndSaysTheRunnerRestarts() async {
        let (m, svc, r) = make()
        await m.setPolicy(r, agents: true)
        #expect(svc.policies == [RunnerPolicy(terminals: true, agents: true, capacity: 2)])
        #expect(m.policyNote["r1"]?.refused == false)
        #expect(m.policyNote["r1"]?.text.contains("restarts") == true)
    }

    @Test func capacityStaysBetweenOneAndEight() async {
        let (m, svc, r) = make()
        await m.setPolicy(r, capacity: 99)
        await m.setPolicy(r, capacity: 0)
        #expect(svc.policies.map(\.capacity) == [8, 1])
    }

    @Test func aRefusalShowsTheCoresReasonAndRunnerOfflineGetsPlainWords() async {
        let (m, svc, r) = make()
        svc.policyResult = .failure(.http(status: 409, code: "policy_refused", message: "no agent tool is installed"))
        await m.setPolicy(r, agents: true)
        #expect(m.policyNote["r1"] == RunnerNote(text: "no agent tool is installed", refused: true))
        svc.policyResult = .failure(.http(status: 409, code: "runner_offline", message: "x"))
        await m.setPolicy(r, terminals: false)
        #expect(m.policyNote["r1"]?.text == "mac-studio is offline. Try again when it is back.")
    }

    @Test func toolInstallProgressFollowsTheEvents() async {
        let (m, svc, r) = make()
        await m.installTool(r, "git")
        #expect(svc.installed == ["git"] && m.installs["r1"]?["git"]?.op == "op_1")
        m.toolInstall(["runner": "r1", "tool": "git", "state": "running", "percent": "40", "step": "Downloading"])
        #expect(m.installs["r1"]?["git"]?.percent == 40 && m.installs["r1"]?["git"]?.state == .running)
        m.toolInstall(["runner": "r1", "tool": "git", "state": "failed", "reason": "no network"])
        #expect(m.installs["r1"]?["git"]?.reason == "no network")
    }

    @Test func progressNamesTheToolBeingInstalledAndTheLastFailure() async {
        let (m, _, r) = make()
        await m.reload()
        #expect(m.runnerProgress(id: r.id)?.installing == nil)
        m.installs[r.id] = [
            "claude": ToolInstall(op: "o1", tool: "claude", state: .running, percent: 40, step: "", reason: nil),
            "codex": ToolInstall(op: "o2", tool: "codex", state: .failed, percent: 0, step: "", reason: "No network."),
        ]
        let p = m.runnerProgress(name: r.name)
        #expect(p?.installing == "Claude" && p?.percent == 40 && p?.failure == "No network.")
        #expect(m.runningInstall(r.id)?.tool == "claude")
        #expect(m.runnerProgress(id: "nope") == nil)
    }

    @Test func theRunnersOwnReportShowsAnInstallInFlightAndKeepsADoneToolReady() async throws {
        let json = """
            [{"id":"r1","home":"/var/lib/akrw","last_error":"no AI tool installed",
              "tool_install":{"tool":"claude","state":"running","percent":55,"step":"Downloading Claude","reason":null}}]
            """
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let wire = try d.decode([RunnerReportWire].self, from: Data(json.utf8))
        var r = runner()
        wire[0].apply(to: &r)
        #expect(r.home == "/var/lib/akrw" && r.lastError == "no AI tool installed")
        #expect(r.reported?.state == .running && r.reported?.percent == 55)
        let (m, _, _) = make()
        await m.reload()
        m.runners = [r]
        m.applyReported()
        #expect(m.installs[r.id]?["claude"]?.percent == 55)
        // Done: nothing in flight, and the report alone does not make the tool installed (only the runner's probe does).
        var done = runner()
        RunnerReportWire(
            id: "r1", home: nil, lastError: nil,
            toolInstall: .init(tool: "codex", state: "done", percent: 100, step: "Installed", reason: nil)
        ).apply(to: &done)
        #expect(done.tools["codex"] == nil)
        m.runners = [done]
        m.applyReported()
        #expect(m.installs[done.id] == nil)
    }
}
