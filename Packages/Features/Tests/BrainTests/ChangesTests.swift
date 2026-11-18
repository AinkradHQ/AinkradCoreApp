import Foundation
import Testing

@testable import Admin
@testable import Brain
@testable import Shell

/// Memory change sets (B10-01): the wire shapes of `change_routes.rs`, and the Activity memory view on the sample.
@MainActor
struct ChangesTests {
    private func real(_ t: FakeBrainTransport) -> CoreBrainService { CoreBrainService(transport: t) }

    @Test func theListReadsTheCoresSummaryLines() async throws {
        let t = FakeBrainTransport()
        t.routes["GET /modules/brain/v1/rooms/r1/changes"] = { _ in
            [
                ["id": "c2", "kind": "distil", "summary": "Saved 5 · reinforced 3", "counts": ["saved": 5],
                 "at": "2026-11-18T09:00:00Z", "undone_at": NSNull(), "rows": 8],
                ["id": "c1", "kind": "purge", "summary": "Removed 12 for good", "counts": [String: Int](),
                 "at": "2026-11-17T03:17:00Z", "undone_at": "2026-11-17T04:00:00Z", "rows": 0],
            ]
        }
        let page = try await real(t).changes(room: "r1", after: nil)
        #expect(page.changes.map(\.line) == ["Saved 5 · reinforced 3", "Removed 12 for good"])
        #expect(page.changes[0].canUndo && page.changes[0].rows == 8)
        // A purge keeps no rows: no Undo, no See changes.
        #expect(!page.changes[1].canUndo && !page.changes[1].kind.hasRows)
        #expect(!page.hasMore)
    }

    @Test func rowsKeepBeforeAfterAndCitedSources() async throws {
        let t = FakeBrainTransport()
        t.routes["GET /modules/brain/v1/rooms/r1/changes/c2"] = { _ in
            [
                "change": ["id": "c2", "kind": "ai", "summary": "Saved 1", "counts": [String: Int](), "at": "2026-11-18T09:00:00Z",
                           "undone_at": NSNull(), "rows": 2],
                "rows": [
                    ["seq": 1, "record": "rec-1", "before": NSNull(),
                     "after": ["type": "fact", "body": "A made-up fact.", "tags": "[\"x\",\"y\"]", "_sources": ["s1", "s2"]]],
                    ["seq": 2, "record": "rec-2", "before": ["type": "task", "body": "Old.", "tags": [String]()],
                     "after": NSNull()],
                ],
                "more": true,
            ]
        }
        let page = try await real(t).changeRows(room: "r1", change: "c2", after: nil)
        #expect(page.more && page.rows.map(\.verb) == ["Added", "Removed"])
        #expect(page.rows[0].after == MemoryImage(type: "fact", text: "A made-up fact.", tags: ["x", "y"], sources: ["s1", "s2"]))
        #expect(page.rows[1].before?.text == "Old." && page.rows[1].after == nil)
    }

    @Test func undoReportsWhatWasKept() async throws {
        let t = FakeBrainTransport()
        t.routes["POST /modules/brain/v1/rooms/r1/changes/c2/undo"] = { _ in
            ["change": "c2", "restored": ["a", "b"], "skipped": ["c"], "already_undone": false]
        }
        let u = try await real(t).undoChange(room: "r1", change: "c2")
        #expect(u == ChangeUndo(restored: ["a", "b"], skipped: ["c"]))
        #expect(ChangesModel.sentence(u) == "Put back 2 memories. 1 changed since and was kept.")
        #expect(ChangesModel.sentence(ChangeUndo(restored: [], skipped: [], alreadyUndone: true)).contains("already undone"))
    }

    @Test func aPurgeUndoIsRefusedInWords() {
        let f = CoreBrainService.failure(BrainHTTPError(status: 409, code: "not_undoable"))
        #expect(f.sentence == "A purge removed these for good. It cannot be undone.")
    }

    // MARK: the memory view

    private func model(_ s: SampleBrainService.Scenario = .init()) async -> (BrainModel, FakeHost) {
        let host = FakeHost()
        let m = BrainModel(host: host)
        m.use(SampleBrainService(s, pace: .zero))
        await m.reload()
        m.activity.view = .memory
        m.changes.enter()
        await m.changes.load()
        return (m, host)
    }

    @Test func theViewListsSetsAndUndoRoundTrips() async {
        let (m, host) = await model()
        let c: ChangesModel = m.changes
        #expect(c.phase == .ready && c.changes.count == 4)
        c.toggle("chg-3")
        #expect(await until { c.details["chg-3"]?.loading == false })
        #expect(c.details["chg-3"]?.rows.count == 3)
        c.undo("chg-3")
        #expect(await until { c.results["chg-3"] != nil })
        // The record changed since stays; the rest is back; the line now says Undone.
        #expect(c.results["chg-3"]?.skipped == ["rec-b3"] && c.results["chg-3"]?.restored.count == 2)
        #expect(c.changes.first { $0.id == "chg-3" }?.undone == true)
        #expect(host.shell.toast?.message.contains("kept") == true)
        // A second Undo changes nothing.
        c.undo("chg-3")
        #expect(await until { c.results["chg-3"]?.alreadyUndone == true })
    }

    @Test func emptyAndFailingStatesShow() async {
        var quiet = SampleBrainService.Scenario()
        quiet.noActivity = true
        let (empty, _) = await model(quiet)
        #expect(empty.changes.phase == .ready && empty.changes.changes.isEmpty)
        var s = SampleBrainService.Scenario()
        s.activityError = true
        let (bad, _) = await model(s)
        if case .failed = bad.changes.phase {} else { Issue.record("expected a failed phase") }
    }
}
