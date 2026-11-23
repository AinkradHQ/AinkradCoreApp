import Foundation
import Shell
import Testing

@testable import Brain

struct BrainRedesignTests {
    private let d = JSONDecoder()

    @Test func anOlderCoreStillDecodesAndHasNoNewFields() throws {
        let areas = try d.decode(
            BrainAreasWire.self,
            from: Data(
                #"{"areas":[{"area":"rules","count":3,"today":1,"latest":null}],"places":2,"evidence":0,"locked_rooms":0}"#
                    .utf8))
        #expect(areas.ruleKinds == nil && areas.areas[0].series == nil)
        let rec = try d.decode(
            BrainAreaRecordWire.self,
            from: Data(
                #"{"id":"a","room":"r","room_name":"R","type":"rule","body":"x","tags":[],"support":2,"created_at":"","seen_at":""}"#
                    .utf8))
        #expect(rec.kind == nil && rec.following == nil && rec.everywhere == nil)
    }

    @Test func api101FieldsAreRead() throws {
        let areas = try d.decode(
            BrainAreasWire.self,
            from: Data(
                #"{"areas":[{"area":"rules","count":3,"today":1,"latest":null,"series":[0,1,2]}],"places":2,"evidence":0,"locked_rooms":0,"rule_kinds":{"always":1,"never":1,"prefer":1}}"#
                    .utf8))
        #expect(areas.ruleKinds?.never == 1 && areas.areas[0].series == [0, 1, 2])
        let rec = try d.decode(
            BrainAreaRecordWire.self,
            from: Data(
                #"{"id":"a","room":"r","room_name":"R","type":"rule","body":"x","tags":[],"support":2,"created_at":"","seen_at":"","kind":"never","everywhere":true,"rooms":[{"room":"r","name":"R"}],"following":false}"#
                    .utf8))
        #expect(
            rec.kind == "never" && rec.everywhere == true && rec.rooms?.first?.name == "R" && rec.following == false)
        let p = try d.decode(
            [PlaceWire].self,
            from: Data(
                #"[{"room":"me","name":"Me","knowledge":1,"rules":2,"timeline":3,"learning":true,"locked":false}]"#.utf8
            ))
        #expect(p[0].total == 6 && p[0].learning && p[0].lastLearnedAt == nil)
        let days = try d.decode(
            ActivityDaysWire.self,
            from: Data(
                #"{"days":[{"day":"2026-11-23","learned":4,"tidied":2,"events":[{"kind":"tidied","count":120,"rooms":["A"],"took_s":360}]}]}"#
                    .utf8))
        #expect(days.days[0].events[0].tookS == 360)
    }

    @Test func activityIsSaidInPlainWords() {
        let e = ActivityDaysWire.Event(kind: "learned", count: 38, rooms: ["A", "B", "C", "D"])
        #expect(ActivityWords.line(e).line == "Learned 38 new things from 4 places")
        let t = ActivityDaysWire.Event(kind: "tidied", count: 120, rooms: ["A"], tookS: 360)
        #expect(ActivityWords.line(t).meta == "A · took 6 min")
        #expect(
            ActivityWords.line(.init(kind: "overview", count: 1, rooms: ["A"])).line == "Wrote a fresh overview of A")
    }

    @Test func aNewRuleSaysEverywhereOrItsPlaces() throws {
        func json(_ b: NewRuleBody) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(b)) as? [String: Any] ?? [:]
        }
        #expect(try json(NewRuleBody(body: "x", kind: "never", rooms: nil))["rooms"] as? String == "everywhere")
        #expect(try json(NewRuleBody(body: "x", kind: "never", rooms: ["r1"]))["rooms"] as? [String] == ["r1"])
    }

    @Test func toCheckSaysWhyItAsks() {
        var c = InboxCandidate(id: "1", room: "r", roomName: "R", kind: .fact, text: "x")
        #expect(CheckWords.question(c) == "Keep this?" && CheckWords.why(nil) == nil)
        c.reason = "conflict"
        c.otherBody = "y"
        #expect(CheckWords.question(c) == "Is this still right?" && CheckWords.why(c.reason) == "Two sessions disagree")
        #expect(CheckWords.context(c)?.contains("“y”") == true)
    }

    @Test func theDropdownTilesFollowTheAreas() throws {
        let g = BrainGlanceMaker.glance(
            GlanceData(
                activity: try d.decode(
                    GlanceActivity.self,
                    from: Data(
                        #"{"state":"idle","health":"ok","rooms":2,"distilling":0,"queued":0,"overviews":0,"needs":[]}"#
                            .utf8)),
                areas: try d.decode(
                    GlanceAreas.self,
                    from: Data(
                        #"{"areas":[{"area":"knowledge","count":10,"today":2,"series":[1,2]},{"area":"me","count":0}],"places":3}"#
                            .utf8)),
                learned: [GlanceLearned(id: "a", room: "r", body: "Newest", createdAt: nil)]))
        #expect(g.tiles.map(\.area) == ["knowledge", "rules", "timeline", "me"])
        #expect(g.tiles[0].today == 2 && g.tiles[0].series == [1, 2] && g.known == 10 && g.places == 3)
        #expect(g.latest == "Newest" && g.status == "Up to date")
    }
}
