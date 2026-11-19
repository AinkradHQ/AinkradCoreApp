import Foundation

// The runner tool-install state the Runners dropdown and the Runners app read (E2 round 2). E8 builds the report on the Core:
// `tools.status` on the runner and `runner.tool_install` events `{op, runner, tool, state, percent, step, reason}` as text
// (state `running`, `done` or `failed`, percent 0...100). Everything that knows those field names lives here, so a change in
// E8's final shape is one edit.

/// A tool being installed or updated on one runner.
public struct RunnerUpdate: Sendable, Equatable {
    public let runner: String
    public let tool: String
    public let percent: Int
    public let step: String
    /// "Claude", "Node.js": the plain name of the tool.
    public var toolName: String { RunnerUpdates.name(tool) }
    /// 0...1 for a meter.
    public var fraction: Double { Double(min(100, max(0, percent))) / 100 }
    public init(runner: String, tool: String, percent: Int, step: String) {
        self.runner = runner
        self.tool = tool
        self.percent = percent
        self.step = step
    }
}

public enum RunnerUpdates {
    /// One event: a running install is kept (the newest per runner), a finished or failed one clears that runner's entry.
    public static func apply(_ f: [String: String], to updates: inout [String: RunnerUpdate]) {
        guard let runner = f["runner"], let tool = f["tool"], let state = f["state"] else { return }
        if state == "running" {
            updates[runner] = RunnerUpdate(
                runner: runner, tool: tool, percent: Int(f["percent"] ?? "") ?? 0, step: f["step"] ?? "")
        } else if updates[runner]?.tool == tool {
            updates[runner] = nil
        }
    }

    private static let names = [
        "claude": "Claude", "codex": "Codex", "opencode": "OpenCode", "agy": "Antigravity", "node": "Node.js",
        "git": "Git", "python": "Python", "go": "Go", "rust": "Rust", "docker": "Docker",
    ]
    public static func name(_ tool: String) -> String { names[tool] ?? tool }
}
