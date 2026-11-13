import BrainImport
import Foundation
import Testing

@testable import Admin
@testable import Brain
@testable import Shell

/// A Core that answers from a table keyed "METHOD path" (query ignored), and keeps what it was asked.
final class FakeBrainTransport: BrainTransport, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var log: [String] = []
    var routes: [String: @Sendable (Data?) throws -> Any] = [:]

    func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
        let key = "\(method) \(path.split(separator: "?")[0])"
        let handler = lock.withLock { () -> (@Sendable (Data?) throws -> Any)? in
            log.append(key)
            return routes[key]
        }
        guard let handler else { throw BrainHTTPError(status: 404, code: "not_found") }
        let out = try handler(body)
        return try JSONSerialization.data(withJSONObject: out)
    }
    func count(_ key: String) -> Int { lock.withLock { log.filter { $0 == key }.count } }
}

struct FakeSource: ImportSource {
    let id = "claude_code"
    let title = "Claude Code sessions"
    func scan() async -> CollectReport {
        var r = CollectReport()
        r.found = 3
        r.skipped = ["deprecated:GitScope": 1]
        return r
    }
    func stream(
        run: String, uploader: Uploader, uploaded: Uploader.Progress, resume: SourceResume,
        save: @Sendable (SourceResume) -> Void, onProgress: @Sendable (StreamProgress) async -> Void
    ) async throws -> CollectReport {
        let items = (0..<2).map { i -> ImportItem in
            let json: [String: Any] = [
                "item_id": ItemFormat.itemID(seed: "t\(i)"), "source_kind": "claude_code",
                "content_hash": ItemFormat.hash("synthetic \(i)"),
                "origin": ["device": "test", "path": "/x/\(i)"], "project_hint": "/work/alpha",
                "author": ["kind": "person", "name": "me"], "title": "Synthetic \(i)", "text": "synthetic \(i)",
                "links": [String](), "started_at": "2026-01-01T00:00:00Z",
            ]
            // swiftlint:disable:next force_try
            return try! JSONDecoder().decode(ImportItem.self, from: JSONSerialization.data(withJSONObject: json))
        }
        try await uploader.upload(items, run: run, progress: uploaded)
        var p = StreamProgress()
        p.filesDone = 2
        p.filesTotal = 2
        p.bytesDone = 20
        p.bytesTotal = 20
        await onProgress(p)
        var r = CollectReport()
        r.found = 2
        r.items = 2
        return r
    }
}

func card(_ id: String, kind: String = "product", state: String = "proposed", warnings: [String] = []) -> [String: Any]
{
    [
        "id": id, "name": id.capitalized, "kind": kind, "kind_guess": kind, "state": state, "signals": [],
        "warnings": warnings, "item_count": 2, "sample_titles": ["a"], "config": [:] as [String: Any],
    ]
}

func runView(_ state: String, stored: Int = 0) -> [String: Any] {
    [
        "run": "r1", "kind": "full", "state": state, "stage": state, "sources": ["claude_code"],
        "started_at": "2026-01-01T00:00:00Z",
        "counts": [
            "found": stored, "stored": stored, "duplicate": 0, "refused": 0, "rejected": 0, "cleaned": 0,
            "pointers": 0, "skipped": [String: Int](),
        ],
    ]
}

@MainActor
struct BrainImportFlowTests {
    func wizard(_ t: FakeBrainTransport, host: FakeHost = FakeHost()) -> (ImportModel, FakeHost) {
        t.routes["POST /modules/brain/v1/imports"] = { _ in ["run": "r1"] }
        t.routes["POST /modules/brain/v1/imports/r1/items"] = { _ in ["results": []] }
        t.routes["POST /modules/brain/v1/imports/r1/collected"] = { _ in runView("discovering", stored: 2) }
        t.routes["GET /modules/brain/v1/imports/r1"] = { _ in runView("review", stored: 2) }
        t.routes["GET /modules/brain/v1/imports/r1/proposals"] = { _ in
            [card("alpha"), card("acme", kind: "employer", warnings: ["mixed_employers"]), card("unsorted")]
        }
        let m = ImportModel(
            host: host, routes: BrainRoutes(transport: t), sources: [FakeSource()], poll: .milliseconds(1),
            pause: { _ in })
        return (m, host)
    }

