import Foundation
import Shell
import Testing

@testable import Projects

/// A Core with an archived project and the run limits (E2-4).
private final class OptionsService: ProjectsService, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var saved: [ProjectLimits] = []
    private(set) var unarchived: [Int64] = []
    var held: ProjectLimits? = .standard
    func projects() async throws -> [ProjectItem] { [item(1, "live", archived: false)] }
    func archivedProjects() async throws -> [ProjectItem] { [item(2, "old", archived: true)] }
    func create(slug: String, name: String) async throws -> ProjectItem { item(9, slug, archived: false) }
    func addRepo(project: Int64, name: String, url: String, primary: Bool) async throws {}
    func setExpose(project: Int64, _ on: Bool) async throws {}
    func unarchive(project: Int64) async throws { lock.withLock { unarchived.append(project) } }
    func limits() async throws -> ProjectLimits? { lock.withLock { held } }
    func setLimits(_ limits: ProjectLimits) async throws { lock.withLock { saved.append(limits) } }
    private func item(_ id: Int64, _ slug: String, archived: Bool) -> ProjectItem {
        ProjectItem(
            id: id, slug: slug, name: slug, description: "", expose: true, repos: [], updatedAt: Date(),
            archived: archived)
    }
}

@MainActor
private func make() async -> (ProjectsModel, OptionsService, FakeHost) {
    let host = FakeHost()
    let m = ProjectsModel(host: host, defaults: UserDefaults(suiteName: "projects-options-\(UUID())")!)
    let s = OptionsService()
    m.use(s)
    _ = await until { m.load == .ready }
    return (m, s, host)
}

@MainActor
struct ProjectsOptionsTests {
    @Test func theMenusMapToTheCoresNumbers() {
        var l = ProjectLimits.standard
        #expect((ProjectsOptions.coreChoice(l), ProjectsOptions.memoryChoice(l)) == (2, 4))
        #expect(ProjectsOptions.idleChoice(l) == 30)
        l = ProjectsOptions.setIdle(l, minutes: 0)
        #expect(l.idleNever && l.idleMinutes == 30, "Never keeps the minutes the Core holds")
        #expect(ProjectsOptions.idleChoice(l) == 0)
        l = ProjectsOptions.setIdle(l, minutes: 120)
        #expect(!l.idleNever && l.idleMinutes == 120)
        // A value set from elsewhere shows as the nearest choice at or above it.
        l = ProjectLimits(cpus: 3, memoryMb: 3000, idleMinutes: 45, idleNever: false)
        #expect((ProjectsOptions.coreChoice(l), ProjectsOptions.memoryChoice(l), ProjectsOptions.idleChoice(l)) == (4, 4, 120))
    }

    @Test func limitsRoundTripTheCoresJSON() throws {
        let l = ProjectLimits(cpus: 4, memoryMb: 8192, idleMinutes: 15, idleNever: true)
        #expect(try ProjectLimits.decode(try l.encoded()) == l)
        let json = Data(#"{"cpu_limit":2.0,"mem_limit_mb":4096,"idle_minutes":30,"idle_never":false}"#.utf8)
        #expect(try ProjectLimits.decode(json) == .standard)
    }

    @Test func archivedProjectsShowOnlyWhenTheSwitchIsOn() async {
        let options = ProjectsOptions.options
        let was = options.bool(ProjectsOptions.showArchivedKey, false)
        defer { options.set(ProjectsOptions.showArchivedKey, was) }
        options.set(ProjectsOptions.showArchivedKey, false)
        let (m, _, _) = await make()
        #expect(m.projects.map(\.slug) == ["live"])
        options.set(ProjectsOptions.showArchivedKey, true)
        await m.reload()
        #expect(m.projects.map(\.slug) == ["live", "old"])
        #expect(m.projects.last?.archived == true)
        #expect(m.projects.last?.badge.label == "Archived")
    }

    @Test func aChosenLimitIsSavedForAllProjectsBehindTouchID() async {
        let (m, s, host) = await make()
        await m.loadLimits()
        m.saveLimits { $0.cpus = 8 }
        _ = await until { !s.saved.isEmpty }
        #expect(s.saved.last?.cpus == 8)
        #expect(host.reasons.last?.contains("every project") == true)
        #expect(m.limits?.cpus == 8)
    }

    @Test func aDeclinedSaveGoesBackToWhatTheCoreHolds() async {
        let (m, s, host) = await make()
        await m.loadLimits()
        host.declines = true
        m.saveLimits { $0.memoryMb = 8192 }
        _ = await until { m.limits?.memoryMb == 4096 }
        #expect(m.limits == .standard && s.saved.isEmpty)
    }

    @Test func aCoreWithoutTheSettingSaysSo() async {
        let (m, s, _) = await make()
        s.held = nil
        await m.loadLimits()
        #expect(m.limits == nil && m.limitsState == .unsupported)
    }

    @Test func unarchiveAsksTheCoreAndReloads() async {
        let (m, s, host) = await make()
        let old = ProjectItem(
            id: 2, slug: "old", name: "old", description: "", expose: true, repos: [], updatedAt: Date(), archived: true)
        await m.unarchive(old)
        #expect(s.unarchived == [2])
        #expect(host.reasons.last?.contains("old") == true)
    }

    @Test func openingAProjectFollowsTheChoice() async {
        let options = ProjectsOptions.options
        let was = options.string(ProjectsOptions.openInKey, "new")
        defer { options.set(ProjectsOptions.openInKey, was) }
        let (m, _, host) = await make()
        options.set(ProjectsOptions.openInKey, "this")
        m.openProject(1)
        #expect(m.openID == 1 && !host.shell.panes.contains { $0.id == "project-1" })
        m.closeProject()
        options.set(ProjectsOptions.openInKey, "new")
        m.openProject(1)
        #expect(m.openID == nil && host.shell.panes.contains { $0.id == "project-1" })
    }
}
