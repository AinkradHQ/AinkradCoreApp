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
        #expect(p.title(name: "Atlas") == "Creating Atlas")
    }

    @Test func settlesWhenNothingIsCopying() {
        let bad = WizardProgress([repo(1, fetched: true), repo(2, error: "private", state: "failed")])
        #expect(bad.settled && bad.title(name: "Atlas") == "Almost there")
        let good = WizardProgress([repo(1, fetched: true)])
        #expect(good.settled && good.title(name: "Atlas") == "Your project is ready")
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