    func untilStep(_ m: ImportModel, _ s: ImportModel.Step) async {
        for _ in 0..<500 where m.step != s { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func scanShowsCountsAndSkipsFromNamesAlone() async {
        let (m, _) = wizard(FakeBrainTransport())
        await m.scan()
        #expect(m.choices.first?.found == 3 && m.choices.first?.skipped == ["deprecated:GitScope": 1])
        #expect(ImportWords.skips(["deprecated:GitScope": 1]) == "1 a refused project")
        #expect(ImportWords.shortName("/-p1/" + String(repeating: "a", count: 60) + ".jsonl").count == 28)
        #expect(ImportWords.shortName("/-p1/s1.jsonl") == "s1.jsonl")
    }

    @Test func aToolWithUnreadableHistoryIsListedButCannotBeChosen() async {
        let t = FakeBrainTransport()
        _ = wizard(t)
        let nr = NotReadableSource(id: "antigravity", title: "Antigravity sessions", reason: "Binary records.")
        let model = ImportModel(
            host: FakeHost(), routes: BrainRoutes(transport: t), sources: [FakeSource(), nr], poll: .milliseconds(1),
            pause: { _ in })
        await model.scan()
        let c = model.choices.first { $0.id == "antigravity" }
        #expect(c?.notReadable == "Binary records." && c?.on == false && c?.found == 0)
        #expect(model.chosen.map(\.id) == ["claude_code"])
    }

    @Test func collectUploadsThenReportsDoneThenReachesReview() async {
        let t = FakeBrainTransport()
        let (m, _) = wizard(t)
        #expect(m.step == .sources && m.canStart)
        m.start()
        await untilStep(m, .review)
        #expect(m.step == .review && m.run == "r1")
        #expect(t.count("POST /modules/brain/v1/imports/r1/items") == 1)
        #expect(t.count("POST /modules/brain/v1/imports/r1/collected") == 1)
        #expect(m.counts.stored == 2 && m.itemsFound == 2 && m.fraction == 1)
        #expect(m.review.visible.map(\.id) == ["alpha", "acme", "unsorted"])
    }

    @Test func aDroppedCoreFailsInWordsAndRetryKeepsTheRun() async {
        let t = FakeBrainTransport()
        let (m, _) = wizard(t)
        t.routes["POST /modules/brain/v1/imports/r1/items"] = { _ in throw BrainHTTPError(status: 500, code: "x") }
        m.start()
        for _ in 0..<500 where m.failure == nil { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(m.failure != nil && m.step == .collecting)
        t.routes["POST /modules/brain/v1/imports/r1/items"] = { _ in ["results": []] }
        m.retry()
        await untilStep(m, .review)
        #expect(m.step == .review)
        #expect(t.count("POST /modules/brain/v1/imports") == 1, "one run, not two")
    }

    @Test func aMixedEmployerCardCannotBeAcceptedOrCommitted() async {
        let t = FakeBrainTransport()
        let (m, _) = wizard(t)
        m.start()
        await untilStep(m, .review)
        await m.review.accept("acme")
        #expect(m.review.accepted.isEmpty && m.review.notice == "Two employers are in this room. Split it first.")
        await m.review.accept("unsorted")
        #expect(m.review.accepted.isEmpty)
        #expect(m.review.canCommit == false)
        #expect(t.count("PATCH /modules/brain/v1/imports/r1/proposals/acme") == 0, "refused before the Core")
    }

    @Test func reviewActionsRoundTripThroughTheCore() async {
        let t = FakeBrainTransport()
        let (m, _) = wizard(t)
        let base = "/modules/brain/v1/imports/r1/proposals/alpha"
        let held = NSLock()
        nonisolated(unsafe) var current = card("alpha")
        t.routes["PATCH " + base] = { b in
            let o = (try? JSONSerialization.jsonObject(with: b ?? Data()) as? [String: Any]) ?? [:]
            return held.withLock {
                for k in ["name", "kind", "state"] { if let v = o[k] as? String { current[k] = v } }
                return current
            }
        }
        t.routes["POST " + base + "/refuse"] = { _ in card("alpha", state: "refused") }
        t.routes["PATCH /modules/brain/v1/imports/r1/items"] = { _ in ["changed": 1] }
        t.routes["GET " + base + "/items"] = { _ in
            [
                "items": [
                    [
                        "id": "i1", "cursor": 1, "title": "T", "started_at": "2026-01-01", "source_kind": "claude_code",
                        "warnings": [],
                    ]
                ]
            ]
        }
        m.start()
        await untilStep(m, .review)
        await m.review.accept("alpha")
        #expect(m.review.accepted.map(\.id) == ["alpha"] && m.review.canCommit)
        await m.review.rename("alpha", to: "Side project")
        await m.review.setKind("alpha", "personal")
        #expect(m.review.cards.first { $0.id == "alpha" }?.name == "Side project")
        #expect(m.review.cards.first { $0.id == "alpha" }?.kind == "personal")
        await m.review.openCard("alpha")
        #expect(m.review.items.map(\.id) == ["i1"])
        m.review.selected = ["i1"]
        await m.review.markSelected("needed")
        #expect(m.review.items.first?.mark == "needed" && m.review.selected.isEmpty)
        await m.review.refuse("alpha")
        #expect(m.review.cards.first { $0.id == "alpha" }?.state == "refused" && m.review.openID == nil)
    }

    @Test func acceptAgainUndoesItAndABlockedAcceptSaysWhy() async {
        let t = FakeBrainTransport()
        let (m, _) = wizard(t)
        let held = NSLock()
        nonisolated(unsafe) var state = "proposed"
        t.routes["PATCH /modules/brain/v1/imports/r1/proposals/alpha"] = { b in
            let o = (try? JSONSerialization.jsonObject(with: b ?? Data()) as? [String: Any]) ?? [:]
            return held.withLock {
                state = o["state"] as? String ?? state
                return card("alpha", state: state)
            }
        }
        m.start()
        await untilStep(m, .review)
        await m.review.choose("alpha", "accept")
        #expect(m.review.accepted.map(\.id) == ["alpha"])
        await m.review.choose("alpha", "accept")
        #expect(m.review.accepted.isEmpty, "Accept again takes it back out")
        #expect(m.review.cards.first { $0.id == "alpha" }?.state == "proposed")
        await m.review.choose("acme", "accept")
        #expect(m.review.notice == "Two employers are in this room. Split it first.")
    }

    @Test func commitAsksTouchIDAndHeldRoomsAreShownHeld() async {
        let t = FakeBrainTransport()
        let host = FakeHost()
        let (m, _) = wizard(t, host: host)
        t.routes["PATCH /modules/brain/v1/imports/r1/proposals/alpha"] = { _ in card("alpha", state: "accepted") }
        t.routes["POST /modules/brain/v1/imports/r1/commit"] = { _ in
            [
                "rooms": [
                    [
                        "proposal": "alpha", "room": "alpha", "name": "Alpha", "kind": "product", "sources": 2,
                        "created": true,
                    ]
                ],
                "held": ["acme"], "rules_enabled": 0, "state": "committed",
            ]
        }
        m.start()
        await untilStep(m, .review)
        await m.review.accept("alpha")
        host.declines = true
        await m.commit()
        #expect(m.step == .review && t.count("POST /modules/brain/v1/imports/r1/commit") == 0)
        host.declines = false
        t.routes["GET /modules/brain/v1/imports/r1/proposals"] = { _ in
            [card("alpha", state: "committed"), card("acme", kind: "employer", state: "held")]
        }
        await m.commit()
        #expect(m.step == .done && host.reasons.count == 2)
        #expect(m.result?.rooms.first?.sources == 2 && m.result?.held == ["acme"])
        #expect(m.heldCards().map(\.id) == ["acme"] && ReviewWords.held == "Held until the room backup exists.")
    }

    @Test func aSavedRunIsPickedUpAfterARestartInsteadOfStartingOver() async throws {
        let t = FakeBrainTransport()
        let store = ResumeStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("brain-state-\(UUID().uuidString).json"))
        var saved = ResumeState()
        saved.run = "r1"
        store.save(saved)
        t.routes["POST /modules/brain/v1/imports"] = { _ in throw BrainHTTPError(status: 500, code: "no new run") }
        t.routes["POST /modules/brain/v1/imports/r1/items"] = { _ in ["results": []] }
        t.routes["POST /modules/brain/v1/imports/r1/collected"] = { _ in runView("discovering", stored: 2) }
        t.routes["GET /modules/brain/v1/imports/r1"] = { _ in runView("review", stored: 2) }
        t.routes["GET /modules/brain/v1/imports/r1/proposals"] = { _ in [card("alpha")] }
        let m = ImportModel(
            host: FakeHost(), routes: BrainRoutes(transport: t), sources: [FakeSource()], poll: .milliseconds(1),
            resume: store, pause: { _ in })
        m.start()
        await untilStep(m, .review)
        #expect(m.step == .review && m.run == "r1" && t.count("POST /modules/brain/v1/imports") == 0)
        #expect(t.count("POST /modules/brain/v1/imports/r1/items") == 0, "a run in review is opened, not sent to again")
    }

    @Test func aSavedRunTheCoreClosedIsForgottenAndANewOneStarts() async throws {
        let t = FakeBrainTransport()
        let store = ResumeStore(
            url: FileManager.default.temporaryDirectory.appendingPathComponent("brain-state-\(UUID().uuidString).json"))
        var saved = ResumeState()
        saved.run = "old"
        store.save(saved)
        t.routes["GET /modules/brain/v1/imports/old"] = { _ in runView("committed", stored: 2) }
        t.routes["POST /modules/brain/v1/imports"] = { _ in ["run": "r1"] }
        t.routes["POST /modules/brain/v1/imports/r1/items"] = { _ in ["results": []] }
        t.routes["POST /modules/brain/v1/imports/r1/collected"] = { _ in runView("discovering", stored: 2) }
        t.routes["GET /modules/brain/v1/imports/r1"] = { _ in runView("review", stored: 2) }
        t.routes["GET /modules/brain/v1/imports/r1/proposals"] = { _ in [card("alpha")] }
        let m = ImportModel(
            host: FakeHost(), routes: BrainRoutes(transport: t), sources: [FakeSource()], poll: .milliseconds(1),
            resume: store, pause: { _ in })
        m.start()
        await untilStep(m, .review)
        #expect(m.run == "r1" && t.count("POST /modules/brain/v1/imports") == 1)
        #expect(t.count("POST /modules/brain/v1/imports/old/items") == 0, "nothing is sent to a closed run")
    }

    @Test func statusLineReadsTheCoresCounts() async {
        let t = FakeBrainTransport()
        let (m, _) = wizard(t)
        #expect(m.statusLine.hasPrefix("Reading"))
        #expect(ReviewWords.range("2026-03-04T10:00:00Z", "2026-03-04T11:00:00Z") == "2026-03-04")
    }
}

@MainActor
struct CoreBrainServiceTests {
    func service(_ t: FakeBrainTransport) -> CoreBrainService { CoreBrainService(transport: t) }

    @Test func setupMapsTheFourStates() async throws {
        let t = FakeBrainTransport()
        let s = service(t)
        #expect(try await s.setup() == .absent, "a Core without the module answers 404")
        t.routes["GET /modules/brain/v1/status"] = { _ in ["present": true, "key": "ok", "rooms": 0, "runs": 0] }
        #expect(try await s.setup() == .notSetUp)
        t.routes["GET /modules/brain/v1/status"] = { _ in ["present": true, "key": "ok", "rooms": 2, "runs": 1] }
        #expect(try await s.setup() == .ready)
        t.routes["GET /modules/brain/v1/status"] = { _ in
            ["present": true, "key": "locked_mode0", "rooms": 2, "runs": 1]
        }
        if case .locked = try await s.setup() {} else { Issue.record("expected locked") }
    }

    @Test func roomsMapAndOpenSetsALease() async throws {
        let t = FakeBrainTransport()
        let s = service(t)
        t.routes["GET /modules/brain/v1/rooms"] = { _ in
            [
                [
                    "id": "a", "name": "Alpha", "kind": "product", "state": "ready", "review_days": 180, "sources": 7,
                    "open": false,
                ],
                [
                    "id": "e", "name": "Acme", "kind": "employer", "state": "ready", "review_days": 90, "sources": 3,
                    "open": true,
                ],
            ]
        }
        let rooms = try await s.rooms()
        #expect(rooms[0].mounted == false && rooms[0].counts == nil && rooms[0].lock == .sealed)
        #expect(rooms[1].kind == .employer && rooms[1].counts?.records == 3 && rooms[1].mode == .synced)
        t.routes["POST /modules/brain/v1/rooms/a/open"] = { _ in
            ["room": "a", "open_until": ISO8601DateFormatter().string(from: Date().addingTimeInterval(7200))]
        }
        try await s.openRoom("a")
        #expect(s.lease(for: "a").left == "2 h")
    }

    @Test func aRealCoreServiceGivesTheRealPaneStates() async {
        let t = FakeBrainTransport()
        let host = FakeHost()
        let model = BrainModel(host: host)
        model.use(service(t))
        await model.reload()
        #expect(model.load == .unavailable && model.setup == .absent && model.tabsVisible == false)
        t.routes["GET /modules/brain/v1/status"] = { _ in ["present": true, "key": "ok", "rooms": 0, "runs": 0] }
        await model.reload()
        #expect(model.load == .ready && model.setup == .notSetUp && model.tabsVisible == false)
        #expect(model.isSample == false && model.canMakeRooms == false)
    }

    @Test func theHowPageCoversWhatTheSpecSays() {
        let titles = BrainHowItWorks.sections.map(\.title)
        #expect(titles.count == 6 && titles.contains("Touch ID on every room open"))
        #expect(BrainWords.unavailableTitle == "Brain is coming")
    }
}
