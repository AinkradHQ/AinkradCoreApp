import Admin
import Foundation
import Shell
import Testing

@testable import Projects

@MainActor
final class FakeHost: AdminHost {
    let shell = ShellModel()
    var pausedReason: String?
    var elevationNotice: AdminNotice?
    var declines = false
    private(set) var reasons: [String] = []
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

    @Test @MainActor func reduceMotionMeansNoTravel() {
        #expect(ProjectsMotion.rise(true) == 0)
        #expect(ProjectsMotion.rise(false) > 0)
    }
}

@MainActor
struct ModelTests {
    @Test func creatingAddsTheReposBehindOneTouchID() async {
        let (m, s, host) = await make()
        let ok = await m.create(
            name: "Tidepool", slug: "tidepool", colour: .green, repos: [pick("tidepool-api"), pick("tidepool-web")])
        #expect(ok)
        #expect(host.reasons.count == 1)
        #expect(s.calls == ["create tidepool", "repo tidepool-api primary=true", "repo tidepool-web primary=false"])
        #expect(m.openID == m.projects.first?.id)
        #expect(m.colour(m.projects[0]) == .green)
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
}
