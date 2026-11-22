import Foundation
import Testing

@testable import Terminals

/// Machines: the one status, the groups and their order, the problem line, load, and asking for AI tool installs once.
struct MachinesTests {
    private func quiet(_ id: String = "r1", name: String = "attic", online: Bool = true) -> RunnerItem {
        var r = runner(id, name: name, online: online)
        r.load = 0
        return r
    }

    private func signIn(_ id: String, mac: Bool = false, me: Bool = false, seen: TimeInterval = 0) -> SignInMachine {
        SignInMachine(
            id: id, name: id, platform: mac ? "macos" : "ios", lastSeen: Date(timeIntervalSince1970: 1_000_000 + seen),
            added: Date(timeIntervalSince1970: 0), scopes: ["read"], isThisMac: me)
    }

    @Test func oneStatusOfflineWinsAndNothingOfflineReadsWorking() {
        var off = quiet(online: false)
        off.slots = RunnerSlotFacts(agentsUsed: 2, agentsCapacity: 4, terminalsUsed: 1, terminalsCapacity: 4)
        #expect(MachineStatus(off) == .offline, "an offline machine never reads Working, even with stale slots")
        #expect(MachineStatus(runner(degraded: true)) == .notAnswering)
        #expect(MachineStatus(quiet()) == .idle)
        var working = quiet()
        working.slots = RunnerSlotFacts(agentsUsed: 1, agentsCapacity: 4, terminalsUsed: 0, terminalsCapacity: 4)
        #expect(MachineStatus(working) == .working)
        #expect(MachineStatus(runner()) == .working, "an older runner with no slots works when it has load")
        #expect(MachineStatus(runner(avg1: 40)) == .idle, "busy with other apps and nothing of ours running is Idle")
        var busyAndOurs = runner(avg1: 40)
        busyAndOurs.slots = RunnerSlotFacts(agentsUsed: 1, agentsCapacity: 4, terminalsUsed: 0, terminalsCapacity: 4)
        #expect(MachineStatus(busyAndOurs) == .working)
    }

    @Test func doesWorkPutsThisMacFirstThenTheCoreThenByName() {
        var core = quiet("core", name: "Core")
        core.builtIn = true
        let list = Machines.ordered(
            [quiet("b", name: "zeta"), core, quiet("a", name: "alpha"), quiet("mac", name: "mine")], thisMac: "mac")
        #expect(list.map(\.id) == ["mac", "core", "a", "b"])
        #expect(Machines.name(list[0], thisMac: "mac") == "This Mac")
    }

    @Test func signsInOnlyDropsThisMacOnceItDoesWork() {
        let all = [signIn("phone", seen: 10), signIn("me", mac: true, me: true), signIn("tablet", seen: 50)]
        #expect(Machines.signInOnly(all, thisMacWorks: false).map(\.id) == ["me", "tablet", "phone"])
        #expect(Machines.signInOnly(all, thisMacWorks: true).map(\.id) == ["tablet", "phone"])
    }

    @Test func theProblemLineNamesTheFirstProblemAndHowManyMore() {
        var garage = quiet("g", name: "Garage pi", online: false)
        garage.lastSeen = Date(timeIntervalSince1970: 0)
        let attic = quiet("a", name: "Attic box")
        let failed = ToolInstall(op: "o", tool: "codex", state: .failed, percent: 0, step: "", reason: "No network.")
        let p = Machines.problem(
            [attic, garage], installs: ["a": ["codex": failed]], thisMac: nil,
            waiting: { $0 == "g" ? (0, 1) : (0, 0) })
        #expect(p?.machine == "g" && p?.title == "Garage pi is offline")
        #expect(
            p?.text.contains("1 terminal waits for it.") == true && p?.text.hasSuffix("1 more problem below.") == true)
        let only = Machines.problem([attic], installs: ["a": ["codex": failed]], thisMac: nil, waiting: { _ in (0, 0) })
        #expect(only?.title == "Could not install Codex on Attic box" && only?.text == "No network.")
        #expect(Machines.problem([attic], installs: [:], thisMac: nil, waiting: { _ in (0, 0) }) == nil)
    }

    @Test func loadAndRoomComeFromTheMachine() {
        var r = quiet()
        r.slots = RunnerSlotFacts(agentsUsed: 1, agentsCapacity: 4, terminalsUsed: 0, terminalsCapacity: 4)
        #expect(Machines.busy(r, cpuPct: 38) == 0.38, "the CPU wins when the Core reports hardware")
        #expect(Machines.busy(r, cpuPct: nil) == 0.25)
        #expect(Machines.room(r) == "Room for 3 more AI sessions")
        #expect(Machines.busy(quiet(online: false), cpuPct: 50) == nil, "an offline machine shows no load")
        #expect(
            Machines.summary([r, quiet("b"), quiet("c", online: false)], signIns: 2)
                == "1 working, 1 idle, 1 offline. 2 machines sign in only.")
    }

    @Test func autoInstallAsksForEachMissingPinnedToolOnceAfterTheGrace() {
        let now = Date(timeIntervalSince1970: 10_000)
        var r = quiet()
        r.drivers.append(DriverItem(name: "agent", commands: [], capacity: 2))
        r.tools = ["claude": "2.1"]
        r.connectedSince = now.addingTimeInterval(-30)
        #expect(
            AutoInstall.due([r], installs: [:], requested: [], now: now).isEmpty, "the runner gets its own go first")
        r.connectedSince = now.addingTimeInterval(-600)
        let due = AutoInstall.due([r], installs: [:], requested: [], now: now)
        #expect(due.map(\.tool) == ["codex", "opencode"], "never Antigravity: it has no download")
        #expect(AutoInstall.due([r], installs: [:], requested: ["r1/codex"], now: now).map(\.tool) == ["opencode"])
        let failed = ToolInstall(op: "o", tool: "codex", state: .failed, percent: 0, step: "", reason: nil)
        #expect(
            AutoInstall.due([r], installs: ["r1": ["codex": failed]], requested: [], now: now).map(\.tool) == [
                "opencode"
            ])
        var off = r
        off.online = false
        #expect(AutoInstall.due([off], installs: [:], requested: [], now: now).isEmpty)
        #expect(AutoInstall.missing(r) == "Codex and OpenCode")
    }

    @Test func aMacThatOnlySignsInCanStartWork() {
        #expect(Machines.promote(signIn("me", mac: true, me: true), macRunnerAvailable: true) == .thisMacSwitch)
        #expect(Machines.promote(signIn("me", mac: true, me: true), macRunnerAvailable: false) == nil)
        #expect(Machines.promote(signIn("studio", mac: true), macRunnerAvailable: true) == .runWorkHere)
        #expect(Machines.promote(signIn("phone"), macRunnerAvailable: true) == nil)
    }

    @MainActor @Test func theModelRequestsAMissingToolOnceWhileElevated() async {
        let svc = FakeService()
        var r = quiet()
        r.drivers.append(DriverItem(name: "agent", commands: [], capacity: 2))
        r.tools = ["claude": "2.1", "opencode": "1.4"]
        r.connectedSince = Date().addingTimeInterval(-600)
        svc.runnerList = [r]
        let host = FakeHost()
        host.isElevated = false
        let m = TerminalsModel(host: host, service: svc)
        await m.reload()
        #expect(svc.installed.isEmpty, "no Touch ID prompt nobody asked for")
        host.isElevated = true
        await m.reload()
        await m.reload()
        #expect(svc.installed == ["codex"], "asked once, not on every look")
    }
}
