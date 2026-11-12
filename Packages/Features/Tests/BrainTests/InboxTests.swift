import Foundation
import Testing

@testable import Admin
@testable import Brain
@testable import Shell

@MainActor
struct InboxTests {
    func make(_ s: SampleBrainService.Scenario = .init(), room: String = "ainkrad") async -> (
        BrainModel, FakeHost, SampleBrainService
    ) {
        let host = FakeHost()
        let model = BrainModel(host: host)
        let svc = SampleBrainService(s)
        model.use(svc)
        await model.reload()
        model.view(room)
        await model.loadInbox()
        return (model, host, svc)
    }

    @Test func approveSettlesTheItemAndTheCounts() async {
        let (m, _, _) = await make()
        #expect(m.inboxState.count(.waiting) == 3)
        let before = m.tabCount(.inbox)
        #expect(await m.approve("c1") == .done)
        #expect(m.inboxState.count(.waiting) == 2)
        #expect(m.tabCount(.inbox) == before - 1)
        #expect(m.visibleNeeds.first { $0.kind == .waiting && $0.room == "ainkrad" }?.n == 2)
        #expect(m.inboxState.done.first?.kind == "Approved")
    }

    @Test func aNoteThatReadsLikeAnInstructionNeedsItsConfirm() async {
        let (m, _, _) = await make()
        #expect(await m.approve("c3") == .needsConfirm)
        #expect(m.inboxState.count(.waiting) == 3)
        #expect(await m.approve("c3", confirmed: true) == .done)
        #expect(m.inboxState.count(.waiting) == 2)
    }

    @Test func rejectRemovesAndRedactMovesTheCleanedNoteToWaiting() async {
        let (m, _, _) = await make()
        #expect(await m.reject("c2") == .done)
        #expect(m.inboxState.count(.waiting) == 2)
        m.view("globex")
        await m.loadInbox()
        #expect(m.inboxState.count(.blocked) == 1 && m.inboxState.count(.waiting) == 1)
        m.inboxState.list = .blocked
        #expect(await m.redact("b1") == .done)
        #expect(m.inboxState.count(.blocked) == 0 && m.inboxState.count(.waiting) == 2)
        #expect(m.inboxState.list == .waiting)
    }

    @Test func keepingALowerSourceOverAHigherOneAsksTouchID() async {
        let (m, host, _) = await make(room: "acme-shop")
        host.declines = true
        #expect(await m.keep("k1", .second) == .cancelled)  // team member over project owner
        #expect(m.inboxState.count(.conflicts) == 1 && host.reasons.count == 1)
        #expect(await m.keep("k1", .first) == .done)  // the higher one needs no Touch ID
        #expect(host.reasons.count == 1 && m.inboxState.count(.conflicts) == 0)
    }

    @Test func assigningIntoARoomCloudAgentsReachAsksAndCancelLeavesItUnchanged() async {
        let (m, host, _) = await make()
        #expect(m.inboxState.captures.count == 4)
        #expect(await m.assign(["u2"], to: "personal", mode: .move) == .done)  // this Mac only: no Touch ID
        #expect(host.reasons.isEmpty && m.inboxState.captures.count == 3)
        host.declines = true
        #expect(await m.assign(["u1"], to: "ainkrad", mode: .move) == .cancelled)  // synced, approved cloud
        #expect(m.inboxState.captures.count == 3 && host.reasons.count == 1)
        host.declines = false
        #expect(await m.assign(["u1"], to: "ainkrad", mode: .copy) == .done)
        #expect(m.inboxState.captures.count == 3)  // a copy leaves the original
        #expect(m.inboxState.count(.waiting) == 3)  // and a move would have added one
    }

    @Test func markPrivateExcludeAndDeleteAlwaysAskTouchID() async {
        let (m, host, _) = await make()
        host.declines = true
        #expect(await m.markPrivate(["u1"]) == .cancelled)
        #expect(await m.exclude(["u1"]) == .cancelled)
        #expect(await m.deleteCaptures(["u1", "u2"]) == .cancelled)
        #expect(host.reasons.count == 3 && m.inboxState.captures.count == 4)
        host.declines = false
        m.inboxState.selected = ["u3", "u4"]
        #expect(await m.deleteCaptures(["u3", "u4"]) == .done)
        #expect(m.inboxState.captures.map(\.id) == ["u1", "u2"] && m.inboxState.selected.isEmpty)
        #expect(await m.discardAsked("b1") == false)
    }

