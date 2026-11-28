import Admin
import CoreKit
import Foundation
import Shell
import Testing

@testable import Projects

// QA lane 1: create, archive, delete, kind and the write guards.

@MainActor
private func make(_ host: FakeHost = FakeHost()) async -> (ProjectsModel, FakeService, FakeHost) {
    let m = ProjectsModel(host: host, defaults: UserDefaults(suiteName: "qa1-tests-\(UUID())")!)
    let s = FakeService()
    m.use(s)
    _ = await until { m.load == .ready }
    return (m, s, host)
}

private func pick(_ name: String) -> PickRepo {
    PickRepo(org: "o", name: name, url: "https://github.com/o/\(name)")
}

private func gh(_ name: String) -> PickRepo {
    PickRepo(
        org: "o", name: name, url: "https://github.com/o/\(name)", fullName: "o/\(name)", defaultBranch: "main")
}

private func existing(_ slug: String, name: String, age: TimeInterval = 86400 * 90) -> ProjectItem {
    var p = ProjectItem(
        id: 50, slug: slug, name: name, description: "mine", expose: true, repos: [], updatedAt: Date())
    p.createdAt = Date().addingTimeInterval(-age)
    return p
}

@MainActor
struct CreateAdoptionTests {
    // F-1
    @Test func aTakenLinkNeverAdoptsTheProjectThatHoldsIt() async {
        let (m, s, _) = await make()
        s.seed(existing("tidepool", name: "Tidepool"))
        await m.reload()
        s.takenSlugs = ["tidepool"]
        let ok = await m.create(name: "Tidepool", slug: "tidepool", colour: .teal, repos: [pick("api")], expose: false)
        #expect(!ok)
        #expect(s.calls == ["create tidepool"], "nothing is added to, patched or archived on the project that was there")
        #expect(m.wizardError == "That link name is taken. Pick another.")
        #expect(m.projects.count == 1)
    }

    @Test func aDroppedConnectionNeverTakesOverAnOldProjectOfTheSameLink() async {
        let (m, s, _) = await make()
        s.seed(existing("tidepool", name: "Tidepool"))
        s.failCreate = URLError(.networkConnectionLost)
        #expect(await m.create(name: "Tidepool", slug: "tidepool", colour: .teal, repos: [pick("api")]) == false)
        #expect(s.calls == ["create tidepool"], "it was not made now, so it is not ours")
    }

    @Test func aLostAnswerFindsTheProjectJustMadeAndFinishesIt() async {
        let (m, s, _) = await make()
        s.loseAnswerFor = ["tidepool"]
        let ok = await m.create(name: "Tidepool", slug: "tidepool", colour: .teal, repos: [pick("api")])
        #expect(ok && s.calls.contains("repo api primary=true"))
        #expect(m.projects.count == 1)
    }

    @Test func onlyAnAnswerThatWasLostCanBeRecovered() {
        #expect(ProjectsModel.answerLost(URLError(.timedOut)))
        #expect(ProjectsModel.answerLost(CoreError.offline("down")))
        #expect(ProjectsModel.answerLost(CoreError.http(status: 502, code: "bad_gateway", message: "")))
        #expect(!ProjectsModel.answerLost(CoreError.http(status: 409, code: "conflict", message: "slug exists")))
        #expect(!ProjectsModel.answerLost(CoreError.forbiddenScope))
    }
}

@MainActor
struct WizardFinishTests {
    // F-9
    @Test func aCreatedProjectStaysEvenWhenTheListReadAfterItFails() async {
        let (m, s, _) = await make()
        s.failList = URLError(.timedOut)
        let ok = await m.create(name: "Tidepool", slug: "tidepool", colour: .teal, wizard: true)
        #expect(ok)
        #expect(m.project(m.wizardProjectID) != nil, "the wizard still finds its project, so a second Create is not offered")
    }

    // F-10
    @Test func openProjectLeavesNoDraftBehind() async {
        let (m, _, _) = await make()
        _ = await m.create(name: "Tidepool", slug: "tidepool", colour: .teal, wizard: true)
        var d = WizardDraft()
        d.name = "Tidepool"
        #expect(m.draftToKeep(d, made: true) != nil, "a dialog closed with the project made keeps it")
        m.openWizardProject()
        #expect(m.wizardDraft == nil)
        #expect(m.draftToKeep(d, made: false) == nil, "the closing wizard cannot save the draft again")
        NewProjectDialogs.openWizard(m, name: "")
        #expect(m.wizardFinished == false)
    }

    // F-27
    @Test func theWizardsErrorStaysOutOfSettings() async {
        let (m, _, _) = await make()
        m.writeError = "settings said no"
        #expect(await m.create(name: "7 seas", slug: "7-seas", colour: .blue) == false)
        #expect(m.wizardError == "The link has to start with a letter.")
        #expect(m.writeError == "settings said no")
        m.clearWizardError()
        #expect(m.wizardError == nil && m.writeError == "settings said no")
    }
}

