import Admin
import CoreKit
import Foundation
import Shell
import Testing

@testable import Projects

// Lane P2 of the Projects audit: create, settings, repos and the gallery's actions.

struct LinkRulesTests {
    @Test func namesThatAreNotLatinOrStartWithADigitStillMakeALink() {
        #expect(ProjectRules.slug(from: "2048 game") == "project-2048-game")
        #expect(ProjectRules.slugProblem(ProjectRules.slug(from: "2048 game")) == nil)
        #expect(ProjectRules.slug(from: "東京 Lab") == "dong-jing-lab")
        #expect(ProjectRules.slug(from: "Café Münster") == "cafe-munster")
        // Nothing usable in the name, one letter, a reserved word: all end in a link the Core takes.
        #expect(ProjectRules.slug(from: "🚀") == "project")
        #expect(ProjectRules.slug(from: "A") == "a-project")
        #expect(ProjectRules.slug(from: "Docs") == "docs-project")
        #expect(ProjectRules.slug(from: "   ") == "")
        for n in ["2048 game", "東京", "🚀", "A", "Docs", "x"] {
            #expect(ProjectRules.slugProblem(ProjectRules.slug(from: n)) == nil)
        }
    }

    @Test func theCoresLinkRulesAreSaidInWords() {
        #expect(ProjectRules.slugProblem("docs")?.contains("reserved") == true)
        #expect(ProjectRules.slugProblem("tide-") == "The link can’t end with a dash.")
        #expect(ProjectRules.suffixed("tidepool", 2) == "tidepool-2")
        #expect(ProjectRules.suffixed(String(repeating: "a", count: 40), 12).count == 40)
    }

    @Test func repoLinksAreHttpsOnlyAndRefusedInWords() {
        #expect(ProjectRules.repoLinkProblem("https://github.com/o/r") == nil)
        #expect(ProjectRules.repoLinkProblem("git@github.com:o/r.git")?.contains("SSH") == true)
        #expect(ProjectRules.repoLinkProblem("ssh://git@github.com/o/r")?.contains("SSH") == true)
        #expect(ProjectRules.repoLinkProblem("http://github.com/o/r")?.contains("https") == true)
        #expect(ProjectRules.repoLinkProblem("https://u:p@github.com/o/r")?.contains("password") == true)
        #expect(ProjectRules.repoLinkProblem("https://github.com/o/r?x=1") != nil)
        #expect(ProjectRules.repoLinkProblem("https://github.com/") != nil)
        #expect(ProjectRules.repoLinkProblem("tidepool") != nil)
        #expect(ProjectRules.looksLikeLink("git@github.com:o/r") && !ProjectRules.looksLikeLink("tidepool"))
    }

    @Test func theSameRepoIsOneHoweverItIsTyped() {
        #expect(ProjectRules.same("https://GitHub.com/o/r.git/", "https://github.com/o/r"))
        #expect(ProjectRules.same("git@github.com:o/r.git", "https://github.com/o/r"))
        #expect(!ProjectRules.same("https://github.com/o/r", "https://github.com/o/r2"))
    }
}

struct WordsTests {
    @Test func everyConflictHasItsOwnCause() {
        func c(_ m: String, _ code: String = "conflict") -> ProjectConflict { ProjectConflict(code: code, message: m) }
        #expect(c("a project of that slug exists") == .slugTaken)
        #expect(c("the project is archived") == .archived)
        #expect(c("the project has a repo of that name or remote") == .repoExists)
        #expect(c("the project is not archived") == .notArchived)
        #expect(c("the link name is taken, or the project is running or holds secrets") == .linkLocked)
        #expect(c("set another repo primary before removing this one") == .primaryRepo)
        #expect(c("no GitHub connection is set up: connect GitHub first", "no_connection") == .noConnection)
        #expect(c("that connection is disabled") == .connectionOff)
        let all = [
            ProjectConflict.slugTaken, .archived, .repoExists, .linkLocked, .primaryRepo, .noConnection, .connectionOff,
            .notArchived,
        ]
        #expect(Set(all.map(\.words)).count == all.count)
    }

    @Test func githubFailuresAreToldPerCause() {
        #expect(CatalogProblem(CoreError.http(status: 409, code: "no_connection", message: "")) == .noConnection)
        #expect(CatalogProblem(CoreError.http(status: 502, code: "auth_failed", message: "")) == .authFailed)
        #expect(CatalogProblem(CoreError.http(status: 502, code: "unreachable", message: "")) == .unreachable)
        #expect(CatalogProblem(CoreError.http(status: 429, code: "rate_limited", message: "")) == .rateLimited)
        #expect(CatalogProblem.authFailed.needsConnection && !CatalogProblem.unreachable.needsConnection)
        #expect(CatalogProblem.rateLimited.words != CatalogProblem.unreachable.words)
    }
}

