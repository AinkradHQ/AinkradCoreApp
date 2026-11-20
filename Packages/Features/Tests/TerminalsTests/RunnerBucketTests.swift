import Testing

@testable import Terminals

struct RunnerBucketTests {
    @Test func aRunnerLandsInOneOfFourBuckets() {
        var idle = runner()
        idle.load = 0
        #expect(RunnerBucket(of: idle) == .idle)
        #expect(RunnerBucket(of: runner()) == .working)
        var busyOnSlots = runner()
        busyOnSlots.slots = RunnerSlotFacts(agentsUsed: 1, agentsCapacity: 2, terminalsUsed: 0, terminalsCapacity: 4)
        #expect(RunnerBucket(of: busyOnSlots) == .working)
        #expect(RunnerBucket(of: runner(degraded: true)) == .attention)
        #expect(RunnerBucket(of: runner(online: false)) == .offline)
    }

    @Test func theHeaderSentenceCountsWhatIsBusyOrDown() {
        #expect(
            RunnerBucket.sentence([runner(), runner("r2"), runner("r3", online: false)]) == " 2 are busy, 1 is offline."
        )
        #expect(RunnerBucket.sentence([]) == "")
    }

    @Test func aWorkingLineSaysWhatIsRunning() {
        var r = runner()
        r.slots = RunnerSlotFacts(agentsUsed: 2, agentsCapacity: 4, terminalsUsed: 1, terminalsCapacity: 4)
        #expect(RunnerRow.line(r, .working, terminals: 0) == "Working on 2 AI sessions and 1 terminal")
        #expect(RunnerRow.line(r, .idle, terminals: 0) == "Idle · ready for work")
    }

    @Test func aRunnerGettingItsToolsIsUpdating() {
        #expect(RunnerBucket.of(runner(), updating: true) == .updating)
        #expect(RunnerBucket.of(runner(online: false), updating: true) == .offline)
        #expect(RunnerBucket.of(runner(), updating: false) == .working)
        #expect(RunnerBucket.updating.chip == "Updating")
        #expect(
            RunnerBucket.sentence([runner("r1"), runner("r2")], updating: ["r2"]) == " 1 is busy, 1 is getting ready.")
        #expect(RunnerRow.line(runner(), .updating, terminals: 0) == "Getting ready · installing tools")
        let i = ToolInstall(op: "o", tool: "node", state: .running, percent: 64, step: "")
        #expect(
            RunnerRow.line(runner(), .updating, terminals: 0, install: i) == "Getting ready · installing Node.js · 64%")
    }

    @MainActor @Test func theCoreReportsInstallsOnlyFromMinor95() {
        let m = TerminalsModel(host: FakeHost(), service: FakeService())
        m.runners = [runner("r1")]
        m.toolInstall(["runner": "r1", "tool": "node", "state": "running", "percent": "64"])
        #expect(m.bucket(m.runners[0]) == .working, "an older Core never shows Updating")
        m.showsUpdates = true
        #expect(m.bucket(m.runners[0]) == .updating && m.updatingIDs == ["r1"])
    }
}