@MainActor
struct CreateWritesTests {
    // F-39
    @Test func api112SendsTheColourAndKindInTheCreateAndPatchesNothing() async {
        let (m, s, _) = await make()
        m.core110 = true
        m.core111 = true
        m.core112 = true
        let ok = await m.create(name: "Tidepool", slug: "tidepool", colour: .teal, expose: true, kind: .app)
        #expect(ok && s.lastColor == "teal")
        #expect(s.calls == ["create tidepool"], "no PATCH: the public link is the Core's default and the rest went in the create")
    }

    @Test func theGithubRouteOnlyPatchesTheColourAndALostColourDoesNotUndoTheProject() async {
        let (m, s, _) = await make()
        m.core110 = true
        m.core111 = true
        m.core112 = true
        s.refusePatch = CoreError.http(status: 400, code: "bad_request", message: "nope")
        let ok = await m.create(name: "Tidepool", slug: "tidepool", colour: .teal, repos: [gh("api")], wizard: true)
        #expect(ok, "a colour that could not be saved is told, not a reason to roll back")
        #expect(!s.calls.contains("archive"))
        #expect(m.wizardIssues.contains { $0.contains("colour") })
    }

    @Test func aKindOnApi111IsPatchedOnlyWhenItIsNotTheDefault() async {
        let (m, s, _) = await make()
        m.core111 = true
        _ = await m.create(name: "Tidepool", slug: "tidepool", colour: .teal, kind: .web)
        #expect(!s.calls.contains { $0.hasPrefix("kind") })
        _ = await m.create(name: "Quill", slug: "quill", colour: .teal, kind: .infra)
        #expect(s.calls.contains("kind infra"))
    }

    // F-15
    @Test func theUndoRunsInsideTheCreatesTouchIDAndSaysWhatReallyHappened() async {
        let (m, s, host) = await make()
        m.core112 = true
        s.refuseRepo = "web"
        _ = await m.create(name: "Tidepool", slug: "tidepool", colour: .teal, repos: [pick("api"), pick("web")])
        #expect(host.reasons.count == 1, "archive and delete rode the same Touch ID")
        #expect(s.calls.suffix(2) == ["archive", "delete"])
        #expect(m.wizardError?.hasSuffix("Nothing was left behind.") == true)
    }

    @Test func aDeleteThatFailedIsNotReportedAsNothingLeftBehind() async {
        let (m, s, _) = await make()
        m.core112 = true
        s.refuseRepo = "web"
        s.deleteError = CoreError.http(status: 409, code: "project_running", message: "")
        _ = await m.create(name: "Tidepool", slug: "tidepool", colour: .teal, repos: [pick("api"), pick("web")])
        #expect(m.wizardError?.contains("could not be deleted") == true)
        #expect(m.wizardError?.contains("Nothing was left behind") == false)
    }

    @Test func beforeApi112NoDeleteIsPromised() async {
        let (m, s, _) = await make()
        s.refuseRepo = "web"
        _ = await m.create(name: "Tidepool", slug: "tidepool", colour: .teal, repos: [pick("api"), pick("web")])
        #expect(m.wizardError?.contains("cannot delete") == true)
        #expect(m.wizardError?.contains("from Archived") == false)
    }

    @Test func anArchiveThatFailedIsSaidSo() async {
        let (m, s, _) = await make()
        s.refuseRepo = "web"
        s.archiveError = URLError(.timedOut)
        _ = await m.create(name: "Tidepool", slug: "tidepool", colour: .teal, repos: [pick("api"), pick("web")])
        #expect(m.wizardError?.contains("still in your list") == true)
    }

    // F-40
    @Test func roomsOfArchivedProjectsAreNotOffered() async {
        let (m, s, _) = await make()
        s.placesList = [BrainPlace(id: "r1", name: "A"), BrainPlace(id: "r2", name: "B"), BrainPlace(id: "r3", name: "C")]
        var live = existing("a", name: "A")
        live.roomID = "r1"
        var old = existing("b", name: "B")
        old.roomID = "r2"
        m.projects = [live]
        m.archivedList = [old]
        await m.loadPlaces()
        #expect(m.places?.map(\.id) == ["r3"])
        let c = ProjectConflict(code: "room_linked", message: "room is linked")
        #expect(c == .roomLinked && c.words.contains("Brain room"))
    }
}

@MainActor
struct ArchiveDeleteTests {
    private func running(_ p: ProjectItem) -> ProjectItem {
        var p = p
        p.repos = [
            RepoItem(
                id: 1, name: "a", remoteURL: "https://x/a", branch: "main", primary: true, fetchedAt: Date(),
                fetchError: nil)
        ]
        p.run = RunSummary(state: .running, services: 1)
        return p
    }

    // F-6
    @Test func archivingARunningProjectStopsItFirstUnderOneTouchID() async {
        let (m, s, host) = await make()
        let p = running(existing("tidepool", name: "Tidepool"))
        s.seed(p)
        await m.archive(p)
        #expect(s.calls == ["run stop", "archive"])
        #expect(host.reasons.count == 1)
    }

