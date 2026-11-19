import Foundation
import Shell
import Testing

@testable import Brain

struct BrainGlanceTests {
    private func data(_ activity: String, learned: String = "[]") throws -> GlanceData {
        let d = JSONDecoder()
        let areas = #"{"areas":[{"area":"rules","count":38,"today":1,"latest":null},{"area":"me","count":14,"today":0,"latest":null}],"places":21,"evidence":4,"locked_rooms":0}"#
        return GlanceData(
            activity: try d.decode(GlanceActivity.self, from: Data(activity.utf8)),
            areas: try d.decode(GlanceAreas.self, from: Data(areas.utf8)),
            learned: try d.decode([GlanceLearned].self, from: Data(learned.utf8)))
    }

    @Test func workingTidyingShowsTheFlowTheAreasAndWhatItLearned() throws {
        let g = BrainGlanceMaker.glance(
            try data(
                #"{"state":"working","health":"ok","rooms":10,"distilling":2,"queued":3,"overviews":0,"failed":0,"needs":[]}"#,
                learned: #"[{"id":"a","room":"r1","area":"me","body":"x"},{"id":"b","room":"r1"}]"#))
        #expect(g.flowStep == 1 && g.doing == "Tidying 2 places into Knowledge")
        #expect(g.progress == 0.5 && g.healthy && g.learned == 2)
        #expect(g.stats.map(\.label) == ["Me", "Rules", "Knowledge", "Timeline", "Places"])
        #expect(g.stats.map(\.count) == [14, 38, 0, 0, 21])
        #expect(g.stats.map(\.area) == ["me", "rules", "knowledge", "timeline", "places"])
    }

    @Test func idleHasNoFlowAndANeedIsSaidInWords() throws {
        let idle = BrainGlanceMaker.glance(
            try data(#"{"state":"idle","health":"ok","rooms":3,"distilling":0,"queued":0,"overviews":0,"failed":0,"needs":[]}"#))
        #expect(idle.flowStep == nil && idle.doing == nil && idle.learned == 0)
        let needy = BrainGlanceMaker.glance(
            try data(
                #"{"state":"needs_you","health":"attention","rooms":3,"distilling":0,"queued":1,"overviews":0,"failed":0,"needs":[{"kind":"ai_account","rooms":1}]}"#
            ))
        #expect(needy.status == "Needs an AI account" && !needy.healthy)
    }

    @Test func theStepFollowsWhatTheCoreIsDoing() throws {
        func step(_ tail: String) throws -> Int? {
            try BrainGlanceMaker.doing(
                JSONDecoder().decode(
                    GlanceActivity.self,
                    from: Data(#"{"state":"working","health":"ok","rooms":4,\#(tail),"needs":[]}"#.utf8)))?.step
        }
        #expect(try step(#""distilling":0,"queued":1,"overviews":0"#) == 0)
        #expect(try step(#""distilling":1,"queued":0,"overviews":0"#) == 1)
        #expect(try step(#""distilling":0,"queued":0,"overviews":2"#) == 2)
    }
}
