import Foundation
import Testing

@testable import Admin
@testable import Brain
@testable import Shell

@MainActor
struct ActivityChecksTests {
    func make(_ s: SampleBrainService.Scenario = .init(), pace: Duration = .zero) async -> (BrainModel, FakeHost) {
        let host = FakeHost()
        let model = BrainModel(host: host)
        model.use(SampleBrainService(s, pace: pace))
        await model.reload()
        return (model, host)
    }

    func loaded(_ s: SampleBrainService.Scenario = .init()) async -> (BrainModel, FakeHost) {
        let (m, h) = await make(s)
        m.activity.enter()
        await m.activity.load()
        await m.checks.load()
        return (m, h)
    }

    // MARK: Activity

    @Test func startsOnTheViewingRoomAndFollowsThePicker() async {
        let (m, _) = await loaded()
        #expect(m.activity.filter.room == .room("ainkrad"))
        #expect(m.activity.visible.allSatisfy { $0.room == "ainkrad" })
        // Clearing the filters keeps the room picker's room.
        m.activity.filter.result = .blocked
        #expect(m.activity.filter.isActive)
        m.activity.clearFilters()
        #expect(m.activity.filter.room == .room("ainkrad") && !m.activity.filter.isActive)
        // Switching the viewing room moves the starting filter with it.
        m.view("voutra")
        m.activity.enter()
        #expect(m.activity.filter.room == .room("voutra"))
    }

    @Test func filtersCombine() async {
        let (m, _) = await loaded()
        let a = m.activity!
        a.filter.room = .all
        a.filter.kind = .blocked
        #expect(!a.visible.isEmpty && a.visible.allSatisfy { $0.result == .blocked })
        a.filter.kind = .sync
        #expect(a.visible.allSatisfy { $0.kind == .sync })
        a.filter.kind = .all
        a.filter.room = .none
        #expect(a.visible.allSatisfy { $0.room == nil } && !a.visible.isEmpty)
        a.filter = ActivityFilter()
        a.filter.who = "You"
        a.filter.result = .ok
        #expect(a.visible.allSatisfy { $0.actor == "You" && $0.result == .ok })
        a.filter.result = .failed
        #expect(a.visible.isEmpty)
        #expect(a.filter.isActive)
        a.clearFilters()
        #expect(!a.filter.isActive && !a.visible.isEmpty)
    }

    @Test func aSealedRoomsRowsNeverShow() async {
        let (m, _) = await loaded()
        let sealed = ActivityEvent(
            seq: 1, at: "now", actor: "You", device: "Mac", action: "Searched", room: "althaqeel", result: .ok,
            kind: .access)
        m.activity.receive(sealed)
        m.activity.filter.room = .all
        #expect(!m.activity.visible.contains { $0.room == "althaqeel" })
    }

