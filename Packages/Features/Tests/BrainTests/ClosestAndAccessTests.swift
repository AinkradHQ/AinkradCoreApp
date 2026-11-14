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
