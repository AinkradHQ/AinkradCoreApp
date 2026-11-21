import Foundation

/// What the Machines app reads from the terminals model: the one status, the work on a machine, load and the problem line.
extension TerminalsModel {
    var thisMacID: String? { host.thisMacRunnerID }

    /// Does work, in list order.
    var workingMachines: [RunnerItem] { Machines.ordered(runners, thisMac: thisMacID) }

    /// Signs in only; nil before the devices were read.
    var signInMachines: [SignInMachine]? {
        host.runnerHost?.signInMachines().map {
            Machines.signInOnly($0, thisMacWorks: thisMacID.map { id in runners.contains { $0.id == id } } ?? false)
        }
    }

    func machineName(_ r: RunnerItem) -> String { Machines.name(r, thisMac: thisMacID) }

    /// The AI sessions running on a runner, by name.
    func work(on id: String) -> [RunnerWork] { host.runnerHost?.agentWork(on: id) ?? [] }

    /// The terminals still open on a runner.
    func terminals(on id: String) -> [TerminalItem] { items.filter { $0.runner == id && !$0.isEnded } }

    func waiting(on id: String) -> (agents: Int, terminals: Int) { (work(on: id).count, terminals(on: id).count) }

    var problem: MachineProblem? {
        Machines.problem(runners, installs: installs, thisMac: thisMacID, waiting: { [self] in waiting(on: $0) })
    }

    func busy(_ r: RunnerItem) -> Double? { Machines.busy(r, cpuPct: hardware[r.id]?.cpuPct) }

    /// The install running on a runner now, either one this app asked for or one the runner reports.
    func runningInstall(_ id: String) -> ToolInstall? {
        installs[id]?.values.sorted { $0.tool < $1.tool }.first { $0.state == .running }
    }

    /// What a machine is doing, in one plain line: the AI session and the terminals, or why it is not working.
    func line(_ r: RunnerItem) -> String {
        let status = MachineStatus(r)
        let terms = terminals(on: r.id).count
        let termWords = terms == 0 ? nil : terms == 1 ? "1 terminal" : "\(terms) terminals"
        switch status {
        case .offline:
            let since = r.lastSeen.map { "Offline since \(Machines.when($0))" } ?? "Offline"
            let w = waiting(on: r.id)
            return [since, Machines.waiting(agents: w.agents, terminals: w.terminals)?.lowercasedFirst]
                .compactMap { $0 }.joined(separator: " · ")
        case .notAnswering:
            return "Not answering" + (r.lastSeen.map { " since \(Machines.when($0))" } ?? "")
        default:
            let work = work(on: r.id)
            if let first = work.first {
                let doing = first.tool.map { "\($0) is on “\(first.title)”" } ?? "Working on “\(first.title)”"
                let more = work.count > 1 ? "\(work.count - 1) more" : nil
                return [doing, more, termWords].compactMap { $0 }.joined(separator: " · ")
            }
            if let termWords { return termWords + " open" }
            if let i = runningInstall(r.id) { return "Installing \(RunnerTools.name(i.tool)) · \(i.percent)%" }
            if RunnerStatus(r) == .busy { return "Very busy: new work waits or goes elsewhere" }
            return r.builtIn ? "Inside your Core · ready for work" : "Ready for work"
        }
    }

    /// Asks the Core to install a pinned AI tool a runner is still missing, once per tool per launch. Only while the session
    /// is already elevated: the Core wants Touch ID for it, and a prompt nobody asked for is worse than waiting. Otherwise
    /// the machine's page offers one Install button for all of them.
    func autoInstall() async {
        guard host.isElevated else { return }
        await requestMissing(AutoInstall.due(runners, installs: installs, requested: requestedInstalls))
    }

    /// Installs every pinned tool a machine is missing (the page's one button; Touch ID once).
    func installMissing(_ r: RunnerItem) async {
        let due = AutoInstall.pinned.filter { r.tools[$0] == nil && installs[r.id]?[$0]?.state != .running }
        await requestMissing(due.map { (r.id, $0) })
    }

    private func requestMissing(_ due: [(runner: String, tool: String)]) async {
        for d in due {
            requestedInstalls.insert("\(d.runner)/\(d.tool)")
            guard let r = runner(d.runner) else { continue }
            await installTool(r, d.tool)
        }
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
