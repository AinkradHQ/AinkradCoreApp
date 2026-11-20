import Foundation
import Testing

@testable import Shell

struct CoreUpdateTests {
    @Test func aRunningUpdateMarksTheStepsInOrder() {
        var s = CoreUpdateStatus()
        s.phase = .install
        #expect(s.steps == [.done, .now, .wait] && s.running)
        s.phase = .rolledBack
        #expect(s.steps == [.done, .done, .fail] && !s.running && s.visible)
    }

    @Test func decodesTheCoreAnswerAndSurvivesJunk() throws {
        let raw =
            #"{"current":"0.10.0","state":"rolled_back","available":null,"to":"0.10.1","progress":1,"error":"health_failed","updated_at":5,"events":[{"at":3,"step":"health","text":"Health check"}]}"#
        let s = try #require(CoreUpdateStatus.decode(Data(raw.utf8)))
        #expect(s.phase == .rolledBack && s.error == "health_failed" && s.events.count == 1)
        #expect(s.errorWords == "Core did not answer in time.")
        #expect(CoreUpdateStatus.decode(Data("nope".utf8)) == nil)
        #expect(CoreUpdateStatus.decode(Data(#"{"state":"pwned"}"#.utf8))?.phase == .idle)
    }

    @Test func releaseNotesKeepOnlyPlainLines() {
        let items = WhatsNew.parse("Calmer Settings | One page for each app\n<script>x</script>\n\nTouch ID once\n")
        #expect(
            items == [
                WhatsNewItem(title: "Calmer Settings", sub: "One page for each app"),
                WhatsNewItem(title: "Touch ID once", sub: ""),
            ])
    }
}

struct WhatsNewStoreTests {
    @Test func notesAreShownOnceAndOnlyByTheVersionTheyBelongTo() throws {
        let d = try #require(UserDefaults(suiteName: "whatsnew-\(UUID().uuidString)"))
        WhatsNewStore.save(version: "0.10.2", items: [WhatsNewItem(title: "A", sub: "b")], defaults: d)
        #expect(WhatsNewStore.take(installed: "0.10.1", defaults: d) == nil, "still the old version")
        let got = try #require(WhatsNewStore.take(installed: "0.10.2", defaults: d))
        #expect(got.items == [WhatsNewItem(title: "A", sub: "b")])
        #expect(WhatsNewStore.take(installed: "0.10.2", defaults: d) == nil, "shown once")
    }
}
