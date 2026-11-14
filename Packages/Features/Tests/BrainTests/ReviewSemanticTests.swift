import Foundation
import Testing

@testable import Admin
@testable import Brain

final class Seen: @unchecked Sendable { nonisolated(unsafe) var body: [String: Any]? }

@MainActor
struct ReviewSemanticTests {
    static let base = "/modules/brain/v1/imports/r1"

    nonisolated static let applied = SemanticView(
        state: "ready", aiTidy: AiTidy(summary: SampleImportTransport.sampleTidy))

    func make(_ state: String, hints: SemanticView = Self.applied) -> (
        ReviewModel, FakeBrainTransport
    ) {
        let t = FakeBrainTransport()
        nonisolated(unsafe) let cards: [[String: Any]] = ["acme-shop", "pricing-experiment", "unsorted"].map {
            [
                "id": $0, "name": $0, "kind": "product", "kind_guess": "product", "state": "proposed",
                "signals": [String](),
                "warnings": [String](), "item_count": 3, "sample_titles": [String](), "config": [String: Any](),
                "semantic": state,
            ]
        }
        t.routes["GET \(Self.base)/proposals"] = { _ in cards }
        t.routes["GET \(Self.base)/semantic"] = { _ in
            var v = hints
            v.state = state
            return try JSONSerialization.jsonObject(with: JSONEncoder().encode(v))
        }
        let r = ReviewModel(host: FakeHost(), routes: BrainRoutes(transport: t))
        r.pollEvery = .milliseconds(5)
        return (r, t)
    }

    func settle(_ r: ReviewModel) async { await r.watching?.value }