struct WireTests {
    // The shapes of `api/openapi.json` (Core API 1.109): a project with a mirror, one without, GitHub-made.
    private let json = Data(
        """
        [{"id":7,"slug":"tidepool","name":"Tidepool","description":"Tide data","state":"active","source":"github",
          "expose":true,"idle_minutes":45,"idle_never":true,"cpu_limit":4.0,"mem_limit_mb":8192,"runner":"home_server",
          "fetch_interval_minutes":15,"default_environment":null,
          "created_at":"2026-11-12T09:30:00.250Z","updated_at":"2026-11-27T10:00:00.000Z",
          "room":{"room_id":"room_a","name":"Tidepool"},
          "repos":[{"id":1,"name":"api","remote_url":"https://github.com/tidepool-labs/api.git","default_branch":"develop","is_primary":true,
                    "mirror":{"state":"failed","reason":"needs_github","error":"private","head":null,"fetched_at":null,"started_at":null}},
                   {"id":2,"name":"web","remote_url":"https://github.com/tidepool-labs/web.git","default_branch":"main","is_primary":false}]}]
        """.utf8)

    @Test func aProjectKeepsItsRunnerLimitsSourceAndDate() throws {
        let p = try #require(try LiveProjectsService.decode(json).first)
        #expect(p.runner == "home_server" && p.source == "github" && p.idleNever && p.idleMinutes == 45)
        #expect(p.cpuLimit == 4 && p.memLimitMb == 8192 && p.createdAt != nil)
        #expect(p.limits == ProjectLimits(cpus: 4, memoryMb: 8192, idleMinutes: 45, idleNever: true))
    }

    @Test func theCoresDefaultBranchIsKeptAndAMissingMirrorIsUnknown() throws {
        let p = try #require(try LiveProjectsService.decode(json).first)
        #expect(p.repos[0].branch == "develop" && p.repos[0].copy == .failed(.needsGithub, "private"))
        #expect(p.repos[1].hasMirror == false && p.repos[1].copy == .unknown)
        #expect(p.copyFailed == false)
    }

    @Test func aListOfGithubReposCarriesBranchPrivacyAndTruncation() throws {
        let page = try LiveRepoCatalog.decode(
            Data(
                """
                {"connection_id":3,"total":2,"page":1,"per_page":30,"has_more":true,"truncated":true,
                 "owners":[{"owner":"tidepool-labs","repos":[
                   {"name":"api","full_name":"tidepool-labs/api","default_branch":"develop","private":true,"description":"The API"},
                   {"name":"web","full_name":"tidepool-labs/web","default_branch":"main","private":false,"description":""}]}]}
                """.utf8))
        #expect(page.hasMore && page.truncated && page.repos.count == 2)
        #expect(
            page.repos[0].defaultBranch == "develop" && page.repos[0].isPrivate
                && page.repos[0].fullName == "tidepool-labs/api")
        #expect(page.repos[0].url == "https://github.com/tidepool-labs/api")
        #expect(page.repos[0].detail(now: Date()) == "Private · The API")
    }
}

@MainActor
private func make(runner: Bool = true) async -> (ProjectsModel, FakeService, FakeHost) {
    let host = FakeHost()
    let m = ProjectsModel(host: host, defaults: UserDefaults(suiteName: "p2-tests-\(UUID())")!)
    m.runnerSupported = runner
    let s = FakeService()
    m.use(s)
    _ = await until { m.load == .ready }
    return (m, s, host)
}

private func link(_ name: String) -> PickRepo {
    PickRepo(org: "o", name: name, url: "https://github.com/o/\(name)")
}

private func gh(_ name: String, branch: String = "develop") -> PickRepo {
    PickRepo(
        org: "o", name: name, url: "https://github.com/o/\(name)", fullName: "o/\(name)", defaultBranch: branch)
}

@MainActor
struct CreateTests {
    @Test func githubReposGoThroughFromGithubSoTheCoreReadsTheRealBranch() async {
        let (m, s, _) = await make()
        _ = await m.create(name: "Atlas", slug: "atlas", colour: .blue, repos: [gh("api"), gh("web", branch: "trunk")])
        #expect(s.calls.contains("github o/api,o/web") && s.branches.isEmpty)
    }