    @Test func switchingRoomsClearsTheInboxBeforeTheNewOneLoads() async {
        let (m, _, _) = await make()
        m.inboxState.selected = ["u1"]
        _ = await m.approve("c1")
        m.view("initech")
        let s = m.inboxState
        #expect(s.data == nil && s.captures.isEmpty && s.done.isEmpty && s.selected.isEmpty && s.phase == .idle)
        await m.loadInbox()
        #expect(s.data?.room == "initech" && s.count(.waiting) == 0)
    }

    @Test func aSealedRoomShowsNothingButTheNoRoomListStillWorks() async {
        let (m, _, _) = await make(room: "umbrella")
        #expect(m.inboxState.data == nil && m.inboxState.phase == .ready)
        #expect(m.inboxState.captures.count == 4)
        #expect(m.viewingLock == .sealed)
    }

    @Test func staleAndBellAges() async {
        let (m, _, _) = await make()
        let c = m.inboxState.captures
        #expect(c.map(\.stale) == [false, false, true, true] && c.map(\.inBell) == [false, false, false, true])
    }

    @Test func pausedHoldsMovesAndSaysSo() async {
        let (m, host, _) = await make(.init(paused: true))
        #expect(await m.assign(["u1"], to: "personal", mode: .move) == .failed)
        #expect(m.notice?.hasPrefix("Paused.") == true && m.inboxState.captures.count == 4 && host.reasons.isEmpty)
    }

    @Test func aFailedActionKeepsTheItemAndOffersTryAgain() async {
        let (m, _, svc) = await make()
        await svc.failNextAction()
        #expect(await m.approve("c1") == .failed)
        #expect(m.inboxState.errors["c1"] == "That did not save. The local Core did not answer, and nothing changed.")
        #expect(m.inboxState.count(.waiting) == 3)
        #expect(await m.approve("c1") == .done && m.inboxState.errors["c1"] == nil)
    }

    @Test func refusedAndErrorStatesAreWorded() async {
        let (r, _, _) = await make(.init(refused: true))
        if case .refused(let why) = r.inboxState.phase {
            #expect(why.contains("provider rule"))
        } else {
            Issue.record("not refused")
        }
        let (e, _, _) = await make(.init(inboxError: true))
        #expect(e.inboxState.phase == InboxState.Phase.failed("Core did not answer. Nothing was changed."))
    }

    @Test func offlineChangesAreCountedAsQueued() async {
        let (m, _, _) = await make(.init(offline: true))
        _ = await m.approve("c1")
        #expect(m.inboxState.queued == 1 && m.inboxState.done.first?.text.hasSuffix("queued to sync") == true)
    }

    @Test func theBellAndPushNeverCarryContent() async {
        let (m, _, _) = await make()
        let titles =
            ["c1", "c2", "c3", "c4"].compactMap { m.candidate($0)?.title } + ["Sample", "secret", "net payment"]
        let texts = m.bellTexts + NeedKind.allCases0.map { BrainWords.push(kind: $0, n: 2) }
        for t in texts { for bad in titles { #expect(!t.localizedCaseInsensitiveContains(bad), "\(t)") } }
        #expect(m.bellTexts.contains("3 memories wait in Ainkrad"))
        #expect(m.bellTexts.contains("1 note was blocked in Globex"))
        #expect(BrainWords.push(kind: .waiting, n: 3) == "3 memories wait in a room")
    }
}

extension NeedKind {
    static var allCases0: [NeedKind] { [.waiting, .conflict, .blocked, .check, .unclassified, .paused] }
}

extension BrainModel {
    /// A discard of a blocked note needs Touch ID; true when it ran without asking (it must not).
    func discardAsked(_ id: String) async -> Bool {
        let host = self.host as? FakeHost
        let before = host?.reasons.count ?? 0
        host?.declines = true
        view("globex")
        await loadInbox()
        _ = await discard(id)
        host?.declines = false
        return (host?.reasons.count ?? 0) == before
    }
}
