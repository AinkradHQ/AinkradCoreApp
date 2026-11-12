import BrainImport
import Foundation
import Testing

@testable import Admin
@testable import Brain
@testable import Shell

/// A Mac source with one new file; records what it was asked.
struct NewFileSource: ImportSource {
    let id = "claude_code"
    let title = "Claude Code sessions"
    let count: Int
    func scan() async -> CollectReport { CollectReport() }
    func stream(
        run: String, uploader: Uploader, uploaded: Uploader.Progress, resume: SourceResume,
        save: @Sendable (SourceResume) -> Void, onProgress: @Sendable (StreamProgress) async -> Void
    ) async throws -> CollectReport { CollectReport() }
    var incremental: Bool { true }
    func newCount(since: Date?) async -> Int { count }
    func streamNew(since: Date?, run: String, uploader: Uploader, uploaded: Uploader.Progress) async throws
        -> CollectReport
    { CollectReport() }
}

private let base = "/modules/brain/v1"
private func sourceRow(cursor: [String: Any] = ["mtime": 100]) -> [String: Any] {
    [
        "id": "mac_claude_code", "device": "Mac", "kind": "claude_code", "enabled": true, "roots": [String](),
        "cursor": cursor, "last_run": NSNull(),
    ]
}

@MainActor
struct SyncTests {
    func model(_ t: FakeBrainTransport, sources: [any ImportSource] = [NewFileSource(count: 1)]) -> SyncModel {
        SyncModel(
            host: FakeHost(), service: CoreBrainService(transport: t), sources: { sources }, poll: .milliseconds(1),
            now: { Date(timeIntervalSince1970: 500) }, pause: { _ in })
    }

    func core(_ t: FakeBrainTransport, runState: @escaping @Sendable () -> String) {
        t.routes["GET \(base)/sources"] = { _ in [sourceRow()] }
        t.routes["POST \(base)/imports"] = { _ in ["run": "r9"] }
        t.routes["POST \(base)/imports/r9/collected"] = { _ in runView("discovering") }
        t.routes["GET \(base)/imports/r9"] = { _ in runView(runState()) }
        t.routes["POST \(base)/sync"] = { _ in
            [
                "found": 0, "stored": 0, "duplicate": 0, "refused": 0, "rejected": 0,
                "routed": [Any](), "unsorted": 0, "new_rooms": 0, "notice": false, "idle": "nothing_new",
            ]
        }
        t.routes["GET \(base)/sync"] = { _ in ["every_secs": 3600, "sources": [Any](), "review": ["run-1"]] }
        t.routes["GET \(base)/rules"] = { _ in [Any]() }
    }

    @Test func syncResultMapsToWordsAndRooms() throws {
        let json = """
            {"run":"run-1","state":"committed","found":5,"stored":3,"duplicate":2,"refused":0,"rejected":1,
             "routed":[{"room":"r-opt","sources":2}],"unsorted":1,"new_rooms":2,"notice":true}
            """
        let r = try JSONDecoder().decode(SyncResultWire.self, from: Data(json.utf8))
        #expect(r.newRooms == 2 && r.routed.first?.sources == 2 && r.notice)
        let s = r.summary { $0 == "r-opt" ? "Optimus" : nil }
        #expect(s.contains("5 items found, 3 kept, 2 already known, 1 skipped"))
        #expect(s.contains("Added to Optimus") && s.contains("1 unsorted, 2 new rooms"))
        var idle = SyncResultWire()
        idle.idle = "nothing_new"
        #expect(idle.summary() == "Nothing new.")
    }

