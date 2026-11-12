import BrainImport
import Foundation
import Testing

@testable import Admin
@testable import Brain
@testable import Shell

/// The words and states the Rooms, Sources and Import screens show (the 2026-11-12 mockups).
@MainActor
struct BrainScreensTests {
    private let base = "/modules/brain/v1"

    func sync(_ t: FakeBrainTransport, result: @escaping @Sendable () -> [String: Any]) -> SyncModel {
        t.routes["GET \(base)/sources"] = { _ in [Any]() }
        t.routes["GET \(base)/rules"] = { _ in [Any]() }
        t.routes["GET \(base)/sync"] = { _ in
            [
                "every_secs": 1800, "sources": [["id": "core_transcript", "kind": "core_transcript", "enabled": true]],
                "review": ["run-1", "run-2"],
            ]
        }
        t.routes["POST \(base)/sync"] = { _ in result() }
        return SyncModel(
            host: FakeHost(), service: CoreBrainService(transport: t), sources: { [] }, poll: .milliseconds(1),
            pause: { _ in })
    }

    @Test func bannerSaysWhatWaitsThenWhatASyncFound() async {
        let t = FakeBrainTransport()
        let m = sync(
            t,
            result: {
                [
                    "found": 14, "stored": 12, "duplicate": 2,
                    "routed": [["room": "a", "sources": 5], ["room": "b", "sources": 4]],
                    "unsorted": 3, "new_rooms": 0,
                ]
            })
        await m.reload()
        #expect(m.banner == .waiting(2))
        #expect(SyncWords.banner(.waiting(2)).title == "2 imports waiting for review")
        #expect(SyncWords.banner(.nothingNew(sources: 1, nextMinutes: 1)).text.hasSuffix("Next sync in 1 minute."))
        await m.syncNow()
        #expect(m.banner == .synced(new: 12, went: 9, rooms: 2, review: 3))
        #expect(SyncWords.banner(m.banner) == ("12 new items", "9 went to 2 rooms, 3 need review."))
        m.dismissOutcome()
        #expect(m.banner == .waiting(2))
    }

    @Test func nothingNewSaysWhenTheNextSyncIs() async {
        let t = FakeBrainTransport()
        let m = sync(t) { ["found": 0, "stored": 0, "idle": "nothing_new"] }
        await m.syncNow()
        #expect(m.banner == .nothingNew(sources: 1, nextMinutes: 30))
        #expect(SyncWords.banner(m.banner).text == "All 1 source checked just now. Next sync in 30 minutes.")
    }

    @Test func agoReadsLikeAPerson() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(SyncWords.ago(now.addingTimeInterval(-20), now: now) == "Just now")
        #expect(SyncWords.ago(now.addingTimeInterval(-240), now: now) == "4 min ago")
        #expect(SyncWords.ago(now.addingTimeInterval(-7200), now: now) == "2 hours ago")
        #expect(SyncWords.ago(now.addingTimeInterval(-100_000), now: now) == "Yesterday")
        #expect(SyncWords.date("2026-11-12T14:02:00Z") != nil)
        #expect(SyncWords.date("2026-11-12T14:02:00.123Z") != nil)
    }

    @Test func sourcesGroupAndDropTheSessionsWord() {
        let all = ImportSources.standard()
        #expect(SyncWords.title("claude_code", all) == "Claude Code")
        #expect(SyncWords.title("vault", all) == "Notes vault (Ainkrad)")
        #expect(SyncWords.title("core_transcript", all) == "AI sessions on this Core")
        #expect(SyncWords.group("agents_md") == "Notes and docs" && SyncWords.group("codex") == "AI sessions")
        #expect(SourcesTab.unreadableNote(["Antigravity", "Kimi"]).hasPrefix("Antigravity and Kimi keep their"))
    }

    @Test func kimiIsAbsentWhileAntigravityIsUnreadable() {
        let t = FakeBrainTransport()
        let m = ImportModel(host: FakeHost(), routes: BrainRoutes(transport: t), sources: ImportSources.standard())
        #expect(m.choices.first { $0.id == "kimi" }?.absent == true)
        #expect(m.choices.first { $0.id == "antigravity" }?.absent == false)
        #expect(m.choices.first { $0.id == "chat" }?.title == "Chat exports")
    }

    @Test func collectRowsGoFromWaitingToDone() async {
        let t = FakeBrainTransport()
        t.routes["POST \(base)/imports"] = { _ in ["run": "r1"] }
        t.routes["POST \(base)/imports/r1/items"] = { _ in ["results": []] }
        t.routes["POST \(base)/imports/r1/collected"] = { _ in runView("discovering", stored: 2) }
        t.routes["GET \(base)/imports/r1"] = { _ in runView("review", stored: 2) }
        t.routes["GET \(base)/imports/r1/proposals"] = { _ in [card("alpha")] }
        let m = ImportModel(
            host: FakeHost(), routes: BrainRoutes(transport: t), sources: [FakeSource()], poll: .milliseconds(1),
            pause: { _ in })
        await m.scan()
        #expect(m.sourceRows.map(\.state) == [.waiting] && m.sourceRows.first?.total == 3)
        m.start()
        for _ in 0..<500 where m.step != .review { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(m.sourceRows.map(\.state) == [.done] && m.sourceRows.first?.fraction == 1)
    }

    @Test func aReadingRowCountsItemsNotFiles() {
        var c = ImportModel.Choice(id: "chat", title: "Chat exports")
        c.found = 300
        var p = StreamProgress()
        p.filesDone = 1
        p.filesTotal = 3
        let r = ImportModel.row(c, done: false, reading: p)
        #expect(r.state == .reading && r.done == 100 && r.total == 300, "a third of the files is a third of the items")
        p.filesDone = 3
        #expect(ImportModel.row(c, done: false, reading: p).fraction == 1, "no stall short of the end")
        #expect(ImportModel.row(c, done: true, reading: nil).done == 300)
        #expect(ImportModel.row(c, done: false, reading: nil).state == .waiting)
    }

    @Test func reviewWordsCountOnlyWhatIsThere() {
        func pc(_ id: String, _ state: String = "proposed") -> ProposalCard {
            ProposalCard(id: id, name: id, state: state)
        }
        let cards = [pc("a", "accepted"), pc("b", "accepted"), pc("c", "refused"), pc("d", "held"), pc("unsorted")]
        #expect(ReviewWords.tally(cards) == "2 accepted · 1 refused · 1 held")
        #expect(ReviewWords.importTitle(3) == "Import 3 rooms" && ReviewWords.importTitle(1) == "Import 1 room")
        #expect(ReviewWords.line(ProposalCard(id: "unsorted", name: "Unsorted")).hasPrefix("No room yet"))
    }

    @Test func aRealCoreShowsInboxRoomsAndSources() {
        let m = BrainModel(host: FakeHost())
        m.use(CoreBrainService(transport: FakeBrainTransport()))
        #expect(m.visibleTabs == [.inbox, .rooms, .sources] && m.currentTab == .inbox)
        m.tab = .sources
        #expect(m.currentTab == .sources)
    }
}
