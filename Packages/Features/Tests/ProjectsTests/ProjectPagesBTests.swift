import Foundation
import Testing

@testable import Projects

struct ProjectPagesBTests {
    @Test func kindsToggleSeveralButOtherOnlyAlone() {
        typealias M = ProjectsModel
        #expect(M.toggled([.web], .app) == [.web, .app])
        #expect(M.toggled([.web, .app], .web) == [.app])
        // The last one cannot be switched off.
        #expect(M.toggled([.web], .web) == [.web])
        // "Not software" replaces the rest, and a software type replaces it.
        #expect(M.toggled([.web, .app], .other) == [.other])
        #expect(M.toggled([.other], .infra) == [.infra])
        #expect(M.toggled([.other], .other) == [.other])
        // The order is the tiles' order whatever order they were picked in.
        #expect(M.toggled([.infra], .web) == [.web, .infra])
    }

    @Test func runningSavesAsOneChange() {
        var p = ProjectItem(id: 1, slug: "a", name: "A", description: "", expose: false, repos: [], updatedAt: nil)
        p.runner = "auto"
        var l = p.limits
        #expect(ProjectsModel.runningPatch(from: p, runner: "auto", limits: l).isEmpty)
        l.cpus = 4
        l.memoryMb = 8192
        let patch = ProjectsModel.runningPatch(from: p, runner: "this_mac", limits: l)
        #expect(patch.runner == "this_mac" && patch.cpuLimit == 4 && patch.memLimitMb == 8192)
        // Only what differs goes up.
        #expect(patch.idleMinutes == nil && patch.idleNever == nil)
    }

    @Test func kindsGoUpAsAList() throws {
        let body = try LiveProjectsService.patchBody(ProjectPatch(kinds: ["web", "app"]))
        let o = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(o["kinds"] as? [String] == ["web", "app"] && o["kind"] == nil)
    }

    private func run(_ id: String, _ state: String, ago minutes: Double) -> RunRecord {
        RunRecord(
            id: id, state: state, configID: nil, environment: nil, runner: "r",
            startedAt: Date(timeIntervalSince1970: 1_800_000_000 - minutes * 60),
            stoppedAt: Date(timeIntervalSince1970: 1_800_000_000 - minutes * 60 + 60), stopReason: nil, error: nil)
    }

    @Test func buildsGroupByDayNewestFirst() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00 UTC
        let runs = [run("old", "stopped", ago: 60 * 24 * 3), run("y", "failed", ago: 60 * 12), run("a", "stopped", ago: 10), run("b", "failed", ago: 5)]
        let days = BuildWords.days(runs, failedOnly: false, now: now, calendar: cal)
        #expect(days.map(\.title).prefix(2) == ["Today", "Yesterday"])
        #expect(days[0].runs.map(\.id) == ["b", "a"] && days.count == 3)
        let failed = BuildWords.days(runs, failedOnly: true, now: now, calendar: cal)
        #expect(failed.flatMap(\.runs).map(\.id) == ["b", "y"])
        #expect(BuildWords.days([], failedOnly: false, now: now, calendar: cal).isEmpty)
    }

    @Test func wordsForDurationAndIdle() {
        #expect(BuildWords.duration(9) == "9 s" && BuildWords.duration(192) == "3 min 12 s")
        #expect(BuildWords.duration(300) == "5 min" && BuildWords.duration(3840) == "1 h 4 min")
        #expect(BuildWords.idle("idle 4 min of 30")?.now == 4 && BuildWords.idle("idle 4 min of 30")?.of == 30)
        #expect(BuildWords.idle(nil) == nil && BuildWords.idle("running") == nil)
    }
}