    @Test func aPastedSshLinkIsRefusedInWordsBeforeTouchId() async {
        let (m, s, host) = await make()
        let ssh = PickRepo(org: "Pasted links", name: "r", url: "git@github.com:o/r.git")
        let ok = await m.create(name: "Atlas", slug: "atlas", colour: .blue, repos: [ssh])
        #expect(!ok && host.reasons.isEmpty && s.calls.isEmpty)
        #expect(m.writeError?.contains("SSH") == true)
    }

    @Test func reposTheCoreRefusesAreListedWithTheirReason() async {
        let (m, s, _) = await make()
        s.refuseRepo = "web"
        let pasted = [
            PickRepo(org: "p", name: "api", url: "https://example.com/o/api"),
            PickRepo(org: "p", name: "web", url: "https://example.com/o/web"),
        ]
        _ = await m.create(name: "Atlas", slug: "atlas", colour: .blue, repos: pasted, wizard: true)
        #expect(m.wizardMissed.map(\.name) == ["web"] && !m.wizardMissed[0].why.isEmpty)
    }

    @Test func aTakenLinkMadeFromTheNameGetsANumberAndAnExplicitOneIsAnError() async {
        let (m, s, _) = await make()
        s.takenSlugs = ["atlas"]
        let ok = await m.create(name: "Atlas", slug: "atlas", colour: .blue, autoSuffix: true, wizard: true)
        #expect(ok && s.calls.contains("create atlas-2"))
        #expect(m.wizardIssues.contains { $0.contains("atlas-2") })
        let (m2, s2, _) = await make()
        s2.takenSlugs = ["atlas"]
        let bad = await m2.create(name: "Atlas", slug: "atlas", colour: .blue)
        #expect(!bad && m2.writeError == "That link name is taken. Pick another.")
    }

    @Test func aPublicLinkOrRunnerTheCoreRefusesIsToldNotDropped() async {
        let (m, s, _) = await make()
        s.refusePatch = CoreError.http(
            status: 400, code: "bad_request", message: "the runner is auto, this_mac or home_server")
        let ok = await m.create(
            name: "Atlas", slug: "atlas", colour: .blue, expose: true, runner: "this_mac", wizard: true)
        #expect(ok && m.wizardIssues.contains { $0.contains("public link") && $0.contains("runner is auto") })
    }

    @Test func aPickedGithubRepoNeedsNoLinkCheck() async {
        let (m, _, host) = await make()
        let ok = await m.create(name: "Atlas", slug: "atlas", colour: .blue, repos: [gh("api")])
        #expect(ok && host.reasons.count == 1)
    }
}

@MainActor
struct SettingsTests {
    private func open(_ m: ProjectsModel, _ s: FakeService) async -> ProjectItem {
        _ = await m.create(
            name: "Atlas", slug: "atlas", colour: .blue, repos: [link("api"), link("web")], wizard: true)
        return m.projects[0]
    }

    @Test func theRunnerAndEachLimitAreSavedOnTheProject() async {
        let (m, s, _) = await make()
        let p = await open(m, s)
        await m.setRunner(p, "this_mac")
        var l = p.limits
        l.cpus = 4
        l.memoryMb = 8192
        await m.setLimits(p, l)
        #expect(s.calls.contains("runner this_mac") && s.calls.contains("limits 4.0 8192 0 -"))
        await m.setLimits(p, ProjectsOptions.setIdle(p.limits, minutes: 0))
        #expect(s.calls.last == "limits 0.0 0 0 true")
    }

    @Test func aRefusedWriteMarksTheDeviceReadOnlyOnEveryPath() async {
        let (m, s, _) = await make()
        let p = await open(m, s)
        s.refusePatch = CoreError.forbiddenScope
        await m.setExpose(p, true)
        #expect(m.readOnly)
        m.readOnly = false
        await m.setRunner(p, "home_server")
        #expect(m.readOnly)
    }

    @Test func theLinkNameChangeCarriesTheColourToTheNewName() async {
        let (m, s, _) = await make()
        let p = await open(m, s)
        m.setColour(.blue, for: p)
        _ = await m.saveGeneral(p, name: "Atlas", description: "", slug: "atlas-two")
        #expect(s.calls.contains("slug atlas-two"))
        #expect(m.colours.colour("atlas-two") == .blue)
        #expect(await m.saveGeneral(p, name: "Atlas", description: "", slug: "docs") == false)
        #expect(m.writeError?.contains("reserved") == true)
    }

    @Test func repoRemovalAndPrimaryGoToTheCore() async {
        let (m, s, _) = await make()
        let p = await open(m, s)
        await m.makePrimary(p, p.repos[1])
        await m.removeRepo(p, p.repos[1])
        #expect(s.calls.contains("primary 2") && s.calls.contains("remove 2"))
    }

