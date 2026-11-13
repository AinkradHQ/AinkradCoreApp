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
        #expect(r.semanticState == "ready" && r.hasHints)
        let n = t.count("GET \(Self.base)/semantic")
        try await Task.sleep(for: .milliseconds(30))
        #expect(t.count("GET \(Self.base)/semantic") == n)
    }

    @Test func offOrNoModelShowsNothingAndAsksNothing() async throws {
        let (r, t) = make("off")
        try await r.load(run: "r1")
        #expect(r.semanticState == nil && !r.hasHints && t.count("GET \(Self.base)/semantic") == 0)
        let t2 = FakeBrainTransport()  // an older Core: cards carry no `semantic`
        t2.routes["GET \(Self.base)/proposals"] = { _ in [[String: Any]]() }
        let old = ReviewModel(host: FakeHost(), routes: BrainRoutes(transport: t2))
        try await old.load(run: "r1")
        #expect(old.semanticState == nil && t2.count("GET \(Self.base)/semantic") == 0)
    }

    @Test func mergeHintsNeedTwoRealRoomsAndSkipPairsTheCardAlreadyHints() async throws {
        var v = SampleImportTransport.sampleHints
        v.merges += [
            MergeHint(from: "pricing-experiment", to: "unsorted", fromName: "x", toName: nil, score: 0.9),
            MergeHint(from: "ghost", to: "acme-shop", fromName: "g", toName: "A", score: 0.9),
        ]
        let (r, _) = make("ready", hints: v)
        try await r.load(run: "r1")
        await settle(r)
        #expect(r.mergeHints.map(\.to) == ["acme-shop"] && r.mergeHints.first?.from == "pricing-experiment")
    }

    @Test func dismissIsLocalAndAcceptUsesTheExistingRoutes() async throws {
        let (r, t) = make("ready")
        t.routes["POST \(Self.base)/proposals/unsorted/split"] = { _ in
            [
                "id": "garden-planner", "name": "Garden planner", "kind": "project", "kind_guess": "project",
                "state": "proposed", "signals": [String](), "warnings": [String](), "item_count": 12,
                "sample_titles": [String](), "config": [String: Any](),
            ]
        }
        t.routes["PATCH \(Self.base)/items"] = { _ in [String: Any]() }
        t.routes["POST \(Self.base)/proposals/pricing-experiment/merge"] = { _ in
            [
                "id": "acme-shop", "name": "Acme", "kind": "product", "kind_guess": "product", "state": "proposed",
                "signals": [String](), "warnings": [String](), "item_count": 8, "sample_titles": [String](),
                "config": [String: Any](),
            ]
        }
        try await r.load(run: "r1")
        await settle(r)
        let (room, copies, merge) = (r.roomHints[0], r.copyHints[0], r.mergeHints[0])
        r.dismiss(r.roomHints[1])
        #expect(r.roomHints.count == 1 && t.count("GET \(Self.base)/proposals") == 1)

        let seen = Seen()
        t.routes["PATCH \(Self.base)/items"] = { b in
            seen.body = b.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            return [String: Any]()
        }
        await r.accept(copies)
        #expect(seen.body?["mark"] as? String == "refused" && (seen.body?["ids"] as? [String]) == ["d2", "d3"])
        await r.accept(room)
        #expect(t.count("POST \(Self.base)/proposals/unsorted/split") == 1)
        await r.accept(merge)
        #expect(t.count("POST \(Self.base)/proposals/pricing-experiment/merge") == 1)
        #expect(t.count("GET \(Self.base)/proposals") == 4)  // load, then one reload per accept
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
