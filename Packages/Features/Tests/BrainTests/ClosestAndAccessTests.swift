import Foundation
import Testing

@testable import Admin
@testable import Brain

@MainActor
struct ClosestAndAccessTests {
    static let base = "/modules/brain/v1/imports/r1"

    @Test func theCoresClosestJSONDecodesAndAnOlderCoreHasNone() throws {
        let json = Data(
            #"""
            {"state":"ready","duplicates":[],"rooms":[],"merges":[],"closest":[
              {"item_id":"i1","room_id":"p1","room_name":"Acme Shop","in_review":true,"score":0.93,
               "runner_up":{"room_id":"p2","room_name":"Pricing","score":0.9}},
              {"item_id":"i2","room_id":"room-9","room_name":"Orchard","in_review":false,"score":0.91}]}
            """#.utf8)
        let v = try JSONDecoder().decode(SemanticView.self, from: json)
        #expect(v.closest.count == 2 && v.closest[0].runnerUp?.roomName == "Pricing" && v.closest[1].runnerUp == nil)
        #expect(!v.closest[1].inReview && ReviewWords.score(v.closest[0].score) == "0.93")
        let old = try JSONDecoder().decode(SemanticView.self, from: Data(#"{"state":"ready"}"#.utf8))
        #expect(old.closest.isEmpty)
    }

    @Test func acceptMovesOrSplitsByInReviewAndDismissIsLocal() async throws {
        let t = FakeBrainTransport()
        let hints = SemanticView(
            state: "ready",
            closest: [
                ClosestHint(itemId: "i1", roomId: "p1", roomName: "Acme Shop", inReview: true, score: 0.93),
                ClosestHint(itemId: "i2", roomId: "room-9", roomName: "Orchard", inReview: false, score: 0.91),
                ClosestHint(itemId: "i3", roomId: "p1", roomName: "Acme Shop", inReview: true, score: 0.9),
            ])
        t.routes["GET \(Self.base)/proposals"] = { _ in [[String: Any]]() }
        t.routes["GET \(Self.base)/semantic"] = { _ in
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(hints))
        }
        let moved = Seen()
        t.routes["PATCH \(Self.base)/items"] = { b in
            moved.body = b.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            return [String: Any]()
        }
        let split = Seen()
        t.routes["POST \(Self.base)/proposals/unsorted/split"] = { b in
            split.body = b.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            return [
                "id": "room-9", "name": "Orchard", "kind": "project", "kind_guess": "project", "state": "proposed",
                "signals": [String](), "warnings": [String](), "item_count": 1, "sample_titles": [String](),
                "config": [String: Any](),
            ]
        }
        let r = ReviewModel(host: FakeHost(), routes: BrainRoutes(transport: t))
        r.run = "r1"
        await r.readSemantic()
        #expect(r.closestHints.count == 3 && r.hasHints)
        r.dismiss(r.closestHints[2])
        #expect(r.closestHints.count == 2 && t.count("PATCH \(Self.base)/items") == 0)
        await r.accept(r.closestHints[0])
        #expect(moved.body?["proposal"] as? String == "p1" && (moved.body?["ids"] as? [String]) == ["i1"])
        #expect(moved.body?["mark"] == nil)
        await r.accept(r.closestHints[1])
        #expect(split.body?["name"] as? String == "Orchard" && (split.body?["item_ids"] as? [String]) == ["i2"])
    }

    @Test func accessDecodesAndPutSendsOnlyTheChangedList() async throws {
        let json = Data(#"{"room":"r","project":["shop-admin"],"runner":[],"session":["s1"]}"#.utf8)
        let a = try JSONDecoder().decode(RoomAccess.self, from: json)
        #expect(a.entries.map(\.value) == ["shop-admin", "s1"] && a.entries.map(\.kind) == [.project, .session])
        let t = FakeBrainTransport()
        let put = Seen()
        t.routes["PUT /modules/brain/v1/rooms/r1/access"] = { b in
            put.body = b.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            return ["room": "r1", "project": ["a"], "runner": [String](), "session": [String]()]
        }
        let got = try await BrainRoutes(transport: t).putRoomAccess(room: "r1", kind: .project, values: ["a"])
        #expect(put.body?.keys.sorted() == ["project"] && got.project == ["a"])
    }

    @Test func addingAndRemovingAccessAsksTheSampleCoreAndSkipsDuplicates() async throws {
        let m = BrainModel(host: FakeHost())
        var sc = SampleBrainService.Scenario()
        sc.m3 = true
        m.use(SampleBrainService(sc, pace: .milliseconds(1)))
        let c = try #require(m.candidates)
        await c.loadAccess("acme-shop")
        #expect(c.access["acme-shop"]?.project == ["shop-admin"])
        _ = await c.addAccess("acme-shop", .runner, "air")
        #expect(c.access["acme-shop"]?.runner == ["air", "build-box"])
        #expect(await c.addAccess("acme-shop", .runner, " air ") == false)
        await c.removeAccess("acme-shop", .runner, "build-box")
        #expect(c.access["acme-shop"]?.runner == ["air"])
    }
}
