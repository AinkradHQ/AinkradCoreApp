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
    /// The tools an agent can run here, from the agent driver's slots (`claude`, `codex`).
    var tools: [String] { (runner.drivers.first { $0.name == "agent" }?.slots.keys.sorted()) ?? [] }
    var commandsOn: Bool { runner.drivers.contains { $0.commands.contains("exec.run") } }
    var terminalCapacity: Int? { runner.drivers.first { $0.name == "pty" }?.capacity }

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
            return "\(n) is very busy (load \(load) for each core). New work waits or goes to another runner."
        }
    }

    /// "Linux aarch64" is not reported (no OS), only the CPU architecture.
    var system: String? { runner.arch }

    /// What revoking stops, in the confirm card: "2 agents and 3 terminals".
    static func stops(agents: Int, terminals: Int) -> String {
        let a = agents == 1 ? "1 agent" : "\(agents) agents"
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
        if scopes.contains("agent") || scopes.contains("admin") { does.append("start agents") }
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
