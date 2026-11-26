import CoreKit
import Foundation
import Testing

@testable import Lore

@MainActor
struct LoreNoteActionsTests {
    let host = FakeHost()
    let page = FakePage()
    let core = FakeLore()
    let model: LoreModel
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lore-actions-\(UUID().uuidString)")

    init() {
        model = LoreModel(host: host, page: page, drafts: LoreDrafts(dir: dir))
        model.debounce = .milliseconds(20)
        core.put(LoreNote(id: "ln_cccccccccccc", title: "Plan", rev: 1, text: "# Plan\n\nBody\n"))
        core.put(LoreNote(id: "ln_dddddddddddd", title: "Other", rev: 1, text: "Other\n"))
        model.service = core
    }

    @Test func retitleReplacesTheFirstHeadingOrPutsOneOnTop() {
        #expect(LoreModel.retitled("# Old\n\nText\n# Two", to: "New") == "# New\n\nText\n# Two")
        #expect(LoreModel.retitled("intro\n## Sub\n# Real", to: "New") == "intro\n## Sub\n# New")
        #expect(LoreModel.retitled("```\n# not a heading\n```\n", to: "N") == "# N\n\n```\n# not a heading\n```\n")
        #expect(LoreModel.retitled("#tag only", to: "N") == "# N\n\n#tag only")
        #expect(LoreModel.retitled("", to: "N") == "# N\n")
        #expect(LoreModel.cleanTitle("  a\nb  ") == "a b")
        #expect(LoreModel.cleanTitle(" \n ") == nil)
    }

    @Test func onlyPlainLiveNotesRenameMoveAndTrash() {
        #expect(LoreModel.canEdit(LoreNote(id: "x")))
        #expect(!LoreModel.canEdit(LoreNote(id: "x", kind: "daily", day: "2026-11-26")))
        #expect(!LoreModel.canEdit(LoreNote(id: "x", trashed: true)))
    }

    @Test func renamingTheOpenNoteRewritesItsHeadingAndSaves() async {
        await model.openNote("ln_cccccccccccc")
        await model.rename("ln_cccccccccccc", to: " Launch ")
        #expect(page.text == "# Launch\n\nBody\n")
        #expect(core.notes["ln_cccccccccccc"]?.text == "# Launch\n\nBody\n")
    }

    @Test func renamingAnotherNoteSavesItFromItsHeadAndLeavesThePage() async {
        await model.openNote("ln_cccccccccccc")
        await model.rename("ln_dddddddddddd", to: "Renamed")
        #expect(core.notes["ln_dddddddddddd"]?.text == "# Renamed\n\nOther\n")
        #expect(core.log().contains("save ln_dddddddddddd 1"))
        #expect(page.text == "# Plan\n\nBody\n")
        await model.rename("ln_dddddddddddd", to: "   ")
        #expect(core.notes["ln_dddddddddddd"]?.rev == 2, "an empty name changes nothing")
    }

    @Test func deletingTheOpenNoteTrashesItOpensTodayAndUndoBringsItBack() async {
        await model.openNote("ln_cccccccccccc")
        await model.trashNote("ln_cccccccccccc", title: "Plan")
        #expect(core.notes["ln_cccccccccccc"]?.trashed == true)
        #expect(model.note?.kind == "daily")
        #expect(host.shell.toast?.message == "“Plan” moved to the trash.")
        #expect(host.shell.undoToast())
        #expect(await until { core.notes["ln_cccccccccccc"]?.trashed == false && model.note?.id == "ln_cccccccccccc" })
    }

    @Test func deletingAnotherNoteKeepsThePageOpen() async {
        await model.openNote("ln_cccccccccccc")
        await model.trashNote("ln_dddddddddddd", title: "Other")
        #expect(core.notes["ln_dddddddddddd"]?.trashed == true)
        #expect(model.note?.id == "ln_cccccccccccc")
        #expect(await until { !model.sideNotes.contains { $0.id == "ln_dddddddddddd" } })
    }

    @Test func movingFromTheListMovesTheOpenNotesChipToo() async {
        await model.openNote("ln_cccccccccccc")
        await model.moveNote("ln_cccccccccccc", to: "7")
        #expect(core.notes["ln_cccccccccccc"]?.project == "7" && model.note?.project == "7")
        await model.moveNote("ln_dddddddddddd", to: "7")
        #expect(core.notes["ln_dddddddddddd"]?.project == "7" && model.note?.id == "ln_cccccccccccc")
        #expect(LoreModel.link("ln_cccccccccccc", title: "Plan") == "[Plan](lore:ln_cccccccccccc)")
    }
}
