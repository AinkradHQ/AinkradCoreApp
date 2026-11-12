import CoreUI
import Foundation

/// What a runner is and does, in plain words, from what `GET /runners` reports (N18, N19). Anything the Core does not report is
/// nil here, and the views say "Not reported yet" for it instead of guessing.
struct RunnerFacts: Equatable {
    let runner: RunnerItem
    var status: RunnerStatus { RunnerStatus(runner) }

    /// The chip word: Online, Busy, Not answering, Offline.
    var chip: String {
        switch status {
        case .ok: "Online"
        case .busy: "Busy"
        case .degraded: "Not answering"
        case .off: "Offline"
        }
    }

    var terminalsOn: Bool { runner.hasPty }
    var agentsOn: Bool { runner.drivers.contains { $0.name == "agent" } }
    /// The tools an agent can run here with their versions ("claude 2.1.318"), else the harness names the agent driver lists.
    var tools: [String] {
        if !runner.tools.isEmpty {
            return runner.tools.keys.sorted().map { k in
                let v = runner.tools[k] ?? ""
                return v.isEmpty ? k : "\(k) \(v)"
            }
        }
        return (runner.drivers.first { $0.name == "agent" }?.slots.keys.sorted()) ?? []
    }
    var commandsOn: Bool { runner.drivers.contains { $0.commands.contains("exec.run") } }
    var terminalCapacity: Int? {
        runner.slots != nil ? runner.slots?.terminalsCapacity : runner.drivers.first { $0.name == "pty" }?.capacity
    }

    /// The agents bar, from `slots`; nil when the agent driver is off or the Core did not report slots.
    var agentBar: (text: String, value: Double, full: Bool)? {
        guard let s = runner.slots, let cap = s.agentsCapacity else { return nil }
        let n = s.agentsUsed
        return ("\(n) of \(cap) AI sessions", cap > 0 ? min(1, Double(n) / Double(cap)) : 0, cap > 0 && n >= cap)
    }

    /// The terminals bar; `fallbackUsed` is the count this Mac listed when the Core sent no `slots`.
    func terminalBar(fallbackUsed: Int) -> (text: String, value: Double)? {
        guard let cap = terminalCapacity else { return nil }
        let n = runner.slots?.terminalsUsed ?? fallbackUsed
        return ("\(n) of \(cap) terminals", cap > 0 ? min(1, Double(n) / Double(cap)) : 0)
    }

    /// "Runs as" row: "ainkrad-runner (sandboxed)", "root (no sandbox)"; nil when the Core did not say who.
    var runsAs: String? {
        let who = runner.runsAsRoot == true ? "root" : runner.runsAsUser
        guard let who, !who.isEmpty else { return nil }
        switch runner.sandbox {
        case "process": return "\(who) (sandboxed)"
        case "none": return "\(who) (no sandbox)"
        default: return who
        }
    }

    /// "Yes", or "No (reason)"; nil when the Core did not report it.
    var accountsAnswer: String? {
        guard let a = runner.accounts else { return nil }
        let checks: [(Bool, String?, String)] = [
            (a.gateway, a.gatewayReason, "it cannot reach the account gateway"),
            (a.subscriptionEnv, a.subscriptionEnvReason, "it cannot pass a plan sign-in to AI sessions"),
            (a.egressFilter, a.egressFilterReason, "it cannot limit where AI sessions connect"),
        ]
        guard let bad = checks.first(where: { !$0.0 }) else { return "Yes" }
        return "No (\(bad.1 ?? bad.2))"
    }
    var canUseAccounts: Bool? { accountsAnswer.map { $0 == "Yes" } }

    /// The sentence under the name when the runner is not simply fine.
    var say: String? {
        let n = runner.name
        switch status {
        case .ok: return nil
        case .degraded: return "\(n) did not answer for a while. The data can be old."
        case .off:
            return "The Core cannot reach \(n). Nothing new starts there. Work continues when it is back."
        case .busy:
            let load = runner.perCore.map { coreDecimal($0, 1) } ?? "high"
            return "\(n) is very busy: load \(load) per core. New work waits or goes to another runner."
        }
    }

    /// "Ubuntu 24.04 aarch64": the OS name and the CPU architecture, whichever the runner reported.
    var system: String? {
        let parts = [runner.osPretty ?? runner.os, runner.arch].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var updateAvailable: Bool { runner.updateAvailable == true }

    /// The list order: this Core's built-in runner first, the rest as they came.
    static func ordered(_ runners: [RunnerItem]) -> [RunnerItem] {
        runners.filter(\.builtIn) + runners.filter { !$0.builtIn }
    }

    /// What revoking stops, in the confirm card: "2 AI sessions and 3 terminals".
    static func stops(agents: Int, terminals: Int) -> String {
        let a = agents == 1 ? "1 AI session" : "\(agents) AI sessions"
        let t = terminals == 1 ? "1 terminal" : "\(terminals) terminals"
        switch (agents, terminals) {
        case (0, 0): return "nothing is running"
        case (_, 0): return a
        case (0, _): return t
        default: return "\(a) and \(t)"
        }
    }

    /// What a person's device may do here, from its scopes; nil when it has no part in this runner.
    static func access(_ scopes: [String]) -> String? {
        var does: [String] = []
        if scopes.contains("terminal") || scopes.contains("admin") { does.append("open terminals") }
        if scopes.contains("agent") || scopes.contains("admin") { does.append("start AI sessions") }
        if scopes.contains("approve") { does.append("approve requests") }
        if does.isEmpty { return scopes.contains("read") ? "Can watch work here" : nil }
        let list = does.count > 1 ? does.dropLast().joined(separator: ", ") + " and " + does.last! : does[0]
        return "Can \(list) here"
    }

    /// The filter chips on the list.
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case online = "Online"
        case needsLook = "Needs a look"
        case offline = "Offline"
        var id: String { rawValue }
        func matches(_ r: RunnerItem) -> Bool {
            switch (self, RunnerStatus(r)) {
            case (.all, _): true
            case (.online, .ok): true
            case (.needsLook, .busy), (.needsLook, .degraded): true
            case (.offline, .off): true
            default: false
            }
        }
    }
}
