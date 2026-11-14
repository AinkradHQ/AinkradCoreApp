import Foundation
import Testing

@testable import Admin
@testable import Brain

final class Seen: @unchecked Sendable { nonisolated(unsafe) var body: [String: Any]? }

@MainActor
struct ReviewSemanticTests {
    static let base = "/modules/brain/v1/imports/r1"

    func make(_ state: String, hints: SemanticView = SampleImportTransport.sampleHints) -> (
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
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(SampleImportTransport.sampleHints))
        }
        await settle(r)
        #expect(r.semanticState == "ready" && r.tidy?.after == 6)
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
            {"state":"pending","progress":{"done":1240,"total":2980},
             "tidy":{"before":35,"after":21,"changes":[{"kind":"fold","title":"Garden notes","into":"Personal"}]}}
            """#.utf8)
        let v = try JSONDecoder().decode(SemanticView.self, from: json)
        #expect(v.progress == SemanticProgress(done: 1240, total: 2980) && v.tidy?.changes.first?.into == "Personal")
        #expect(ReviewWords.reading(v.progress) == "Local AI: 1,240 of 2,980 items")
        let old = try JSONDecoder().decode(SemanticView.self, from: Data(#"{"state":"ready"}"#.utf8))
        #expect(old.progress == nil && old.tidy == nil && ReviewWords.reading(nil) == "Local AI: reading the items…")
    }

    @Test func theSummaryNamesWhatChangedAndTheChangesAreGroupedByName() throws {
        let t = try #require(SampleImportTransport.sampleHints.tidy)
        #expect(
            ReviewWords.tidied(t)
                == "Local AI tidied this: merged 9 duplicates, folded 4 rooms (10 → 6 rooms)"
        )
        let groups = ReviewWords.tidyGroups(t)
        #expect(groups.map(\.title) == ["Duplicates merged", "Small rooms folded", "Rooms joined"])
        #expect(groups[1].changes.map(\.title) == ["Garden notes", "Price page variant", "Old shop api"])
        #expect(ReviewWords.change(groups[0].changes[0]) == "4 copies kept as one")
        #expect(ReviewWords.change(groups[1].changes[0]) == "Now in Personal")
    }

    @Test func undoAsksTheCoreThenRereadsTheRoomsAndTheStep() async throws {
        let (r, t) = make("ready")
        t.routes["POST \(Self.base)/semantic/undo"] = { _ in [String: Any]() }
        try await r.load(run: "r1")
        await settle(r)
        r.showingChanges = true
        #expect(r.tidy != nil)
        t.routes["GET \(Self.base)/semantic"] = { _ in ["state": "ready"] }
        await r.undoTidy()
        #expect(t.count("POST \(Self.base)/semantic/undo") == 1 && r.notice == nil)
        #expect(r.tidy == nil && !r.showingChanges && t.count("GET \(Self.base)/proposals") == 2)
    }

    @Test func theRoomsAreReadAgainWhenTheStepFinishes() async throws {
        let (r, t) = make("pending")
        try await r.load(run: "r1")
        #expect(r.semanticProgress == nil)  // the sample's pending view has no progress
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
