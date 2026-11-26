import AppKit
import CoreKit
import LoreEditor
import Testing

@testable import Lore

@MainActor struct LoreWeekTests {
    @Test func theWeekHoldsTheDayAndStartsOnTheCalendarsFirstWeekday() {
        var monday = Calendar(identifier: .gregorian)
        monday.firstWeekday = 2
        let week = LoreWeek.days(of: "2026-11-26", calendar: monday)
        #expect(week.first == "2026-11-23" && week.last == "2026-11-29" && week.count == 7)
        #expect(week.contains("2026-11-26"))
        var sunday = Calendar(identifier: .gregorian)
        sunday.firstWeekday = 1
        #expect(LoreWeek.days(of: "2026-11-26", calendar: sunday).first == "2026-11-22")
        #expect(LoreWeek.days(of: "2026-12-31", calendar: monday).last == "2027-01-03", "a week runs into the new year")
        #expect(LoreWeek.days(of: "not a day").isEmpty)
    }

    @Test func writtenDaysAreLiveDailyNotesOnly() {
        let notes = [
            LoreNote(id: "a", kind: "daily", day: "2026-11-24", title: ""),
            LoreNote(id: "b", kind: "daily", day: "2026-11-25", title: "", trashed: true),
            LoreNote(id: "c", project: "7", title: "Plan"),
        ]
        #expect(LoreWeek.written(notes) == ["2026-11-24"])
    }

    @Test func readingTimeRoundsUpAndIsZeroForNothing() {
        #expect(LoreWeek.readingMinutes(0) == 0)
        #expect(LoreWeek.readingMinutes(1) == 1)
        #expect(LoreWeek.readingMinutes(200) == 1)
        #expect(LoreWeek.readingMinutes(201) == 2)
    }

    @Test func templatesAreDistinctAndEndReadyToType() {
        let ids = LoreTemplates.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for t in LoreTemplates.all {
            #expect(NSImage(systemSymbolName: t.symbol, accessibilityDescription: nil) != nil)
        }
    }

    @Test func aDaysNoteIsNamedByItsDate() {
        let day = LoreNote(id: "a", kind: "daily", day: "2026-11-24", title: "")
        #expect(LoreLeftSidebar.name(day) != "Untitled note")
        #expect(LoreLeftSidebar.name(LoreNote(id: "b", title: "  ")) == "Untitled note")
    }

    @Test func aTemplateFillsOnlyABlankPage() async {
        let page = FakePage()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = LoreModel(host: FakeHost(), page: page, drafts: LoreDrafts(dir: dir))
        model.load = .ready
        model.pageBlank = true
        model.start(LoreTemplates.all[2])
        #expect(page.text == LoreTemplates.all[2].markdown)
        #expect(!model.pageBlank)
        page.text = "kept"
        model.start(LoreTemplates.all[0])
        #expect(page.text == "kept", "a page with text is never replaced")
    }
}