    // F-7
    @Test func deletingWhatIsRunningAsksToStopItFirst() async {
        let (m, s, host) = await make()
        m.core112 = true
        await m.deleteForever(running(existing("tidepool", name: "Tidepool")))
        #expect(s.calls.isEmpty && host.reasons.isEmpty)
        #expect(host.shell.toast?.message.contains("Stop") == true)
    }

    @Test func aProjectAlreadyArchivedByAnEarlierTryIsStillDeleted() async {
        let (m, s, host) = await make()
        m.core112 = true
        s.archiveError = CoreError.http(status: 409, code: "conflict", message: "the project is archived")
        await m.deleteForever(existing("tidepool", name: "Tidepool"))
        #expect(s.calls == ["archive", "delete"])
        #expect(host.shell.toast?.message == "Tidepool deleted")
    }

    @Test func aRunningRefusalAndANotArchivedRefusalHaveTheirOwnWords() async {
        let (m, s, host) = await make()
        m.core112 = true
        s.deleteError = CoreError.http(status: 409, code: "project_running", message: "the project is running")
        await m.deleteForever(existing("tidepool", name: "Tidepool"))
        #expect(host.shell.toast?.message == "It is still running. Stop it first.")
        #expect(ProjectConflict(code: "not_archived", message: "") == .notArchived)
    }

    // F-16
    @Test func nonRunWritesUseTheGeneralWordsNotTheRunOnes() async {
        let (m, s, host) = await make()
        s.archiveError = CoreError.http(status: 409, code: "project_running", message: "")
        await m.archive(existing("tidepool", name: "Tidepool"))
        #expect(host.shell.toast?.message == "It is still running. Stop it first.")
    }

    @Test func unarchiveWaitsForACoreThatHasIt() async {
        let (m, s, host) = await make()
        await m.unarchive(existing("old", name: "Old"))
        #expect(host.reasons.isEmpty && s.calls.isEmpty)
        #expect(host.shell.toast?.message.contains("Update the Core") == true)
    }

    // F-17
    @Test func changingTheKindFromTheCardKeepsTheOtherKinds() async {
        let (m, s, _) = await make()
        m.core112 = true
        var p = existing("tidepool", name: "Tidepool")
        p.kinds = [.web, .app]
        s.seed(p)
        await m.reload()
        m.tapKind(.infra, for: p)
        #expect(await until { s.calls.contains("kinds web,app,infra") })
    }

    // F-27
    @Test func aWriteWhileAnotherIsBusyIsSaidNotDropped() async {
        let (m, s, host) = await make()
        m.busy = true
        await m.archive(existing("tidepool", name: "Tidepool"))
        #expect(host.shell.toast?.message.hasPrefix("Still saving") == true)
        #expect(s.calls.isEmpty)
        host.shell.toast = nil
        #expect(await m.change(existing("tidepool", name: "Tidepool"), ProjectPatch(runner: "auto"), why: "x") == false)
        #expect(host.shell.toast?.message.hasPrefix("Still saving") == true)
    }
}

@MainActor
struct ColourMigrationTests {
    // F-26
    @Test func aPlainReloadNeverAsksForTouchIDToMigrateColours() async {
        let (m, s, host) = await make()
        m.core110 = true
        var p = existing("tidepool", name: "Tidepool")
        p.colourName = nil
        s.seed(p)
        m.colours.set(.teal, for: "tidepool")
        await m.reload()
        try? await Task.sleep(for: .milliseconds(150))  // let any stray task run
        #expect(host.reasons.isEmpty)
    }

    @Test func aWriteTheUserGaveTouchIDForCarriesTheColoursUp() async {
        let (m, s, host) = await make()
        m.core110 = true
        let p = existing("tidepool", name: "Tidepool")
        s.seed(p)
        m.colours.set(.teal, for: "tidepool")
        await m.reload()
        #expect(await m.change(p, ProjectPatch(runner: "auto"), why: "Change it."))
        #expect(host.reasons.contains { $0.hasPrefix("Save the colours") })
    }
}

struct WizardUITests {
    // U-25
    @Test func anOfflineRunnerIsNotOffered() {
        let off = [RunnerInfo(id: "h", name: "home", os: "linux", online: false)]
        #expect(WizardRunner.home_server.unavailable(kind: .web, runners: off, supported: true, appleCode: false) != nil)
        let on = [RunnerInfo(id: "h", name: "home", os: "linux", online: true)]
        #expect(WizardRunner.home_server.unavailable(kind: .web, runners: on, supported: true, appleCode: false) == nil)
    }

    // U-27
    @Test func theStepCountDoesNotShrinkOnceCodeIsPicked() {
        var d = WizardDraft(kind: .other)
        #expect(d.steps.count == 2)
        d.picked = ["https://github.com/o/r"]
        #expect(d.steps.count == 3)
    }
}
