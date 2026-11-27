import Foundation
import Testing

@testable import Projects

private func repo(_ id: Int64, fetched: Bool = false, error: String? = nil, state: String? = nil) -> RepoItem {
    RepoItem(
        id: id, name: "r\(id)", remoteURL: "https://github.com/o/r\(id)", branch: "main", primary: id == 1,
        fetchedAt: fetched ? Date() : nil, fetchError: error, state: state)
}

struct WizardProgressTests {
    @Test func countsEachRepoByItsCopyState() {
        let p = WizardProgress([repo(1, fetched: true), repo(2), repo(3, error: "no", state: "failed")])
        #expect((p.ready, p.copying, p.failed) == (1, 1, 1))
        #expect(!p.settled)
        #expect(p.title(name: "Atlas") == "Setting up Atlas")
    }

    @Test func settlesWhenNothingIsCopying() {
        let bad = WizardProgress([repo(1, fetched: true), repo(2, error: "private", state: "failed")])
        #expect(bad.settled && bad.title(name: "Atlas") == "Atlas is ready, 1 repo needs you")
        let good = WizardProgress([repo(1, fetched: true)])
        #expect(good.settled && good.title(name: "Atlas") == "Atlas is ready")
        // A project with no code is ready at once.
        #expect(WizardProgress([]).settled)
    }

    @Test func runnersAreTheValuesTheCoreKeeps() {
        #expect(WizardRunner.allCases.map(\.rawValue) == ["auto", "this_mac", "home_server"])
    }
}

@MainActor
struct WizardCreateTests {
    @Test func theWizardKeepsItsDialogAndAppliesThePublicLinkChoice() async {
        let m = ProjectsModel(host: FakeHost(), defaults: UserDefaults(suiteName: "wizard-tests-\(UUID())")!)
        let s = FakeService()
        m.use(s)
        _ = await until { m.load == .ready }
        let ok = await m.create(
            name: "Atlas", slug: "atlas", colour: .blue, repos: [], expose: false, runner: "this_mac", wizard: true)
        #expect(ok)
        #expect(m.wizardProjectID != nil)
        // The wizard decides when to open the project: creating alone leaves the gallery where it is.
        #expect(m.openID == nil)
        #expect(s.calls.contains("expose false"))
    }

    @Test func aPlainCreateStillOpensTheProject() async {
        let m = ProjectsModel(host: FakeHost(), defaults: UserDefaults(suiteName: "wizard-tests-\(UUID())")!)
        m.use(FakeService())
        _ = await until { m.load == .ready }
        _ = await m.create(name: "Atlas", slug: "atlas", colour: .blue)
        #expect(m.openID != nil && m.wizardProjectID == nil)
    }
}

struct WizardHeaderTests {
    /// A repo the Core did not add counts as needing the person, next to the ones that did not copy.
    @Test func countsEveryRequestedRepoInTheHeader() {
        let p = WizardProgress([repo(1, error: "no", state: "failed"), repo(2, fetched: true)])
        #expect(p.title(name: "Tidepool", missed: 1) == "Tidepool is ready, 2 repos need you")
        #expect(
            WizardProgress([repo(1, fetched: true)]).title(name: "Tidepool", missed: 2)
                == "Tidepool is ready, 2 repos need you")
    }
}

private func pick(_ name: String, _ language: String?) -> PickRepo {
    PickRepo(org: "o", name: name, url: "https://github.com/o/\(name)", language: language)
}

struct WizardDraftTests {
    @Test func threeStepsAndNotSoftwareSkipsCode() {
        var d = WizardDraft(name: "Atlas")
        #expect(d.steps == [.what, .code, .review])
        #expect(d.next(.what) == .code && d.previous(.review) == .code)
        d.pickKind(.other)
        #expect(d.steps == [.what, .review])
        #expect(d.next(.what) == .review && d.previous(.review) == .what)
        d.wantsCode = true
        #expect(d.steps == [.what, .code, .review])
    }

    @Test func aPresetKindIsTheOnePicked() {
        let d = WizardDraft(name: "", kind: .infra)
        #expect(d.kind == .infra && d.kindPicked)
    }

    @Test func nextSaysWhyItWaits() {
        var d = WizardDraft()
        #expect(d.whyNotNext == "Give it a name to continue.")
        d.name = "Atlas"
        #expect(d.whyNotNext == nil && d.nameReady)
    }

    @Test func reposCorrectTheKindWithOneLineAndUndoPutsItBack() {
        var d = WizardDraft(name: "Tidepool")
        let repos = [pick("tidepool-ios", "Swift")]
        d.follow(ProjectKind.suggest(from: repos), hasRepos: true)
        #expect(d.kind == .app)
        #expect(d.corrected?.line == "Looks like an App: Swift, iOS")
        d.undoCorrection()
        #expect(d.kind == .web && d.corrected == nil && d.kindPicked)
        // The person decided: the repos never change it again.
        d.follow(ProjectKind.suggest(from: repos), hasRepos: true)
        #expect(d.kind == .web)
    }

