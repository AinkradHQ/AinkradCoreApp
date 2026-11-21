import Admin
import Brain
import Foundation
import Shell
import Testing

@testable import Projects

@MainActor
final class FakeHost: AdminHost {
    func open(_ url: URL) {}  // never a real browser in a test
    let shell = ShellModel()
    var pausedReason: String?
    var elevationNotice: AdminNotice?
    var declines = false
    var reasons: [String] = []
    func clearElevationNotice() { elevationNotice = nil }
    func elevated<T>(_ reason: String, done: String, keepsEdit: Bool, _ op: () async throws -> T) async throws -> T {
        reasons.append(reason)
        if declines { throw AdminDeclined() }
        return try await op()
    }
    func rateLimited(retryAfter: TimeInterval?) {}
}

/// An in-memory Core: records what the model asked, can refuse a link or one repo.
final class FakeService: ProjectsService, @unchecked Sendable {
    private let lock = NSLock()
    private var list: [ProjectItem] = []
    private(set) var calls: [String] = []
    var refuseSlug: String?
    var refuseRepo: String?
    func projects() async throws -> [ProjectItem] { lock.withLock { list } }
    func create(slug: String, name: String) async throws -> ProjectItem {
        try lock.withLock {
            calls.append("create \(slug)")
            if slug == refuseSlug { throw CocoaError(.fileWriteFileExists) }
            let p = ProjectItem(
                id: Int64(list.count + 1), slug: slug, name: name, description: "", expose: true, repos: [],
                updatedAt: Date())
            list.append(p)
            return p
        }
    }
    func addRepo(project: Int64, name: String, url: String, primary: Bool) async throws {
        try lock.withLock {
            calls.append("repo \(name) primary=\(primary)")
            if name == refuseRepo { throw CocoaError(.fileWriteFileExists) }
            let i = list.firstIndex { $0.id == project }!
            list[i].repos.append(
                RepoItem(
                    id: Int64(list[i].repos.count + 1), name: name, remoteURL: url, branch: "main", primary: primary,
                    fetchedAt: nil, fetchError: nil))
        }
    }
    func setExpose(project: Int64, _ on: Bool) async throws { lock.withLock { calls.append("expose \(on)") } }
    var runState: ProjectRunState?
    func update(project: Int64, name: String, description: String) async throws {
        lock.withLock {
            calls.append("update \(name) | \(description)")
            if let i = list.firstIndex(where: { $0.id == project }) {
                list[i].name = name
                list[i].description = description
            }
        }
    }
    func archive(project: Int64) async throws {
        lock.withLock {
            calls.append("archive")
            list.removeAll { $0.id == project }
        }
    }
    func run(project: Int64) async throws -> ProjectRunState? { lock.withLock { runState } }
    func control(project: Int64, _ action: RunAction) async throws -> ProjectRunState {
        lock.withLock {
            calls.append("run \(action)")
            let state: RunSummary.State = action == .stop ? .stopped : .starting
            runState = ProjectRunState(summary: RunSummary(state: state), startedAt: Date())
            return runState!
        }
    }
}

private func pick(_ name: String) -> PickRepo {
    PickRepo(org: "o", name: name, url: "https://github.com/o/\(name)")
}

@MainActor
private func make(_ host: FakeHost = FakeHost()) async -> (ProjectsModel, FakeService, FakeHost) {
    let m = ProjectsModel(host: host, defaults: UserDefaults(suiteName: "projects-tests-\(UUID())")!)
    let s = FakeService()
    m.use(s)
    _ = await until { m.load == .ready }
    return (m, s, host)
}

struct RulesTests {
    @Test func slugFollowsTheName() {
        #expect(ProjectRules.slug(from: "Tidepool") == "tidepool")
        #expect(ProjectRules.slug(from: "  Northwind  Ledger! ") == "northwind-ledger")
        #expect(ProjectRules.slug(from: String(repeating: "a", count: 60)).count == 40)
    }

    @Test func slugProblemsAreSaidInWords() {
        #expect(ProjectRules.slugProblem("tidepool") == nil)
        #expect(ProjectRules.slugProblem("a") != nil)
        #expect(ProjectRules.slugProblem("7-seas") == "The link has to start with a letter.")
        #expect(ProjectRules.slugProblem("Tide") != nil)
        #expect(ProjectRules.slugProblem(String(repeating: "a", count: 41)) != nil)
        #expect(ProjectRules.nameProblem("   ") != nil)
        #expect(ProjectRules.nameProblem("Tidepool") == nil)
    }

