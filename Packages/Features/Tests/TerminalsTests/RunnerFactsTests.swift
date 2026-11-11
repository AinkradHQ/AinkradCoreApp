import Testing

@testable import Terminals

struct RunnerFactsTests {
    private func facts(
        online: Bool = true, degraded: Bool = false, avg1: Double = 1, pty: Bool = true, agent: Bool = false
    )
        -> RunnerFacts
    {
        var r = runner(online: online, degraded: degraded, avg1: avg1, pty: pty)
        if agent {
            r.drivers.append(DriverItem(name: "agent", commands: [], capacity: 2, slots: ["codex": 1, "claude": 2]))
        }
        return RunnerFacts(runner: r)
    }

    @Test func fourStatesInPlainWords() {
        #expect(facts().chip == "Online" && facts().say == nil)
        #expect(facts(avg1: 20).chip == "Busy")
        #expect(facts(avg1: 20).say?.contains("very busy (load 5.0 for each core)") == true)
        #expect(facts(degraded: true).chip == "Not answering")
        #expect(facts(degraded: true).say == "mac-studio did not answer for a while. The data can be old.")
        #expect(facts(online: false).chip == "Offline")
        #expect(facts(online: false).say?.hasPrefix("The Core cannot reach mac-studio.") == true)
    }

    @Test func whatItOffersComesFromTheDrivers() {
        let f = facts(agent: true)
        #expect(f.terminalsOn && f.agentsOn && f.terminalCapacity == 16)
        #expect(f.tools == ["claude", "codex"])
        let none = facts(pty: false)
        #expect(!none.terminalsOn && !none.agentsOn && none.tools.isEmpty && !none.commandsOn)
    }

    @Test func accessWordsFollowTheScopes() {
        #expect(RunnerFacts.access(["terminal", "read"]) == "Can open terminals here")
        #expect(
            RunnerFacts.access(["terminal", "agent", "approve"])
                == "Can open terminals, start agents and approve requests here")
        #expect(RunnerFacts.access(["admin"]) == "Can open terminals and start agents here")
        #expect(RunnerFacts.access(["read"]) == "Can watch work here")
        #expect(RunnerFacts.access(["runner"]) == nil)
    }

    @Test func revokeSaysWhatStops() {
        #expect(RunnerFacts.stops(agents: 2, terminals: 3) == "2 agents and 3 terminals")
        #expect(RunnerFacts.stops(agents: 1, terminals: 0) == "1 agent")
        #expect(RunnerFacts.stops(agents: 0, terminals: 1) == "1 terminal")
        #expect(RunnerFacts.stops(agents: 0, terminals: 0) == "nothing is running")
    }

    @Test func filtersMatchTheStates() {
        let ok = runner().self
        let busy = runner(avg1: 20)
        let off = runner(online: false)
        #expect(RunnerFacts.Filter.all.matches(off) && RunnerFacts.Filter.online.matches(ok))
        #expect(RunnerFacts.Filter.needsLook.matches(busy) && !RunnerFacts.Filter.needsLook.matches(ok))
        #expect(RunnerFacts.Filter.offline.matches(off) && !RunnerFacts.Filter.offline.matches(busy))
    }
}
