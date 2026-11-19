import CoreKit
import Foundation
import Testing

@testable import Lore

struct LoreOutlineTests {
    @Test func headingsSkipCodeAndCountRepeats() {
        let md = "# Title\n\ntext\n## Steps\n```\n# not a heading\n```\n## Steps\n#### deep\n#nospace\n### \n"
        let h = LoreOutline.headings(md)
        #expect(h.map(\.title) == ["Title", "Steps", "Steps"])
        #expect(h.map(\.level) == [1, 2, 2])
        #expect(h.map(\.occurrence) == [0, 0, 1])
    }

    @Test func wordsCountsWhitespaceSeparatedRuns() {
        #expect(LoreOutline.words("a  b\nc") == 3)
        #expect(LoreOutline.words("") == 0)
    }

    @Test func theTreeGroupsPersonalProjectsAndJournal() {
        let notes = [
            LoreNote(id: "a", project: nil, title: "P"),
            LoreNote(id: "b", project: "7", title: "Q"),
            LoreNote(id: "c", kind: "daily", day: "2026-11-18", title: "d1"),
            LoreNote(id: "d", kind: "daily", day: "2026-11-19", title: "d2"),
            LoreNote(id: "e", project: "7", title: "Gone", trashed: true),
        ]
        let g = LoreTree.groups(notes, projects: ["7": "Atlas", "8": "Birch"])
        #expect(g.map(\.name) == ["Personal", "Atlas", "Journal"], "Birch is empty, so it is left out")
        #expect(g[1].notes.map(\.id) == ["b"], "a trashed note is not in the tree")
        #expect(g[2].notes.map(\.id) == ["d", "c"], "newest day first")
    }
}