    @Test func repoLinks() {
        #expect(
            ProjectRules.repo(fromLink: "https://github.com/tidepool-labs/tidepool-api.git")?.name == "tidepool-api")
        #expect(ProjectRules.repo(fromLink: "ssh://git@host/x/y.git")?.name == "y")
        // A password in the link never leaves this Mac; neither does anything that is not a link.
        #expect(ProjectRules.repo(fromLink: "https://user:secret@github.com/x/y") == nil)
        #expect(ProjectRules.repo(fromLink: "tidepool") == nil)
        #expect(ProjectRules.repo(fromLink: "https://github.com/x/y z") == nil)
    }

    @Test func tagsAndSubtitles() {
        let now = Date()
        func repo(_ fetched: Bool) -> RepoItem {
            RepoItem(
                id: 1, name: "a", remoteURL: "https://x/a", branch: "main", primary: true,
                fetchedAt: fetched ? now : nil, fetchError: nil)
        }
        var p = ProjectItem(id: 1, slug: "demo", name: "Demo", description: "", expose: true, repos: [], updatedAt: now)
        #expect(p.tag == .new)
        #expect(p.subtitle == "New · no repos yet")
        p.repos = [repo(false)]
        #expect(p.tag == .settingUp)
        p.repos = [repo(true), repo(true)]
        #expect(p.tag == .stopped)
        #expect(p.subtitle == "Stopped · 2 repos")
        p.run = RunSummary(state: .running, services: 5, sessions: 2)
        #expect(p.subtitle == "Running · 5 services · 2 AI sessions")
        p.run = RunSummary(state: .failed, lastRun: "20 min ago")
        #expect(p.tag == .failed)
        #expect(p.subtitle == "Last run failed 20 min ago")
    }
}

@MainActor
struct ModelTests {
    @Test func creatingAddsTheReposBehindOneTouchID() async {
        let (m, s, host) = await make()
        let ok = await m.create(
            name: "Tidepool", slug: "tidepool", colour: .teal, repos: [pick("tidepool-api"), pick("tidepool-web")])
        #expect(ok)
        #expect(host.reasons.count == 1)
        #expect(s.calls == ["create tidepool", "repo tidepool-api primary=true", "repo tidepool-web primary=false"])
        #expect(m.openID == m.projects.first?.id)
        #expect(m.colour(m.projects[0]) == .teal)
        #expect(m.projects[0].repos.count == 2)
    }

    @Test func aTakenLinkKeepsTheSheetOpenWithWords() async {
        let (m, s, _) = await make()
        s.refuseSlug = "tidepool"
        let ok = await m.create(name: "Tidepool", slug: "tidepool", colour: .blue)
        #expect(!ok)
        #expect(m.writeError != nil)
        #expect(m.openID == nil)
        #expect(m.projects.isEmpty)
    }

    @Test func aBadLinkNameIsStoppedBeforeTouchID() async {
        let (m, s, host) = await make()
        let ok = await m.create(name: "7 seas", slug: "7-seas", colour: .blue)
        #expect(!ok)
        #expect(host.reasons.isEmpty)
        #expect(s.calls.isEmpty)
        #expect(m.writeError == "The link has to start with a letter.")
    }

    @Test func aDeclinedTouchIDCreatesNothing() async {
        let host = FakeHost()
        host.declines = true
        let (m, s, _) = await make(host)
        #expect(await m.create(name: "Tidepool", slug: "tidepool", colour: .blue) == false)
        #expect(s.calls.isEmpty)
        #expect(m.writeError == nil)
    }

    @Test func oneRepoThatFailsDoesNotUndoTheProject() async {
        let (m, s, host) = await make()
        s.refuseRepo = "tidepool-web"
        let ok = await m.create(
            name: "Tidepool", slug: "tidepool", colour: .blue, repos: [pick("tidepool-api"), pick("tidepool-web")])
        #expect(ok)
        #expect(m.projects[0].repos.map(\.name) == ["tidepool-api"])
        #expect(host.shell.toast?.message.contains("tidepool-web") == true)
    }

    @Test func pausedWritesAreRefusedWithAToast() async {
        let host = FakeHost()
        host.pausedReason = "Changes are paused."
        let (m, s, _) = await make(host)
        #expect(await m.create(name: "Tidepool", slug: "tidepool", colour: .blue) == false)
        #expect(s.calls.isEmpty)
        #expect(host.shell.toast?.message == "Changes are paused.")
    }

