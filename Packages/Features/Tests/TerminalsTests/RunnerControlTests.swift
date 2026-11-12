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
}
