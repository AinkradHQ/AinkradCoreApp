import Foundation
import Testing

@testable import Projects

private func repo(_ name: String, _ lang: String?, _ blurb: String = "") -> PickRepo {
    PickRepo(org: "o", name: name, url: "https://github.com/o/\(name)", language: lang, blurb: blurb)
}

struct KindSuggestionTests {
    @Test func swiftAndXcodeAreAnApp() {
        let s = ProjectKind.suggest(from: [repo("tidepool-ios", "Swift", "An Xcode project for iPhone")])
        #expect(s.kind == .app)
        #expect(s.why == "Suggested from your repos: Swift, iOS, iPhone")
    }

    @Test func webFrameworksAreWeb() {
        #expect(ProjectKind.suggest(from: [repo("shop", "TypeScript", "A Next.js storefront")]).kind == .web)
        #expect(ProjectKind.suggest(from: [repo("site", "PHP", "Laravel")]).kind == .web)
    }

    @Test func terraformAndNixAreInfrastructure() {
        #expect(ProjectKind.suggest(from: [repo("net", "HCL")]).kind == .infra)
        #expect(ProjectKind.suggest(from: [repo("os", "Nix")]).kind == .infra)
        #expect(ProjectKind.suggest(from: [repo("deploy", "Go", "Helm charts for the cluster")]).kind == .infra)
    }

    @Test func noCodeOrOnlyDocumentsIsNotSoftware() {
        #expect(ProjectKind.suggest(from: []).kind == .other)
        #expect(ProjectKind.suggest(from: [repo("notes", "Markdown")]).kind == .other)
        #expect(ProjectKind.suggest(from: [repo("book", nil)]).kind == .other)
    }

    @Test func docsBesideCodeDoNotChangeTheAnswer() {
        #expect(ProjectKind.suggest(from: [repo("docs", "Markdown"), repo("app", "Kotlin")]).kind == .app)
    }

    @Test func aTieGoesToTheAppAndNothingClearSaysItIsAGuess() {
        #expect(ProjectKind.suggest(from: [repo("a", "Swift"), repo("b", "HCL")]).kind == .app)
        let s = ProjectKind.suggest(from: [repo("tool", "Rust")])
        #expect(s.kind == .web && s.why.contains("guess"))
    }

    @Test func platformsComeFromTheRepoNames() {
        func r(_ n: String) -> RepoItem {
            RepoItem(id: 1, name: n, remoteURL: "u", branch: "main", primary: true, fetchedAt: nil, fetchError: nil)
        }
        #expect(ProjectKind.platforms([r("tidepool-ios"), r("tidepool-android")]) == ["iOS", "Android"])
        #expect(ProjectKind.platforms([r("tidepool")]).isEmpty)
    }

    @Test func theKindsHaveTheCoresNames() {
        #expect(ProjectKind.allCases.map(\.rawValue) == ["web", "app", "infra", "other"])
        #expect(ProjectKind.other.runs == false && ProjectKind.web.hasPublicLink && !ProjectKind.app.hasPublicLink)
    }
}

@MainActor
struct KindModelTests {
    private func model() async -> ProjectsModel {
        let m = ProjectsModel(host: FakeHost(), defaults: UserDefaults(suiteName: "kind-tests-\(UUID())")!)
        m.use(FakeService())
        _ = await until { m.load == .ready }
        return m
    }

    @Test func aCreateKeepsTheKindOnThisMacAndShowsIt() async throws {
        let m = await model()
        _ = await m.create(name: "Atlas", slug: "atlas", colour: .blue, kind: .infra)
        let p = try #require(m.projects.first)
        #expect(p.kind == .infra)
    }

    @Test func anOlderCoreKeepsAChangedKindOnThisMac() async throws {
        let m = await model()
        _ = await m.create(name: "Atlas", slug: "atlas", colour: .blue)
        var p = try #require(m.projects.first)
        #expect(p.kind == .web)
        m.setKind(.other, for: p)
        p = try #require(m.projects.first)
        #expect(p.kind == .other)
    }

    @Test func theCoresKindWinsOverThisMacs() async throws {
        let m = await model()
        _ = await m.create(name: "Atlas", slug: "atlas", colour: .blue, kind: .app)
        var p = try #require(m.projects.first)
        p.kindName = "infra"
        #expect(m.kind(p) == .infra)
    }
}

struct KindWireTests {
    private let project = """
        {"id":7,"slug":"tidepool","name":"Tidepool","description":"","state":"active","expose":false,"color":"teal","kind":"app",
         "cpu_limit":2.0,"mem_limit_mb":2048,"idle_minutes":30,"fetch_interval_minutes":15,"runner":"auto",
         "source":"manual","created_at":"2026-11-20T10:00:00.000Z","updated_at":"2026-11-27T10:00:00.000Z","repos":[]}
        """

    @Test func aProjectCarriesItsKind() throws {
        #expect(try LiveProjectsService.decode(Data(project.utf8)).first?.kindName == "app")
        let old = project.replacingOccurrences(of: ",\"kind\":\"app\"", with: "")
        #expect(try LiveProjectsService.decode(Data(old.utf8)).first?.kindName == nil)
    }

    @Test func aPatchSendsTheKind() throws {
        let body = try LiveProjectsService.patchBody(ProjectPatch(kind: "other"))
        let o = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(o["kind"] as? String == "other" && o["color"] == nil)
    }
}

@MainActor
struct NoRepoSessionTests {
    private func model(core111: Bool) async -> (ProjectsModel, ProjectItem) {
        let m = ProjectsModel(host: FakeHost(), defaults: UserDefaults(suiteName: "kind-sess-\(UUID())")!)
        m.use(FakeService())
        _ = await until { m.load == .ready }
        m.sessionStarter = { _, _ in nil }
        m.core111 = core111
        let p = ProjectItem(
            id: 1, slug: "book", name: "Book", description: "", expose: false, repos: [], updatedAt: Date())
        return (m, p)
    }

    @Test func aProjectWithNoReposNeedsACoreThatAllowsIt() async {
        let (old, p) = await model(core111: false)
        #expect(!old.canStartSession(p) && old.sessionBlock(p).contains("repo"))
        let (new, q) = await model(core111: true)
        #expect(new.canStartSession(q) && new.sessionBlock(q).contains("own folder"))
    }

    @Test func anArchivedProjectStillCannot() async {
        var (m, p) = await model(core111: true)
        p.archived = true
        #expect(!m.canStartSession(p))
    }
}