    @Test func addingReposToAnEmptyProjectMakesTheFirstPrimary() async {
        let (m, s, _) = await make()
        _ = await m.create(name: "Tidepool", slug: "tidepool", colour: .blue)
        #expect(await m.addRepos(to: m.projects[0], [pick("tidepool-api")]))
        #expect(s.calls.last == "repo tidepool-api primary=true")
    }

    @Test func filterMatchesNameAndLink() async {
        let (m, _, _) = await make()
        _ = await m.create(name: "Tidepool Labs", slug: "tidepool", colour: .blue)
        _ = await m.create(name: "Quill", slug: "quill", colour: .blue)
        m.filter = "TIDE"
        #expect(m.shown.map(\.slug) == ["tidepool"])
        m.filter = "qui"
        #expect(m.shown.map(\.slug) == ["quill"])
        m.filter = "zzz"
        #expect(m.shown.isEmpty)
    }

    @Test func detachingClearsEverything() async {
        let (m, _, _) = await make()
        _ = await m.create(name: "Tidepool", slug: "tidepool", colour: .blue)
        m.detach()
        #expect(m.projects.isEmpty && m.openID == nil && m.load == .notConnected)
    }

    @Test func railKeysAndStartingState() async {
        #expect(ProjectSection.allCases.map(\.key) == ["1", "2", "3", "4", "5", "6", "7"])
        var p = ProjectItem(
            id: 1, slug: "demo", name: "Demo", description: "", expose: true,
            repos: [
                RepoItem(
                    id: 1, name: "a", remoteURL: "https://x/a", branch: "main", primary: true, fetchedAt: Date(),
                    fetchError: nil)
            ], updatedAt: Date())
        p.run = RunSummary(state: .starting, services: 5)
        #expect(p.tag == .starting && p.badge.label == "Starting")
        let (m, _, _) = await make()
        m.section = .repos
        m.openProject(1)
        #expect(m.section == .overview)
        #expect(m.canControl(p))
        #expect(ProjectSection.brain.empty(p).title == "Demo room")
    }
}

@MainActor
struct SettingsAndRunTests {
    private func projectWithRepo(_ m: ProjectsModel) async -> ProjectItem {
        _ = await m.create(name: "Tidepool", slug: "tidepool", colour: .blue, repos: [pick("tidepool-api")])
        return m.projects[0]
    }

    @Test func startingAsksTouchIDAndShowsTheRunTheCoreAnswered() async {
        let (m, s, host) = await make()
        let p = await projectWithRepo(m)
        host.reasons.removeAll()
        await m.runControl(.start, p)
        #expect(s.calls.last == "run start")
        #expect(host.reasons.count == 1)
        #expect(m.projects[0].tag == .starting)
        await m.runControl(.stop, m.projects[0])
        #expect(m.projects[0].tag == .stopped)
        #expect(m.controlling.isEmpty)
    }

    @Test func aDeclinedTouchIDDoesNotStart() async {
        let host = FakeHost()
        let (m, s, _) = await make(host)
        let p = await projectWithRepo(m)
        host.declines = true
        await m.runControl(.start, p)
        #expect(!s.calls.contains("run start"))
        #expect(m.projects[0].tag == p.tag, "a declined start changes nothing")
    }

    @Test func aRunningRunShowsItsIdleTimerAndAFailedOneWhyItFailed() async {
        let (m, s, _) = await make()
        let p = await projectWithRepo(m)
        s.runState = ProjectRunState(
            summary: RunSummary(state: .running), startedAt: Date().addingTimeInterval(-600),
            idleStopAt: Date().addingTimeInterval(26 * 60))
        await m.refreshRun(p.id)
        #expect(m.projects[0].tag == .running)
        #expect(m.projects[0].live?.idle == "idle 4 min of 30")
        s.runState = ProjectRunState(
            summary: RunSummary(state: .failed), startedAt: Date(), error: "port 3000 is taken",
            stopReason: "start_failed")
        await m.refreshRun(p.id)
        #expect(m.projects[0].live?.failure == "port 3000 is taken")
        #expect(m.projects[0].live?.idle == nil)
    }

    @Test func savingGeneralChangesNameAndDescriptionBehindOneTouchID() async {
        let (m, s, host) = await make()
        let p = await projectWithRepo(m)
        host.reasons.removeAll()
        #expect(await m.saveGeneral(p, name: " Tidepool Labs ", description: "Tides"))
        #expect(s.calls.last == "update Tidepool Labs | Tides")
        #expect(host.reasons.count == 1)
        #expect(m.projects[0].name == "Tidepool Labs")
        #expect(await m.saveGeneral(p, name: "  ", description: "") == false)
        #expect(m.writeError == "Give the project a name.")
    }