    @Test func aPendingStepIsPolledUntilReadyAndTheListLoadsFirst() async throws {
        let (r, t) = make("pending")
        try await r.load(run: "r1")
        #expect(r.cards.count == 3 && r.semanticState == "pending")
        try await Task.sleep(for: .milliseconds(40))
        #expect(t.count("GET \(Self.base)/semantic") >= 2)
        // The Core now says ready: the next poll shows the hints and stops.
        t.routes["GET \(Self.base)/semantic"] = { _ in
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.applied))
        }
        await settle(r)
        #expect(r.semanticState == "ready" && r.tidy?.roomsAfter == 4)
        let n = t.count("GET \(Self.base)/semantic")
        try await Task.sleep(for: .milliseconds(30))
        #expect(t.count("GET \(Self.base)/semantic") == n)
    }

    @Test func offOrNoModelShowsNothingAndAsksNothing() async throws {
        let (r, t) = make("off")
        try await r.load(run: "r1")
        #expect(r.semanticState == nil && r.tidy == nil && t.count("GET \(Self.base)/semantic") == 0)
        let t2 = FakeBrainTransport()  // an older Core: cards carry no `semantic`
        t2.routes["GET \(Self.base)/proposals"] = { _ in [[String: Any]]() }
        let old = ReviewModel(host: FakeHost(), routes: BrainRoutes(transport: t2))
        try await old.load(run: "r1")
        #expect(old.semanticState == nil && t2.count("GET \(Self.base)/semantic") == 0)
    }

    @Test func progressAndTidyDecodeAndAnOlderCoreHasNeither() throws {
        let json = Data(
            #"""
            {"state":"ready","progress":{"done":1240,"total":2980},
             "ai_tidy":{"state":"applied","changes_url":"/x","summary":{"duplicates_merged":52,"rooms_merged":2,
               "rooms_folded":12,"rooms_before":35,"rooms_after":21}}}
            """#.utf8)
        let v = try JSONDecoder().decode(SemanticView.self, from: json)
        #expect(v.progress == SemanticProgress(done: 1240, total: 2980) && v.aiTidy?.summary?.roomsAfter == 21)
        #expect(ReviewWords.reading(v.progress) == "Local AI: 1,240 of 2,980 items")
        #expect(
            ReviewWords.tidied(try #require(v.aiTidy?.summary))
                == "Local AI tidied this: merged 52 duplicates, folded 14 rooms (35 → 21 rooms)")
        let old = try JSONDecoder().decode(SemanticView.self, from: Data(#"{"state":"ready"}"#.utf8))
        #expect(old.progress == nil && old.aiTidy == nil && ReviewWords.reading(nil) == "Local AI: reading the items…")
        let c = try JSONDecoder().decode(
            TidyChanges.self,
            from: Data(
                #"{"changes":[{"kind":"fold","item_ids":["a"],"from":"p9","from_name":"AD","to":"unsorted"}]}"#.utf8))
        #expect(
            c.changes.first?.fromName == "AD" && ReviewWords.change(c.changes[0]) == "Its items wait in No room yet")
    }

    @Test func seeChangesNamesEveryChangeByTitleGroupedByKind() async throws {
        let r = ReviewModel(host: FakeHost(), routes: BrainRoutes(transport: SampleImportTransport(semantic: "ready")))
        try await r.load(run: SampleImportTransport.run)
        await settle(r)
        #expect(
            ReviewWords.tidied(try #require(r.tidy))
                == "Local AI tidied this: merged 9 duplicates, folded 5 rooms, moved 2 items into rooms (9 → 4 rooms)")
        await r.openChanges()
        let groups = ReviewWords.tidyGroups(r.tidyChanges ?? [])
        #expect(
            groups.map(\.title) == [
                "Duplicates merged", "Rooms joined", "Small rooms folded", "Items moved into rooms",
            ])
        let names = groups.flatMap(\.changes).map { ReviewWords.changeTitle($0, titles: r.itemTitles) }
        #expect(!names.contains("Untitled item") && names.first == "Sample: queue migration order")
        #expect(names.last == "Sample: price page test B" && names.contains("AcmeShopApi"))
        #expect(ReviewWords.change(groups[0].changes[0]) == "4 copies merged into this one")
        #expect(ReviewWords.change(groups[2].changes[1]) == "Folded into Pricing experiments")
        // Titles the Core sent are used as they are; only the unnamed ones are looked up.
        #expect(r.itemTitles["k1"] == nil && r.itemTitles["m1"] == nil && r.itemTitles["k2"] != nil)
        // The Core applied the name hints: no Merge question is left while the tidy stands, and Undo brings them back.
        #expect(r.cards.allSatisfy { $0.suggestMerge == nil } && r.visible.count == 5)
        await r.undoTidy()
        #expect(r.tidyUndone && r.cards.contains { $0.suggestMerge != nil })
    }

    @Test func undoAsksTheCoreThenRereadsTheRooms() async throws {
        let (r, t) = make("ready")
        t.routes["POST \(Self.base)/semantic/undo"] = { _ in
            ["state": "ready", "ai_tidy": ["state": "undone"]]
        }
        t.routes["GET \(Self.base)/semantic/changes"] = { _ in ["changes": [[String: Any]]()] }
        try await r.load(run: "r1")
        await settle(r)
        await r.openChanges()
        #expect(r.tidy != nil && r.showingChanges && r.tidyChanges == [])
        await r.undoTidy()
        #expect(t.count("POST \(Self.base)/semantic/undo") == 1 && r.notice == nil)
        #expect(r.tidy == nil && r.tidyUndone && !r.showingChanges && t.count("GET \(Self.base)/proposals") == 2)
    }

    @Test func theRoomsAreReadAgainWhenTheStepFinishes() async throws {
        let (r, t) = make("pending")
        try await r.load(run: "r1")
        #expect(r.semanticProgress == nil)  // this pending view has no progress
        t.routes["GET \(Self.base)/semantic"] = { _ in
            ["state": "pending", "progress": ["done": 10, "total": 40]]
        }
        try await Task.sleep(for: .milliseconds(30))
        #expect(r.semanticProgress?.done == 10)
        let before = t.count("GET \(Self.base)/proposals")
        t.routes["GET \(Self.base)/semantic"] = { _ in ["state": "ready"] }
        await settle(r)
        #expect(t.count("GET \(Self.base)/proposals") == before + 1 && r.semanticProgress == nil)
    }

    @Test func aSettingKeepsTheCoresValueAndRollsBackOnAFailure() async {
        let t = FakeBrainTransport()
        t.routes["GET /modules/brain/v1/settings"] = { _ in
            [
                ["name": "semantic.enabled", "value": 1, "default": 1, "min": 0, "max": 1, "description": ""],
                [
                    "name": "semantic.max_tokens", "value": 200, "default": 128, "min": 128, "max": 256,
                    "description": "",
                ],
            ]
        }
        let s = AISettings(routes: { BrainRoutes(transport: t) })
        await s.reload()
        #expect(s.load == .ready && s.enabled && s.maxTokens == 256 && s.strength == 1)
        await s.set("semantic.enabled", 0)  // no PUT route: the fake answers 404
        #expect(s.enabled && s.notice != nil)
        t.routes["PUT /modules/brain/v1/settings/semantic.strength"] = { _ in
            ["name": "semantic.strength", "value": 2, "default": 1, "min": 0, "max": 2, "description": ""]
        }
        await s.set("semantic.strength", 2)
        #expect(s.strength == 2)
        #expect(AISettings(routes: { nil }).load == .loading)
    }
}
