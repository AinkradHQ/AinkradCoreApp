import Foundation
import Testing

@testable import Brain

/// Review before filing (Ahmed, 2026-11-21): Sort lists what the Core prepared, every change is one route, and nothing is
/// filed before Approve.
@MainActor
struct SortReviewTests {
    let base = "/modules/brain/v1/imports/r1"

    func sized(_ id: String, _ n: Int, state: String = "proposed", warnings: [String] = []) -> [String: Any] {
        var c = card(id, state: state, warnings: warnings)
        c["item_count"] = n
        return c
    }

    /// A wizard at Sort on the calm flow, with bodies kept per route.
    func atSort(_ t: FakeBrainTransport, cards: [[String: Any]], host: FakeHost = FakeHost()) async -> ImportModel {
        let (m, _) = BrainImportFlowTests().wizard(t, host: host)
        nonisolated(unsafe) let list = cards
        t.routes["GET \(base)/proposals"] = { _ in list }
        m.autoSort = true
        m.start()
        for _ in 0..<500 where m.step != .review { try? await Task.sleep(for: .milliseconds(5)) }
        await m.beginSort()
        return m
    }

    @Test func approveFilesTheListedPlacesInOneCommitAndGoesToLearn() async throws {
        let t = FakeBrainTransport()
        let host = FakeHost()
        let sent = SentBody()
        t.routes["POST \(base)/commit"] = { b in
            sent.set(b)
            return [
                "rooms": [
                    [
                        "proposal": "alpha", "room": "alpha", "name": "Alpha", "kind": "product", "sources": 2,
                        "created": true,
                    ]
                ], "held": [], "rules_enabled": 0, "state": "committed",
            ]
        }
        t.routes["GET \(base)/learning"] = { _ in
            ["run": "r1", "places": [], "total_cost_usd_micros": 0, "unpriced": 0, "done": false]
        }
        let m = await atSort(t, cards: [sized("alpha", 2), sized("empty", 0), sized("unsorted", 5)], host: host)
        #expect(m.auto.sort == .review)
        #expect(m.review.places.map(\.id) == ["alpha"] && m.review.unsortedCard?.itemCount == 5)
        host.declines = true
        await m.approve()
        #expect(m.step == .review && t.count("POST \(base)/commit") == 0)
        host.declines = false
        await m.approve()
        let body = try #require(sent.json)
        #expect(body["keep"] as? [String] == ["alpha"] && body["keep_unsorted"] as? Bool == true)
        #expect(m.step == .importing && host.reasons.count == 2)
    }

    @Test func aPlaceWithTwoEmployersBlocksApprove() async {
        let t = FakeBrainTransport()
        let m = await atSort(t, cards: [sized("alpha", 2), sized("acme", 3, warnings: ["mixed_employers"])])
        #expect(m.review.approveBlock == "Two employers are in Acme. Open it and split it first.")
        await m.approve()
        #expect(t.count("POST \(base)/commit") == 0 && m.step == .review)
    }

    @Test func renameMergeAndMoveToUnsortedAreOneRouteEach() async throws {
        let t = FakeBrainTransport()
        let patched = SentBody()
        let moved = SentBody()
        t.routes["PATCH \(base)/proposals/alpha"] = { b in
            patched.set(b)
            var c = card("alpha")
            c["name"] = "Northwind"
            return c
        }
        t.routes["POST \(base)/proposals/beta/merge"] = { _ in card("alpha") }
        t.routes["GET \(base)/proposals/gamma/items"] = { _ in
            [
                "items": [
                    [
                        "id": "i1", "cursor": 1, "title": "T", "started_at": "2026-01-01", "source_kind": "claude_code",
                        "warnings": [],
                    ]
                ]
            ]
        }
        t.routes["PATCH \(base)/items"] = { b in
            moved.set(b)
            return ["changed": 1]
        }
        let m = await atSort(t, cards: [sized("alpha", 2), sized("beta", 2), sized("gamma", 1)])
        m.review.renaming = "alpha"
        await m.review.saveRename("alpha", "  Northwind ")
        #expect(patched.json?["name"] as? String == "Northwind" && m.review.renaming == nil)
        #expect(m.review.cards.first { $0.id == "alpha" }?.name == "Northwind")
        await m.review.saveRename("alpha", "Northwind")
        #expect(t.count("PATCH \(base)/proposals/alpha") == 1, "an unchanged name sends nothing")
        m.review.mergingFor = "beta"
        await m.review.mergePlace("beta", into: "alpha")
        #expect(t.count("POST \(base)/proposals/beta/merge") == 1 && m.review.mergingFor == nil)
        await m.review.moveToUnsorted("gamma")
        #expect(moved.json?["ids"] as? [String] == ["i1"] && moved.json?["proposal"] as? String == "unsorted")
        #expect(m.review.mergeTargets(for: "alpha").map(\.id) == ["beta", "gamma"])
    }

    @Test func nothingToReviewCommitsAndGoesToDone() async {
        let t = FakeBrainTransport()
        t.routes["POST \(base)/commit"] = { _ in ["rooms": [], "held": [], "rules_enabled": 0, "state": "committed"] }
        let m = await atSort(t, cards: [sized("unsorted", 0)])
        #expect(m.review.nothingToReview)
        await m.approve()
        #expect(m.step == .done)
    }

