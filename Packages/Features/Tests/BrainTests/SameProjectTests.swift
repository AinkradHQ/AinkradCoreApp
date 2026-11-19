import Foundation
import Testing

@testable import Admin
@testable import Brain

/// "Same project as…", its list in Settings, and the declined tidy (AinkradCore #249, API minor 72).
@MainActor
struct SameProjectTests {
    static let base = "/modules/brain/v1"

    func review(_ t: FakeBrainTransport, host: FakeHost = FakeHost()) -> ReviewModel {
        nonisolated(unsafe) let cards: [[String: Any]] = ["automotive", "dvx", "unsorted"].map {
            [
                "id": $0, "name": $0 == "dvx" ? "harborauto" : $0, "kind": "product", "kind_guess": "product",
                "state": "proposed",
                "signals": [String](), "warnings": [String](), "item_count": 3, "sample_titles": [String](),
                "config": [String: Any](),
            ]
        }
        t.routes["GET \(Self.base)/imports/r1/proposals"] = { _ in cards }
        return ReviewModel(host: host, routes: BrainRoutes(transport: t))
    }

    @Test func sameProjectPostsIntoThenReadsTheRoomsAgain() async throws {
        let t = FakeBrainTransport()
        let seen = Seen()
        t.routes["POST \(Self.base)/imports/r1/proposals/dvx/same-project"] = { b in
            seen.body = b.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            return [
                "id": "automotive", "name": "HarborMotors", "kind": "product", "kind_guess": "product",
                "state": "proposed", "item_count": 6,
                "signals": [String](), "warnings": [String](), "sample_titles": [String](), "config": [String: Any](),
            ]
        }
        let host = FakeHost()
        let r = review(t, host: host)
        try await r.load(run: "r1")
        let dvx = try #require(r.cards.first { $0.id == "dvx" })
        // An older Core: no menu.
        #expect(!r.offersSameProject(dvx))
        r.canSameProject = true
        #expect(r.offersSameProject(dvx) && r.sameProjectChoices(for: "dvx").map(\.id) == ["automotive"])
        let unsorted = try #require(r.cards.first { $0.isUnsorted })
        #expect(!r.offersSameProject(unsorted))
        r.openSameProject("dvx")
        await r.sameProject("dvx", into: "automotive")
        #expect(seen.body?["into"] as? String == "automotive" && r.notice == nil && r.sameProjectFor == nil)
        #expect(t.count("GET \(Self.base)/imports/r1/proposals") == 2)
        #expect(host.shell.toast?.message == "harborauto is now part of HarborMotors.")
    }

    @Test func aRefusedSameProjectKeepsThePickerAndSaysWhy() async throws {
        let t = FakeBrainTransport()  // no route: the fake answers 404
        let r = review(t)
        try await r.load(run: "r1")
        r.canSameProject = true
        r.openSameProject("dvx")
        await r.sameProject("dvx", into: "automotive")
        #expect(r.notice != nil && r.sameProjectFor == "dvx")
    }

    @Test func theSettingsListReadsAndRemovesAnAlias() async {
        let t = FakeBrainTransport()
        t.routes["GET \(Self.base)/aliases"] = { _ in
            [["from": "harborauto", "to": "HarborMotors"], ["from": "shopapi", "to": "Acme Shop"]]
        }
        t.routes["DELETE \(Self.base)/aliases/harborauto"] = { _ in [["from": "shopapi", "to": "Acme Shop"]] }
        let list = SameProjectList(routes: { BrainRoutes(transport: t) })
        await list.reload()
        #expect(list.aliases.map(\.to) == ["HarborMotors", "Acme Shop"])
        await list.remove(list.aliases[0])
        #expect(list.aliases == [RoomAlias(from: "shopapi", to: "Acme Shop")] && list.notice == nil)
        await list.remove(list.aliases[0])  // no route: the list stays and says why
        #expect(list.aliases.count == 1 && list.notice != nil)
    }

    @Test func theGateFollowsTheCoresApiMinor() async {
        let m = BrainModel(host: FakeHost())
        #expect(!m.remembersSameProject)
        m.apiMinor = 71
        #expect(!m.remembersSameProject)
        m.apiMinor = 72
        #expect(m.remembersSameProject)
    }

    @Test func aDeclinedTidyChangedNothingAndOffersNoUndo() async throws {
        let v = try JSONDecoder().decode(
            SemanticView.self,
            from: Data(
                #"{"state":"ready","ai_tidy":{"state":"declined","summary":{"duplicates_merged":40,"rooms_before":9,"rooms_after":2}}}"#
                    .utf8))
        #expect(v.aiTidy?.state == "declined")
        let r = ReviewModel(
            host: FakeHost(), routes: BrainRoutes(transport: SampleImportTransport(semantic: "declined")))
        try await r.load(run: SampleImportTransport.run)
        await r.watching?.value
        #expect(r.semanticState == "ready" && r.tidyDeclined && r.tidy == nil && !r.tidyUndone)
        #expect(ReviewWords.declined == "The local AI was not sure, so it changed nothing.")
        // The rules' proposal stands: nothing was merged away.
        #expect(r.visible.contains { $0.id == "acme-shop-api" })
    }
}