    @Test func aKindThePersonPickedIsNeverCorrected() {
        var d = WizardDraft(name: "Tidepool")
        d.pickKind(.web)
        d.follow(ProjectKind.suggest(from: [pick("tidepool-ios", "Swift")]), hasRepos: true)
        #expect(d.kind == .web && d.corrected == nil)
    }

    @Test func aGuessOrNoReposChangesNothing() {
        var d = WizardDraft(name: "Tidepool")
        d.follow(ProjectKind.suggest(from: []), hasRepos: false)
        #expect(d.kind == .web && d.corrected == nil)
        d.follow(ProjectKind.suggest(from: [pick("thing", "Zig")]), hasRepos: true)
        #expect(d.kind == .web && d.corrected == nil)
    }

    @Test func unpickingTheReposTakesTheCorrectionBack() {
        var d = WizardDraft(name: "Tidepool")
        d.follow(ProjectKind.suggest(from: [pick("tidepool-ios", "Swift")]), hasRepos: true)
        #expect(d.kind == .app)
        d.follow(ProjectKind.suggest(from: []), hasRepos: false)
        #expect(d.kind == .web && d.corrected == nil && !d.kindPicked)
    }

    @Test func documentsOnlyReadAsNotSoftware() {
        var d = WizardDraft(name: "Book")
        d.follow(ProjectKind.suggest(from: [pick("notes", "Markdown")]), hasRepos: true)
        #expect(d.kind == .other && d.corrected?.line == "Looks like a project that is not software: only documents")
    }

    @Test func everyKindHasOneRowPerChoiceWithUniqueIds() {
        for k in ProjectKind.allCases {
            var d = WizardDraft(name: "Atlas")
            d.pickKind(k)
            let ids = d.reviewItems(repoNames: ["a", "b"], brainOn: true).map(\.id)
            #expect(Set(ids).count == ids.count)
            #expect(ids.contains(.link) == k.hasPublicLink && ids.contains(.runs) == k.runs)
            #expect(ids.contains(.brain) && ids.contains(.code) && ids.contains(.kind))
        }
    }

    @Test func aRunnerThatCannotBeUsedSaysWhy() {
        let linux = [RunnerInfo(id: "r", name: "core-oracle", os: "linux", online: true)]
        #expect(WizardRunner.auto.unavailable(kind: .app, runners: linux, supported: false, appleCode: true) == nil)
        #expect(
            WizardRunner.home_server.unavailable(kind: .app, runners: linux, supported: true, appleCode: true)
                == "Apple apps are built on a Mac.")
        #expect(
            WizardRunner.this_mac.unavailable(kind: .web, runners: linux, supported: true, appleCode: false)
                == "No Mac runner is paired yet.")
        #expect(
            WizardRunner.home_server.unavailable(kind: .web, runners: linux, supported: false, appleCode: false)
                == "This Core keeps one place for now.")
        #expect(
            WizardRunner.home_server.unavailable(kind: .web, runners: linux, supported: true, appleCode: false) == nil)
    }
}

@MainActor
struct WizardDialogTests {
    private func model() -> ProjectsModel {
        ProjectsModel(host: FakeHost(), defaults: UserDefaults(suiteName: "wizard-tests-\(UUID())")!)
    }

    @Test func theDialogIsNotDismissedByTheShellAndAFreshOpenRestoresTheDraft() {
        let m = model()
        NewProjectDialogs.openWizard(m, name: "Atlas", kind: .infra)
        #expect(m.host.shell.dialog?.id == "project-new" && m.host.shell.dialog?.dismissible == false)
        var kept = WizardDraft(name: "Atlas", kind: .infra)
        kept.description = "kept"
        m.wizardDraft = kept
        m.host.shell.closeDialog()
        NewProjectDialogs.openWizard(m, name: "")
        #expect(m.wizardDraft?.description == "kept")
        // Anything preset starts a new one and forgets the old.
        NewProjectDialogs.openWizard(m, name: "Other")
        #expect(m.wizardDraft == nil && m.wizardProjectID == nil)
    }

    @Test func openingTheProjectForgetsTheDraft() async {
        let m = model()
        m.use(FakeService())
        _ = await until { m.load == .ready }
        m.wizardDraft = WizardDraft(name: "Atlas")
        _ = await m.create(name: "Atlas", slug: "atlas", colour: .blue, wizard: true)
        let id = m.wizardProjectID
        #expect(id != nil)
        m.openWizardProject()
        #expect(m.wizardDraft == nil && m.wizardProjectID == nil)
    }
}