    @Test func addingReposLeavesOutTheOnesTheProjectHas() async {
        let (m, s, _) = await make()
        let p = await open(m, s)
        let before = s.calls.count
        let ok = await m.addRepos(to: p, [gh("api"), gh("docs")])
        #expect(ok && s.calls.count > before && s.branches.suffix(1) == ["docs develop"] && s.branches.count == 3)
        #expect(await m.addRepos(to: p, [gh("api")]) == false)
    }
}

@MainActor
struct GalleryTests {
    @Test func aFailedRefreshKeepsTheListAndSaysSoUntilItWorksAgain() async {
        let (m, s, _) = await make()
        _ = await m.create(name: "Atlas", slug: "atlas", colour: .blue)
        s.failList = CoreError.offline("timeout")
        await m.reload()
        #expect(m.stale != nil && m.projects.count == 1 && m.load == .ready)
        #expect(m.newProjectBlock != nil)
        s.failList = nil
        await m.reload()
        #expect(m.stale == nil && m.newProjectBlock == nil)
    }

    @Test func newProjectSaysWhyItIsOff() async {
        let (m, _, _) = await make()
        m.readOnly = true
        #expect(m.newProjectBlock?.contains("look at projects") == true)
        m.detach()
        #expect(m.newProjectBlock?.contains("Connect this Mac") == true)
    }

    @Test func startSaysWhyItCannotAndStartsOtherwise() async {
        let (m, s, _) = await make()
        _ = await m.create(name: "Atlas", slug: "atlas", colour: .blue)
        #expect(m.startBlock(m.projects[0]) == "Add a repo first.")
        _ = await m.create(name: "Beta", slug: "beta", colour: .blue, repos: [link("api")])
        let p = m.projects.first { $0.slug == "beta" }!
        #expect(m.startBlock(p) == nil)
        await m.runControl(.start, p)
        #expect(s.calls.contains("run start"))
        var archived = p
        archived.archived = true
        #expect(m.startBlock(archived) == "Unarchive it first.")
    }

    @Test func aFirstCopyThatFailedSaysFailedNotSettingUp() {
        var p = ProjectItem(id: 1, slug: "a", name: "A", description: "", expose: true, repos: [], updatedAt: Date())
        p.repos = [
            RepoItem(
                id: 1, name: "r", remoteURL: "https://x/r", branch: "main", primary: true, fetchedAt: nil,
                fetchError: "no",
                state: "failed", reason: "timeout")
        ]
        #expect(p.tag == .settingUp && p.copyFailed)
        #expect(p.badge.label == "Can’t copy" && p.subtitle == "Couldn’t copy 1 repo")
        p.repos[0] = RepoItem(
            id: 1, name: "r", remoteURL: "https://x/r", branch: "main", primary: true, fetchedAt: nil, fetchError: nil,
            state: "fetching")
        #expect(p.badge.label == "Setting up")
    }
}

@MainActor
struct CopyingTests {
    private func repo(_ id: Int64, state: String?, mirror: Bool = true) -> RepoItem {
        RepoItem(
            id: id, name: "r\(id)", remoteURL: "https://x/r\(id)", branch: "main", primary: id == 1,
            fetchedAt: state == "ready" ? Date() : nil,
            fetchError: nil, state: state, hasMirror: mirror)
    }

    @Test func backoffGrowsAndStopsGrowing() {
        let secs = (0..<9).map { ProjectsModel.backoff($0) }
        #expect(secs.first == .seconds(3) && secs[5] == .seconds(20) && secs[8] == .seconds(30))
        #expect(zip(secs, secs.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func onlyProjectsThatAreCopyingAreReadAgain() async {
        let (m, s, _) = await make()
        _ = await m.create(name: "A", slug: "aa", colour: .blue, repos: [link("a")])
        _ = await m.create(name: "B", slug: "bb", colour: .blue, repos: [gh("b")])
        s.setRepos(1, [repo(1, state: "fetching")])
        s.setRepos(2, [repo(2, state: "ready")])
        await m.reload()
        let reads = s.listReads
        #expect(m.copyingProjects() == [1])
        await m.refreshCopying([1])
        #expect(s.projectReads == 1 && s.listReads == reads)
    }

    @Test func aRepoTheCoreNeverStartedIsWaitedForAFewReadsThenLeftAlone() async {
        let (m, s, _) = await make()
        _ = await m.create(name: "A", slug: "aa", colour: .blue, repos: [link("a")])
        s.setRepos(1, [repo(1, state: nil, mirror: false)])
        await m.reload()
        #expect(m.projects[0].repos[0].copy == .unknown)
        m.pollAttempt = 0
        #expect(m.copyingProjects() == [1])
        m.pollAttempt = 4
        #expect(m.copyingProjects().isEmpty)
    }

