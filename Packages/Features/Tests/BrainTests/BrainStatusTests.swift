import Foundation
import Testing

@testable import Brain

@MainActor
struct BrainStatusTests {
    @Test func theCoreAnswerIsReadAndWorded() throws {
        let json = """
            {"state":"needs_you","health":"ok","rooms":3,"distilling":0,"queued":1,"overviews":0,"failed":0,
             "needs":[{"kind":"ai_account","rooms":1}],"last_done_at":null}
            """
        let a = try JSONDecoder().decode(BrainActivityWire.self, from: Data(json.utf8))
        #expect(a.state == "needs_you" && a.needs.first?.kind == "ai_account")
        #expect(BrainStatusModel.need(a.needs[0]) == "Brain needs an AI account")
        #expect(BrainStatusModel.line(a).contains("paused"))
    }

    @Test func workingNamesHowManyPlaces() throws {
        var a = try JSONDecoder().decode(
            BrainActivityWire.self,
            from: Data(
                #"{"state":"working","health":"ok","rooms":3,"distilling":2,"queued":1,"overviews":0,"failed":0,"needs":[]}"#
                    .utf8))
        #expect(BrainStatusModel.line(a).contains("3 places"))
        a.distilling = 0
        a.queued = 1
        #expect(BrainStatusModel.line(a).contains("1 place,"))
    }
}

@MainActor
struct AutoImportTests {
    @Test func theLearningStepIsReadWithItsCost() throws {
        let json = """
            {"run":"r1","places":[{"room":"a","name":"Atlas","sources":10,"read":4,"learned":2,"state":"learning",
             "provider":"anthropic","cost_usd_micros":1420000}],"total_cost_usd_micros":1420000,"unpriced":1,"done":false}
            """
        let l = try JSONDecoder().decode(LearningWire.self, from: Data(json.utf8))
        #expect(l.places[0].provider == "anthropic" && !l.done)
        #expect(AutoFlow.dollars(l.totalCostUsdMicros) == "$1.42")
        #expect(AutoFlow.dollars(500) == "less than $0.01")
        #expect(AutoFlow.dollars(0) == "$0.00")
    }

    @Test func areasAreReadFromTheCore() throws {
        let json = """
            {"areas":[{"area":"rules","count":3,"today":1,"latest":"ask first"}],"places":2,"evidence":40,"locked_rooms":0}
            """
        let a = try JSONDecoder().decode(BrainAreasWire.self, from: Data(json.utf8))
        #expect(a.areas[0].area == "rules" && a.places == 2)
    }
}

@MainActor
struct BrainHomeMapTests {
    /// The map's shelves and the area cards are the four areas, once each, in the redesign's order.
    @Test func theHomeShowsEachAreaOnce() {
        #expect(CalmHome.order == [.knowledge, .rules, .timeline, .me])
        #expect(Set(CalmHome.order.compactMap(\.area)).count == 4)
    }
}

@Test func theSortStepSaysHowFarAndHowLongIsLeft() {
    let r = SemanticProgress(done: 3210, total: 12391)
    #expect(SortStep.count(r, left: nil) == "3,210 of 12,391")
    #expect(SortStep.count(r, left: .seconds(330)) == "3,210 of 12,391 · about 6 min left")
    #expect(SortStep.count(r, left: .seconds(40)) == "3,210 of 12,391 · under a minute left")
}
