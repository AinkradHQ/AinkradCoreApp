import Testing

@testable import Shell

@MainActor
struct RunnerUpdatesTests {
    private func event(_ state: String, tool: String = "node", percent: String = "64") -> [String: String] {
        ["runner": "r1", "tool": tool, "state": state, "percent": percent, "step": "Downloading Node"]
    }

    @Test func aRunningInstallIsKeptAndAFinishedOneClearsIt() {
        var u: [String: RunnerUpdate] = [:]
        RunnerUpdates.apply(event("running"), to: &u)
        #expect(u["r1"]?.fraction == 0.64 && u["r1"]?.toolName == "Node.js")
        RunnerUpdates.apply(event("done", tool: "git"), to: &u)  // another tool finishing leaves this one
        #expect(u["r1"] != nil)
        RunnerUpdates.apply(event("done"), to: &u)
        #expect(u["r1"] == nil)
    }

    @Test func anOlderCoreNeverShowsUpdating() {
        let shell = ShellModel()
        shell.toolInstall(event("running"))
        #expect(shell.runnerUpdates.isEmpty)
        shell.showsRunnerUpdates = true
        shell.toolInstall(event("running"))
        #expect(shell.runnerUpdates["r1"]?.percent == 64)
    }
}
