import Foundation
import Testing

@testable import Projects

struct ProjectStatsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func run(_ id: String, _ state: String, daysAgo: Double) -> RunRecord {
        RunRecord(
            id: id, state: state, configID: 1, environment: nil, runner: "d",
            startedAt: now.addingTimeInterval(-daysAgo * 86_400), stoppedAt: nil, stopReason: nil, error: nil)
    }
    private func repo(_ n: String, failed: Bool) -> RepoItem {
        RepoItem(
            id: 1, name: n, remoteURL: "u", branch: "main", primary: true, fetchedAt: now.addingTimeInterval(-60),
            fetchError: failed ? "boom" : nil)
    }

    @Test func countsOnlyTheLastWeekAndTheLiveOnes() {
        let s = ProjectStats(
            repos: [repo("a", failed: false)],
            runs: [run("1", "running", daysAgo: 1), run("2", "stopped", daysAgo: 3), run("3", "stopped", daysAgo: 9)],
            now: now)
        #expect(s.runsThisWeek == 2 && s.runningNow == 1 && s.health == "All copied" && s.healthFraction == 1)
    }

    @Test func aFailedCopyNeedsYou() {
        let s = ProjectStats(repos: [repo("a", failed: false), repo("b", failed: true)], runs: [], now: now)
        #expect(s.health == "Needs you" && s.needsYou == 1 && s.healthFraction == 0.5)
    }

    @Test func theTimelineIsNewestFirstAndCapped() {
        let t = ActivityLine.timeline(
            repos: [repo("a", failed: false)], runs: [run("1", "failed", daysAgo: 1)], names: [1: "Dev"], limit: 1)
        #expect(t.count == 1 && t[0].title == "a copied")
        #expect(
            ActivityLine.timeline(repos: [], runs: [run("1", "failed", daysAgo: 1)], names: [1: "Dev"])[0].title
                == "Dev failed to start")
    }
}
