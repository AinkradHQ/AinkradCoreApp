import Foundation
import Testing

@testable import Brain

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