    @Test func anOldRunTheCoreFiledByItselfShowsSortedWithUndo() async {
        let t = FakeBrainTransport()
        t.routes["GET /modules/brain/v1/auto-imports"] = { _ in
            [["run": "r1", "at": "2026-11-21T10:00:00Z", "rooms": 4]]
        }
        t.routes["POST /modules/brain/v1/auto-imports/r1/undo"] = { _ in ["rooms": 4, "items": 120] }
        let m = await atSort(t, cards: [sized("alpha", 2)])
        #expect(m.auto.sort == .sorted(rooms: 4) && m.auto.canUndo)
        await m.undoSort()
        #expect(m.auto.sort == .review && m.auto.undoneItems == 120)
    }

    @Test func learnStatesInWords() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(SyncWords.date("2026-11-21T12:00:00Z"))
        func place(_ state: String, retry: String? = nil) -> LearningWire.Place {
            var p = LearningWire.Place(
                room: "r", name: "R", sources: 10, read: 4, learned: 0, state: state, provider: nil, costUsdMicros: 0)
            p.retryAt = retry
            return p
        }
        #expect(
            LearnWords.shown(
                place("failed", retry: "2026-11-21T12:10:00Z"), now: now, zone: utc, locale: Locale(identifier: "en_GB")
            )
                == .failed(
                    "Couldn't reach the AI · retrying at 12:10"))
        #expect(
            LearnWords.shown(place("failed"), now: now, zone: utc)
                == .failed(
                    "Couldn't reach the AI · it tries again by itself"))
        #expect(
            LearnWords.shown(place("failed", retry: "2026-11-21T11:00:00Z"), now: now, zone: utc)
                == .failed(
                    "Couldn't reach the AI · retrying now"))
        #expect(LearnWords.shown(place("learning"), now: now) == .reading(0.4))
        #expect(LearnWords.shown(place("waiting"), now: now) == .waiting)
        #expect(LearnWords.shown(place("pending"), now: now) == .soon)
        #expect(LearnWords.shown(place("done"), now: now) == .done)
        let wire =
            #"{"room":"r","name":"R","sources":1,"read":0,"learned":0,"state":"failed","cost_usd_micros":0,"retry_at":"x"}"#
        #expect(try JSONDecoder().decode(LearningWire.Place.self, from: Data(wire.utf8)).retryAt == "x")
    }

    @Test func theBrainDropdownSaysTheReviewWaits() async {
        let t = FakeBrainTransport()
        let m = await atSort(t, cards: [sized("alpha", 2), sized("beta", 1)])
        #expect(m.glance?.line == "Waiting for you to review 2 places")
        #expect(ImportModel.waiting(places: 1) == "Waiting for you to review 1 place")
    }
}

/// A body a fake route was sent, as JSON.
final class SentBody: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    func set(_ d: Data?) { lock.withLock { data = d } }
    var json: [String: Any]? {
        lock.withLock { data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    }
}

/// After a restart (Ahmed, 2026-11-21): the import the Core is still learning from is shown again, from `GET /imports`.
@MainActor
struct RestoreImportTests {
    let base = "/modules/brain/v1/imports"

    func model(_ t: FakeBrainTransport) -> ImportModel {
        let (m, _) = BrainImportFlowTests().wizard(t)
        m.autoSort = true
        return m
    }

    func learning(done: Bool, states: [String]) -> [String: Any] {
        let places: [[String: Any]] = states.enumerated().map { i, s in
            [
                "room": "p\(i)", "name": "P\(i)", "sources": 10, "read": s == "done" ? 10 : 4, "learned": 2, "state": s,
                "cost_usd_micros": 0,
            ]
        }
        return ["run": "r1", "places": places, "total_cost_usd_micros": 0, "unpriced": 0, "done": done]
    }

    @Test func aCommittedRunStillLearningOpensAtLearnWithItsProgress() async {
        let t = FakeBrainTransport()
        t.routes["GET \(base)"] = { _ in
            [
                ["run": "r2", "kind": "full", "state": "abandoned", "started_at": "x"],
                ["run": "r1", "state": "committed"],
            ]
        }
        nonisolated(unsafe) let l = learning(done: false, states: ["learning", "done"])
        t.routes["GET \(base)/r1/learning"] = { _ in l }
        let m = model(t)
        #expect(await m.restoreUnderWay())
        #expect(m.run == "r1" && m.step == .importing && m.isActive)
        #expect(await until { m.auto.learning != nil })
        #expect(m.glance?.line == "Learning from your work" && m.glance?.detail == "14 of 20")
        m.auto.stop()
    }

    @Test func aRunThatLearnedEverythingShowsNothing() async {
        let t = FakeBrainTransport()
        t.routes["GET \(base)"] = { _ in [["run": "r1", "state": "committed"]] }
        nonisolated(unsafe) let l = learning(done: true, states: ["done", "done"])
        t.routes["GET \(base)/r1/learning"] = { _ in l }
        let m = model(t)
        #expect(await m.restoreUnderWay() == false)
        #expect(m.run == nil && m.step == .sources && m.glance == nil)
    }

    @Test func aRunInReviewOpensAtSort() async {
        let t = FakeBrainTransport()
        t.routes["GET \(base)"] = { _ in [["run": "r1", "state": "review"], ["run": "r0", "state": "committed"]] }
        let m = model(t)
        #expect(await m.restoreUnderWay())
        #expect(m.run == "r1" && m.step == .review && m.auto.sort == .review)
        #expect(t.count("GET \(base)/r0/learning") == 0)
    }

    @Test func anOlderCoreWithoutTheListChangesNothing() async {
        let t = FakeBrainTransport()  // GET /imports answers 404, as before API minor 96
        let m = model(t)
        #expect(await m.restoreUnderWay() == false)
        #expect(m.run == nil && m.step == .sources && !m.isActive)
    }
}