    @Test func archivingClosesTheSpace() async {
        let (m, s, _) = await make()
        let p = await projectWithRepo(m)
        m.openProject(p.id)
        await m.archive(p)
        #expect(s.calls.last == "archive")
        #expect(m.projects.isEmpty)
    }

    @Test func limitsAreSaidInWords() {
        #expect(SettingsPage.cpus(2) == "2 CPUs")
        #expect(SettingsPage.cpus(1) == "1 CPU")
        #expect(SettingsPage.cpus(1.5) == "1.5 CPUs")
        #expect(SettingsPage.memory(2048) == "2 GB")
        #expect(SettingsPage.memory(512) == "512 MB")
    }
}

@MainActor
@Suite struct ProjectPagesTests {
    @Test func roomCountsItsRulesFromTheBrainOverview() {
        let rules = OverviewRules(workflow: [OverviewRule("a")], never: [OverviewRule("b"), OverviewRule("c")])
        let overview = RoomOverview(
            state: .written, overview: OverviewBody(summary: "One.\n\nTwo.", rules: rules),
            instructionsApprovedAt: "2026-11-16T10:00:00Z")
        let room = ProjectLive.Room(overview: overview, items: 5, updated: "now")
        #expect(room.rules == 3)
        #expect(room.summary == "One.")
        #expect(room.instructionsInUse)
    }

    @Test func aRepoKeepsTheHeadOfTheCoresCopy() {
        #expect(
            RepoItem(id: 1, name: "a", remoteURL: "", branch: "main", primary: true, fetchedAt: nil, fetchError: nil)
                .head == nil)
        #expect(ProjectSection.brain.symbol == "brain")
    }
}

@Suite struct DocGroupTests {
    @Test func tagsPickTheGroup() {
        #expect(DocGroup.of(text: "# Launch\n#plans #q4\n") == .plans)
        #expect(DocGroup.of(text: "Intro #Spec text") == .specs)
        #expect(DocGroup.of(text: "#runbooks, deploy") == .runbooks)
        #expect(DocGroup.of(text: "#specs #plans") == .plans)
        #expect(DocGroup.of(text: "# Heading\nnothing tagged #planet") == .other)
        #expect(DocGroup.of(text: "") == .other)
    }

    @Test func docsIsLastCaseSoOtherKeysStay() {
        #expect(ProjectSection.settings.key == "6" && ProjectSection.docs.key == "7")
        #expect(ProjectSection.allCases.filter { $0 != .settings }.map(\.title).suffix(2) == ["Brain", "Docs"])
    }
}

struct RepoCopyTests {
    private func repo(
        state: String? = nil, reason: String? = nil, error: String? = nil, fetched: Date? = nil, since: Date? = nil
    ) -> RepoItem {
        RepoItem(
            id: 1, name: "web", remoteURL: "https://github.com/acme/web.git", branch: "main", primary: true,
            fetchedAt: fetched, fetchError: error, state: state, reason: reason, startedAt: since)
    }

    @Test func theCoresStateIsShownAsItIs() {
        let t = Date(timeIntervalSince1970: 1_000)
        #expect(repo(state: "fetching", since: t).copy == .fetching(since: t))
        #expect(repo(state: "ready", fetched: t).copy == .ready)
        let failed = repo(state: "failed", reason: "needs_github", error: "This repo is private.").copy
        #expect(failed == .failed(.needsGithub, "This repo is private."))
    }

    @Test func aCoreThatSaysNoStateStillNeverSticksOnCopying() {
        #expect(repo(error: "unreachable").copy == .failed(.other, "unreachable"))
        #expect(repo(fetched: Date()).copy == .ready)
        #expect(repo().copy == .fetching(since: nil))
    }

    @Test func onlyGithubAndSignInFailuresSendThePersonToConnections() {
        #expect(RepoFailure(code: "needs_github").needsConnection && RepoFailure(code: "auth_failed").needsConnection)
        for code in ["timeout", "not_found_or_private", "ssh_not_supported", "other", nil] {
            #expect(!RepoFailure(code: code).needsConnection)
        }
    }

    @Test func elapsedTimeIsInSecondsThenMinutes() {
        let t = Date(timeIntervalSince1970: 0)
        #expect(RepoCopy.elapsed(since: t, now: Date(timeIntervalSince1970: 40)) == "copying · 40 s")
        #expect(RepoCopy.elapsed(since: t, now: Date(timeIntervalSince1970: 125)) == "copying · 2 min 5 s")
        #expect(RepoCopy.elapsed(since: nil, now: t) == "copying…")
    }
}