    @Test func snippetMarksBecomeMatchedRuns() {
        let p = SearchHit.pieces(of: "ship «the plan» now «and")
        #expect(
            p == [
                SnippetPiece(text: "ship ", match: false), SnippetPiece(text: "the plan", match: true),
                SnippetPiece(text: " now ", match: false), SnippetPiece(text: "and", match: true),
            ])
        #expect(SearchHit.pieces(of: "plain") == [SnippetPiece(text: "plain", match: false)])
    }

    @Test func searchAsksTheRoomRouteAndClosedRoomSpeaks() async {
        let t = FakeBrainTransport()
        t.routes["GET \(base)/rooms/r1/search"] = { _ in
            ["hits": [["item_id": "i", "source_kind": "doc", "title": "T", "snippet": "a «b»", "started_at": "x"]]]
        }
        let m = model(t)
        let hits = await m.search(room: "r1", query: " b ")
        #expect(hits.map(\.itemID) == ["i"])
        t.routes["GET \(base)/rooms/r1/search"] = { _ in throw BrainHTTPError(status: 409, code: "room_closed") }
        #expect(await m.search(room: "r1", query: "b").isEmpty)
        #expect(m.notice == "Open this room first, then search it.")
        #expect(await m.search(room: "r1", query: "  ").isEmpty)
    }

    @Test func sourceToggleSendsTheSwitchAndKeepsTheCursor() async throws {
        let t = FakeBrainTransport()
        core(t) { "committed" }
        nonisolated(unsafe) var sent: [String: Any] = [:]
        t.routes["PUT \(base)/sources/mac_claude_code"] = { b in
            sent = (try? JSONSerialization.jsonObject(with: b ?? Data()) as? [String: Any]) ?? [:]
            var row = sourceRow()
            row["enabled"] = false
            return row
        }
        let m = model(t)
        await m.reload()
        let row = try #require(m.sources.first)
        await m.toggle(row, on: false)
        #expect(sent["enabled"] as? Bool == false && sent["cursor"] == nil && sent["kind"] as? String == "claude_code")
        #expect(m.sources.first?.enabled == false)
        #expect(m.review == ["run-1"])
    }

    @Test func cursorMovesOnlyAfterTheCoreHasTheRun() async {
        let t = FakeBrainTransport()
        core(t) { "committed" }
        nonisolated(unsafe) var cursors: [Any] = []
        t.routes["PUT \(base)/sources/mac_claude_code"] = { b in
            cursors.append((try? JSONSerialization.jsonObject(with: b ?? Data()) as? [String: Any])?["cursor"] as Any)
            return sourceRow()
        }
        let m = model(t)
        await m.syncNow()
        #expect(t.count("POST \(base)/imports") == 1 && cursors.count == 1)
        #expect((cursors.first as? [String: Any])?["mtime"] as? Double == 500)
        #expect(m.outcome?.idle == "nothing_new")
    }

    @Test func aRunTheCoreDoesNotConfirmLeavesTheCursorAlone() async {
        let t = FakeBrainTransport()
        core(t) { "abandoned" }
        t.routes["PUT \(base)/sources/mac_claude_code"] = { _ in sourceRow() }
        let m = model(t)
        await m.syncNow()
        #expect(t.count("PUT \(base)/sources/mac_claude_code") == 0)
        #expect(m.notice != nil && m.outcome == nil)
        // A failed upload does not move it either.
        let t2 = FakeBrainTransport()
        core(t2) { "committed" }
        t2.routes["POST \(base)/imports/r9/collected"] = { _ in throw BrainHTTPError(status: 500, code: "x") }
        t2.routes["PUT \(base)/sources/mac_claude_code"] = { _ in sourceRow() }
        await model(t2).syncNow()
        #expect(t2.count("PUT \(base)/sources/mac_claude_code") == 0)
    }

    @Test func nothingNewStartsNoRunAndAnUnregisteredSourceIsNotRead() async {
        let t = FakeBrainTransport()
        core(t) { "committed" }
        await model(t, sources: [NewFileSource(count: 0)]).syncNow()
        #expect(t.count("POST \(base)/imports") == 0 && t.count("POST \(base)/sync") == 1)
        t.routes["GET \(base)/sources"] = { _ in [Any]() }
        await model(t).syncNow()
        #expect(t.count("POST \(base)/imports") == 0)
    }

    @Test func aFirstImportRegistersItsSourcesFromTheStartTime() async {
        let t = FakeBrainTransport()
        t.routes["GET \(base)/sources"] = { _ in [Any]() }
        nonisolated(unsafe) var puts = 0
        t.routes["PUT \(base)/sources/mac_claude_code"] = { b in
            puts += 1
            #expect(
                ((try? JSONSerialization.jsonObject(with: b ?? Data()) as? [String: Any])?["cursor"] as? [String: Any])?[
                    "mtime"] as? Double == 42)
            return sourceRow()
        }
        await SyncModel.register(
            ["claude_code", "doc"], from: [NewFileSource(count: 0)], since: Date(timeIntervalSince1970: 42),
            service: CoreBrainService(transport: t))
        #expect(puts == 1)
    }

    @Test func theInboxEventRaisesOneNoticeAndRefreshesReview() async {
        let t = FakeBrainTransport()
        core(t) { "committed" }
        let host = FakeHost()
        let b = BrainModel(host: host)
        b.use(CoreBrainService(transport: t))
        b.inboxNotice(unsorted: 2, newRooms: 1)
        #expect(host.shell.toast?.message.contains("2 unsorted") == true)
        for _ in 0..<200 where b.sync?.review.isEmpty != false { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(b.sync?.review == ["run-1"])
    }
}