    @Test func blockedRowsNameTheRule() async {
        let (m, _) = await loaded()
        m.activity.filter.room = .all
        let blocked = m.activity.events.filter { $0.result == .blocked }
        #expect(!blocked.isEmpty)
        for e in blocked {
            #expect(e.rule != nil && e.reason != nil)
            let words = BrainWords.blockedBy(e.rule?.name ?? "")
            #expect(words.hasPrefix("Blocked by: "))
        }
        let local = blocked.first { $0.seq == 2037 }
        #expect(local?.rule?.name == "Room is local only")
        #expect(local?.resultCode == "local_only")
        for b in EgressBlock.allCases { #expect(!b.sentence.isEmpty && !b.ruleName.isEmpty) }
    }

    @Test func aLocalOnlyRoomHasNothingInTheEgressLog() async {
        let (m, _) = await loaded()
        m.activity.egressRoom = "personal"
        await m.activity.loadEgress()
        #expect(m.activity.egress.isEmpty)
        #expect(m.activity.egressRoomSummary?.provider == .local)
        #expect(BrainWords.leftNothing("Personal") == "Nothing from Personal has left this Mac")
        m.activity.egressRoom = "ainkrad"
        await m.activity.loadEgress()
        #expect(m.activity.egress.contains { !$0.sent } && m.activity.egress.allSatisfy { $0.room == "ainkrad" })
    }

    @Test func loadStatesAndRetry() async {
        var s = SampleBrainService.Scenario()
        s.activityError = true
        let (m, _) = await make(s)
        m.activity.enter()
        await m.activity.load()
        guard case .failed(_, let code) = m.activity.phase else {
            Issue.record("expected failure")
            return
        }
        #expect(code == "audit_unavailable")
        m.activity.cancelError()
        #expect(m.activity.phase == .ready)
        var q = SampleBrainService.Scenario()
        q.noActivity = true
        let (e, _) = await make(q)
        e.activity.enter()
        await e.activity.load()
        #expect(e.activity.phase == .ready && e.activity.events.isEmpty)
    }

    @Test func aLiveRowArrivesAtTheTopAndSettles() async {
        let (m, _) = await loaded()
        let before = m.activity.events.count
        let e = ActivityEvent(
            seq: 9000, at: "now", actor: "Claude Code (sample)", device: "Mac Studio", action: "Searched",
            room: "ainkrad", result: .ok, kind: .access)
        m.activity.receive(e)
        m.activity.receive(e)
        #expect(m.activity.events.count == before + 1 && m.activity.events.first == e)
        #expect(m.activity.fresh == [e.id] && m.activity.announcement == "New activity: Searched")
    }

    @Test func detailsAreIdsAndCodesNeverContent() async {
        let (m, _) = await loaded()
        m.activity.filter.room = .all
        let id = try! Regex("^[a-z0-9._/, -]+$")
        for e in m.activity.events {
            for l in e.details {
                #expect(l.value != e.action && l.value != e.reason, "detail leaks wording: \(l.value)")
                #expect(l.value.wholeMatch(of: id) != nil, "not an id or code: \(l.value)")
            }
        }
        await m.activity.loadEgress()
        for c in m.activity.egress {
            for l in c.details { #expect(l.value.wholeMatch(of: id) != nil, "\(l.value)") }
        }
    }

    @Test func notificationTextCarriesNoContent() async {
        let (m, _) = await loaded()
        let titles = ["ship the Brain pane", "pull requests target", "no gold in the UI", "customers pay within"]
        for t in m.bellTexts + ["", BrainWords.pausedLine(names: m.pausedNames), BrainWords.pausedWhy] {
            for n in titles { #expect(!t.contains(n)) }
        }
        for k in [NeedKind.paused, .blocked, .check] {
            #expect(!BrainWords.push(kind: k, n: 2).contains("Optimus"))
        }
    }

    // MARK: Checks

    @Test func sevenChecksAndHousekeeping() async {
        let (m, _) = await loaded()
        let c = m.checks!
        #expect(c.items.map(\.id) == ["leakage", "recall", "speed", "sync", "restore", "keys", "providers"])
        #expect(c.housekeeping.count == 2)
        #expect(c.items.allSatisfy { $0.history.count <= 7 })
        #expect(c.summary == "1 check is due.")
        #expect(c.report.pilot.count == 8)
        #expect(c.report.pilot.first { $0.code == "C12" }?.result == .pass)
    }

    @Test func runningMovesThroughStatesAndEndsWithAResult() async {
        let (m, _) = await make(.init(), pace: .milliseconds(40))
        await m.checks.load()
        let c = m.checks!
        let t = Task { await c.run("speed") }
        #expect(await until { c.anyRunning })
        #expect(c.anyRunning && c.state(c.items.first { $0.id == "speed" }!) == .running)
        await t.value
        #expect(!c.anyRunning)
        let item = c.items.first { $0.id == "speed" }
        #expect(item?.last == "Just now" && item.map(c.state) == .pass)
        #expect(item?.history.count == 7)
    }

    @Test func aFailedLeakageRunPausesAndAPassingRerunDoesNotClear() async throws {
        let (m, h) = await make()
        await m.checks.load()
        let svc = try #require(m.service as? SampleBrainService)
        await svc.failNext(["leakage"])
        await m.checks.run("leakage")
        #expect(m.health == .paused && m.pausedNames == ["AutomotiveAi", "Optimus"])
        #expect(m.checks.items.first { $0.id == "leakage" }?.outcome == .fail)
        await m.checks.run("leakage")
        #expect(m.checks.items.first { $0.id == "leakage" }?.outcome == .pass)
        #expect(m.health == .paused, "a passing re-run must not clear Paused")
        // Cancelled Touch ID leaves it paused.
        h.declines = true
        #expect(await m.clearPaused() == false)
        #expect(m.health == .paused)
        // Approved Touch ID clears it, and the check says so.
        h.declines = false
        #expect(await m.clearPaused())
        #expect(m.health != .paused && m.pausedNames.isEmpty)
        #expect(h.reasons.count == 2)
        await m.checks.load()
        #expect(m.checks.items.first { $0.id == "leakage" }?.clearedAfter == true)
    }

    @Test func pausedUsesOneSentenceEverywhere() async {
        var s = SampleBrainService.Scenario()
        s.paused = true
        let (m, _) = await loaded(s)
        #expect(m.health == .paused)
        let line = BrainWords.pausedLine(names: m.pausedNames)
        #expect(line.contains("AutomotiveAi and Optimus"))
        #expect(m.bellTexts.contains("Search is paused for 2 rooms"))
        #expect(m.checks.items.first { $0.id == "leakage" }.map(m.checks.state) == .fail)
    }

    @Test func offlineSkipsTheChecksThatNeedTheServer() async {
        var s = SampleBrainService.Scenario()
        s.offline = true
        let (m, _) = await make(s)
        await m.checks.load()
        let c = m.checks!
        #expect(c.items.first { $0.id == "sync" }.map(c.state) == .skipped)
        #expect(c.sentence(c.items.first { $0.id == "sync" }!) == BrainWords.checksSkipped)
        await c.run("sync")
        #expect(c.items.first { $0.id == "sync" }?.skippedOffline == true)
        await c.run("speed")
        #expect(c.items.first { $0.id == "speed" }?.skippedOffline == false)
    }

    @Test func neverRunReadsInPlainWords() {
        let c = CheckItem(
            id: "x", name: "X", about: "About.", last: "Never", outcome: .never, due: "now", value: "—", target: "Zero")
        #expect(CheckState.never.label == "Never run" && c.history.isEmpty)
        #expect(BrainWords.checksSummary(failed: 0, due: 0) == "Every check passed.")
        #expect(BrainWords.checksSummary(failed: 2, due: 1) == "2 checks failed.")
    }
}
