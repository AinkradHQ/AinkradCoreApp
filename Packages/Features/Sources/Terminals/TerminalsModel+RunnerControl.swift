import CoreKit
import Foundation

/// A line under the runner's switches: the restart notice, or why the Core refused.
struct RunnerNote: Equatable {
    var text: String
    var refused: Bool
}

/// The tools a runner page offers to install, in the order shown, with their plain names.
enum RunnerTools {
    static let all: [(id: String, name: String, help: String)] = [
        ("claude", "Claude Code", "Runs AI sessions with your Claude account."),
        ("codex", "Codex", "Runs AI sessions with your OpenAI account."),
        ("git", "Git", "Lets AI sessions clone and push repositories."),
        ("node", "Node.js", "Needed by many tools."),
        ("python", "Python", "Needed by many tools."),
        ("go", "Go", "Builds Go projects."),
        ("rust", "Rust", "Builds Rust projects."),
        ("docker", "Docker", "Runs containers."),
    ]

    /// The refusal in plain words; the Core's own reason is already a sentence.
    static func why(_ error: Error, runner: String) -> String {
        switch CoreError.unwrapping(error) {
        case .http(_, let code, let message)?:
            switch code {
            case "runner_offline": return "\(runner) is offline. Try again when it is back."
            case "unsupported_command": return "\(runner) runs an older version that cannot do this. Update it first."
            default: return message
            }
        case let e?: return e.localizedDescription
        case nil: return error.localizedDescription
        }
    }
}

extension TerminalsModel {
    /// Changes what a runner offers. `restarting` tells the person the runner restarts for a moment.
    func setPolicy(_ r: RunnerItem, terminals: Bool? = nil, agents: Bool? = nil, capacity: Int? = nil) async {
        let now =
            r.policy
            ?? RunnerPolicy(terminals: r.hasPty, agents: r.drivers.contains { $0.name == "agent" }, capacity: 2)
        let want = RunnerPolicy(
            terminals: terminals ?? now.terminals, agents: agents ?? now.agents,
            capacity: min(8, max(1, capacity ?? now.capacity)))
        guard want != now, !policyBusy.contains(r.id) else { return }
        policyBusy.insert(r.id)
        policyNote[r.id] = nil
        defer { policyBusy.remove(r.id) }
        do {
            let done = try await host.elevated(
                "Change what \(r.name) offers", done: "changed", keepsEdit: true
            ) { try await service.setPolicy(r.id, want) }
            if let i = runners.firstIndex(where: { $0.id == r.id }) { runners[i].policy = done.policy }
            if done.restarting {
                policyNote[r.id] = RunnerNote(
                    text: "\(r.name) restarts for a moment to apply this. Work that is running on it may stop.",
                    refused: false)
            }
            resync()
        } catch is ElevationDeclined {
        } catch {
            policyNote[r.id] = RunnerNote(text: RunnerTools.why(error, runner: r.name), refused: true)
        }
    }

    /// Starts a tool install; progress arrives as `runner.tool_install` events.
    func installTool(_ r: RunnerItem, _ tool: String) async {
        if installs[r.id]?[tool]?.state == .running { return }
        installs[r.id, default: [:]][tool] = ToolInstall(
            op: "", tool: tool, state: .running, percent: 0, step: "Starting…")
        do {
            let op = try await host.elevated("Install \(tool) on \(r.name)", done: "started") {
                try await service.installTool(r.id, tool: tool)
            }
            installs[r.id]?[tool]?.op = op
        } catch is ElevationDeclined {
            installs[r.id]?[tool] = nil
        } catch {
            installs[r.id]?[tool] = ToolInstall(
                op: "", tool: tool, state: .failed, percent: 0, step: "", reason: RunnerTools.why(error, runner: r.name)
            )
        }
    }

    /// One `runner.tool_install` event.
    public func toolInstall(_ f: [String: String]) {
        guard let runner = f["runner"], let tool = f["tool"], let state = f["state"].flatMap(ToolInstall.State.init)
        else {
            return
        }
        installs[runner, default: [:]][tool] = ToolInstall(
            op: f["op"] ?? "", tool: tool, state: state, percent: Int(f["percent"] ?? "") ?? 0,
            step: f["step"] ?? "", reason: f["reason"])
        if state != .running { resync() }
    }
}

/// What the Add runner wizard shows and changes for the runner that just connected (N17 step 5).
public struct RunnerSettings: Equatable, Sendable {
    public let id: String
    public let name: String
    public let terminals: Bool
    public let agents: Bool
    public let capacity: Int
    /// False for a runner too old to take a policy: the wizard says to update it.
    public let editable: Bool
    public let busy: Bool
    public let note: String?
    public let noteIsRefusal: Bool
}

extension TerminalsModel {
    /// The runner with this name, as its settings step needs it; nil until it shows in the Core's list.
    public func runnerSettings(named name: String) -> RunnerSettings? {
        guard let r = runners.first(where: { $0.name == name }) else { return nil }
        let p = r.policy
        let n = policyNote[r.id]
        return RunnerSettings(
            id: r.id, name: r.name, terminals: p?.terminals ?? r.hasPty,
            agents: p?.agents ?? r.drivers.contains { $0.name == "agent" }, capacity: p?.capacity ?? 2,
            editable: p != nil, busy: policyBusy.contains(r.id), note: n?.text, noteIsRefusal: n?.refused ?? false)
    }

    public func changeRunner(_ id: String, terminals: Bool? = nil, agents: Bool? = nil, capacity: Int? = nil) async {
        guard let r = runners.first(where: { $0.id == id }) else { return }
        await setPolicy(r, terminals: terminals, agents: agents, capacity: capacity)
    }
}
