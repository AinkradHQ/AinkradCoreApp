import Foundation
import Testing

@testable import Lore

@MainActor struct LoreOptionsTests {
    @Test func startsOnTheLastNoteOnlyWhenKeptAndSet() {
        #expect(LoreOptions.noteAtStart(openLast: true, last: "n_abc") == "n_abc")
        #expect(LoreOptions.noteAtStart(openLast: false, last: "n_abc") == nil)
        #expect(LoreOptions.noteAtStart(openLast: true, last: "") == nil, "the last page was a day: today's opens")
    }

    @Test func textSizeScales() {
        #expect(LoreOptions.scale("small") < LoreOptions.scale("medium"))
        #expect(LoreOptions.scale("large") > LoreOptions.scale("medium"))
        #expect(LoreOptions.scale("nonsense") == 1)
    }
}