    @Test func fetchAllIsOneReadAndSaysHowItEnded() async {
        let (m, s, host) = await make()
        _ = await m.create(name: "A", slug: "aa", colour: .blue, repos: [link("a"), link("b"), link("c")])
        let p = m.projects[0]
        let reads = s.listReads
        await m.fetch(p.repos, in: p)
        #expect(s.calls.filter { $0.hasPrefix("fetch") }.count == 3 && s.listReads == reads + 1)
        #expect(m.fetching.isEmpty && host.shell.toast?.message.contains("3 repos") == true)
    }

    @Test func aFetchTheCoreRefusesIsToldWithTheRepoName() async {
        let (m, s, host) = await make()
        _ = await m.create(name: "A", slug: "aa", colour: .blue, repos: [link("a")])
        s.fetchError = CoreError.http(status: 409, code: "conflict", message: "the project is archived")
        let p = m.projects[0]
        await m.fetch(p.repos, in: p)
        #expect(host.shell.toast?.message.contains("a (This project is archived") == true)
    }
}

private struct PagedCatalog: RepoCatalog {
    func page(query: String, page: Int) async throws -> RepoPage? {
        let names = query.isEmpty ? (page == 1 ? ["a", "b"] : ["c"]) : ["\(query)-hit"]
        return RepoPage(repos: names.map { gh($0) }, hasMore: query.isEmpty && page == 1, truncated: query.isEmpty)
    }
}

private struct BrokenCatalog: RepoCatalog {
    let error: any Error
    func page(query: String, page: Int) async throws -> RepoPage? { throw error }
}

@MainActor
struct CatalogTests {
    @Test func theFirstPageShowsAtOnceAndMoreIsAskedFor() async {
        let (m, _, _) = await make()
        m.catalog = PagedCatalog()
        await m.loadCatalog()
        #expect(m.catalogHasMore && m.catalogTruncated)
        await m.moreCatalog()
        guard case .ready(let all) = m.catalogState else {
            Issue.record("not ready")
            return
        }
        #expect(all.map(\.name) == ["a", "b", "c"] && !m.catalogHasMore)
    }

    @Test func aSearchAsksTheCoreAndAPickSurvivesIt() async {
        let (m, _, _) = await make()
        m.catalog = PagedCatalog()
        await m.loadCatalog()
        await m.searchCatalog("zed")
        guard case .ready(let hits) = m.catalogState else {
            Issue.record("not ready")
            return
        }
        #expect(hits.map(\.name) == ["zed-hit"])
        // "a" was picked before the search; it is still a repo the wizard can create with.
        #expect(m.chosen([gh("a").id, gh("zed-hit").id], pasted: []).map(\.name) == ["a", "zed-hit"])
    }

    @Test func githubErrorsAreWordedPerCause() async {
        let (m, _, _) = await make()
        m.catalog = BrokenCatalog(error: CoreError.http(status: 502, code: "unreachable", message: ""))
        await m.loadCatalog()
        #expect(m.catalogState == .failed(.unreachable))
        m.catalog = BrokenCatalog(error: CoreError.http(status: 409, code: "no_connection", message: ""))
        await m.loadCatalog()
        #expect(m.catalogState == .failed(.noConnection) || m.catalogState == .unavailable)
    }
}

struct WizardChoiceTests {
    @Test func theRunnerLineSaysWhatTheCoreHas() {
        let rs = [
            RunnerInfo(id: "d1", name: "Studio", os: "macos", online: true),
            RunnerInfo(id: "d2", name: "srv", os: "linux", online: false),
        ]
        #expect(WizardRunner.this_mac.line(rs).contains("Studio is online"))
        #expect(WizardRunner.home_server.line(rs).contains("srv is offline"))
        #expect(WizardRunner.home_server.line([rs[0]]).contains("No Linux runner"))
        #expect(WizardRunner.auto.line(rs) == WizardRunner.auto.line)
    }

    @Test func aRepoWithNoCopyIsNotCopying() {
        let p = WizardProgress([
            RepoItem(
                id: 1, name: "r", remoteURL: "x", branch: "main", primary: true, fetchedAt: nil, fetchError: nil,
                hasMirror: false)
        ])
        #expect(p.settled && p.waiting == 1 && p.title(name: "A") == "A is ready, 1 repo needs you")
    }
}
