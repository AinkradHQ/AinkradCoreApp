import Foundation
import SwiftUI
import Testing

@testable import Agents

struct ToolRunsTests {
    private func e(_ seq: Int64, _ kind: EntryKind) -> TranscriptEntry {
        TranscriptEntry(seq: seq, at: .now, kind: kind)
    }
    private func done(_ seq: Int64, _ name: String, ok: Bool = true) -> TranscriptEntry {
        e(seq, .toolDone(id: "\(seq)", name: name, summary: "", ok: ok, exitCode: nil, output: "", durationMs: 100))
    }

    @Test func twoOrMoreToolStepsFoldIntoOneRunKeepingTheFirstSeq() {
        let items = TranscriptItem.items([
            e(1, .assistant("Reading")), done(2, "Read"), done(3, "Edit"), done(4, "Bash"),
            e(5, .assistant("Done")), done(6, "Read"),
        ])
        #expect(items.map(\.id) == [1, 2, 5, 6])
        guard case .run(let run) = items[1] else {
            Issue.record("no run")
            return
        }
        #expect(run.count == 3)
        if case .one = items[3] {} else { Issue.record("a lone step stays a row") }
    }

    @Test func aFoldedRunIsOneRowAndAnOpenRunListsItsStepsAfterIt() {
        let items = TranscriptItem.items([e(1, .assistant("Go")), done(2, "Read"), done(3, "Edit")])
        #expect(ColumnRow.rows(items) { _, _ in false }.map(\.id) == [1, -3])
        #expect(ColumnRow.rows(items) { _, _ in true }.map(\.id) == [1, -3, 2, 3])
        #expect(!ColumnRow.openByDefault([done(2, "Read"), done(3, "Edit")]))
        #expect(ColumnRow.openByDefault([done(2, "Read"), done(3, "Bash", ok: false)]))
    }

    @Test func composerButtonFollowsWhatIsHappening() {
        #expect(ComposerAction.of(running: true, hasText: false, canSend: false) == .stop)
        #expect(ComposerAction.of(running: true, hasText: true, canSend: true) == .queue)
        #expect(ComposerAction.of(running: false, hasText: true, canSend: true) == .send)
        #expect(ComposerAction.of(running: false, hasText: false, canSend: false) == .idle)
        #expect(ComposerAction.of(running: false, hasText: true, canSend: false) == .idle)
    }

    @Test func connectionCuesNeverJoinARun() {
        let items = TranscriptItem.items([done(1, "Read"), done(2, "github.get_issue"), done(3, "Read")])
        #expect(items.count == 3)
    }

    @Test func summaryCountsEachKindInPlainWords() {
        let steps = [done(1, "Read"), done(2, "Read"), done(3, "Edit"), done(4, "Bash", ok: false)]
            .compactMap(ToolStep.init)
        #expect(ToolStep.summary(steps) == "Read 2 files · edited 1 file · ran 1 command")
    }

    @Test func shortcutsMatchWithoutCaseAndHaveNoDuplicates() {
        #expect(SessionShortcut.match("G", [.command, .shift]) == .findPrevious)
        #expect(SessionShortcut.match("f", .command) == .find)
        #expect(SessionShortcut.match("f", []) == nil)
        let labels = SessionShortcut.allCases.map(\.label)
        #expect(Set(labels).count == labels.count)
        #expect(SessionShortcut.review.label == "⇧⌘R")
    }
}
