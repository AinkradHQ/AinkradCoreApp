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
        #expect(facts(avg1: 20).say?.contains("very busy: load 5.0 per core") == true)
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

    @Test func terminalShellFactMapsAndStaysOutOfTools() {
        func shell(_ v: String?) -> RunnerFacts {
            var r = runner()
            if let v { r.tools["terminal shell"] = v }
            return RunnerFacts(runner: r)
        }
        #expect(shell("Ainkrad zsh").terminalShell == .ainkrad)
        #expect(shell("login shell (zsh is not installed)").terminalShell == .login(reason: "zsh is not installed"))
        #expect(shell("login shell").terminalShell == .login(reason: nil))
        #expect(shell(nil).terminalShell == nil && shell("something new").terminalShell == nil)
        #expect(shell("Ainkrad zsh").tools.isEmpty)
    }

    @Test func accessWordsFollowTheScopes() {
        #expect(RunnerFacts.access(["terminal", "read"]) == "Can open terminals here")
        #expect(
            RunnerFacts.access(["terminal", "agent", "approve"])
                == "Can open terminals, start AI sessions and approve requests here")
        #expect(RunnerFacts.access(["admin"]) == "Can open terminals and start AI sessions here")
        #expect(RunnerFacts.access(["read"]) == "Can watch work here")
        #expect(RunnerFacts.access(["runner"]) == nil)
    }

    @Test func revokeSaysWhatStops() {
        #expect(RunnerFacts.stops(agents: 2, terminals: 3) == "2 AI sessions and 3 terminals")
        #expect(RunnerFacts.stops(agents: 1, terminals: 0) == "1 AI session")
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

/// What the Core reports since API 1.51, in words (N18, N19).
struct RunnerNewFactsTests {
    private func facts(_ edit: (inout RunnerItem) -> Void) -> RunnerFacts {
        var r = runner()
        edit(&r)
        return RunnerFacts(runner: r)
    }

    @Test func runsAsSaysWhoAndTheSandbox() {
        #expect(
            facts {
                $0.runsAsUser = "ainkrad-runner"
                $0.sandbox = "process"
            }.runsAs == "ainkrad-runner (sandboxed)")
        #expect(
            facts {
                $0.runsAsUser = "root"
                $0.runsAsRoot = true
                $0.sandbox = "none"
            }.runsAs == "root (no sandbox)")
        #expect(facts { $0.runsAsUser = "ahmed" }.runsAs == "ahmed")
        #expect(facts { _ in }.runsAs == nil)
    }

    @Test func systemJoinsTheOSNameAndTheArchitecture() {
        #expect(facts { $0.osPretty = "Ubuntu 24.04" }.system == "Ubuntu 24.04 aarch64")
        #expect(
            facts {
                $0.osPretty = nil
                $0.os = "linux"
            }.system == "linux aarch64")
        #expect(facts { $0.arch = nil }.system == nil)
    }

    @Test func accountsAnswerYesOrNoWithTheReason() {
        #expect(facts { _ in }.accountsAnswer == nil && facts { _ in }.canUseAccounts == nil)
        let ok = RunnerAccountFacts(gateway: true, subscriptionEnv: true, egressFilter: true)
        #expect(facts { $0.accounts = ok }.accountsAnswer == "Yes")
        let no = RunnerAccountFacts(
            gateway: false, subscriptionEnv: true, egressFilter: true, gatewayReason: "the gateway is off")
        #expect(facts { $0.accounts = no }.accountsAnswer == "No (the gateway is off)")
        #expect(facts { $0.accounts = no }.canUseAccounts == false)
        let blank = RunnerAccountFacts(gateway: true, subscriptionEnv: true, egressFilter: false)
        #expect(facts { $0.accounts = blank }.accountsAnswer?.hasPrefix("No (") == true)
    }

    @Test func agentAndTerminalBarsComeFromSlots() {
        let f = facts {
            $0.slots = RunnerSlotFacts(agentsUsed: 2, agentsCapacity: 2, terminalsUsed: 3, terminalsCapacity: 16)
        }
        #expect(f.agentBar?.text == "2 of 2 AI sessions" && f.agentBar?.full == true)
        #expect(f.terminalBar(fallbackUsed: 9)?.text == "3 of 16 terminals")
        let off = facts {
            $0.slots = RunnerSlotFacts(agentsUsed: 0, agentsCapacity: nil, terminalsUsed: 0, terminalsCapacity: nil)
        }
        #expect(off.agentBar == nil && off.terminalBar(fallbackUsed: 0) == nil)
        // No slots from the Core: the old pty capacity and this Mac's own count.
        #expect(facts { _ in }.agentBar == nil)
        #expect(facts { _ in }.terminalBar(fallbackUsed: 2)?.text == "2 of 16 terminals")
    }

    @Test func toolsCarryTheirVersions() {
        #expect(facts { $0.tools = ["codex": "0.9", "claude": "2.1.318"] }.tools == ["claude 2.1.318", "codex 0.9"])
    }

    @Test func theBuiltInRunnerComesFirst() {
        var a = runner("a")
        var b = runner("b")
        b.builtIn = true
        #expect(RunnerFacts.ordered([a, b]).map(\.id) == ["b", "a"])
        a.builtIn = true
        #expect(RunnerFacts.ordered([a, b]).map(\.id) == ["a", "b"])
    }

    @Test func updateChipOnlyWhenTheCoreSaysSo() {
        #expect(!facts { _ in }.updateAvailable)
        #expect(facts { $0.updateAvailable = true }.updateAvailable)
    }

    @Test("the AI sessions row names the AI tools and their short versions")
    func aiToolsLine() {
        #expect(RunnerTools.aiLine([:]) == nil)
        #expect(RunnerTools.aiLine(["git": "2.47"]) == nil)
        #expect(RunnerTools.aiLine(["claude": "2.1.318", "codex": "0.9.2"]) == "Claude Code 2.1, Codex 0.9")
        #expect(RunnerTools.aiLine(["codex": ""]) == "Codex")
    }
}
