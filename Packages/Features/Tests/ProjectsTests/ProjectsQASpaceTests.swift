import AppKit
import Foundation
import Shell
import Testing

@testable import Projects

@MainActor
private func make() async -> (ProjectsModel, FakeService, FakeHost) {
    let host = FakeHost()
    let m = ProjectsModel(host: host, defaults: UserDefaults(suiteName: "qa-space-\(UUID())")!)
    let s = FakeService()
    m.eventDelay = .milliseconds(5)
    _ = try? await s.create(slug: "tidepool", name: "Tidepool")
    _ = try? await s.create(slug: "quill", name: "Quill")
    m.use(s)
    _ = await until { m.load == .ready }
    return (m, s, host)
}

@MainActor
struct SpaceModulesTests {
    @Test func theRunModuleIsOnTheRailOfEveryKindThatRuns() {
        for k in [ProjectKind.web, .app, .infra] { #expect(ProjectModule.rail(for: [k]).contains(.run)) }
        #expect(!ProjectModule.rail(for: [.other]).contains(.run))
        #expect(ProjectModule.run.title == "Run setup")
    }

    @Test func onlyTheFirstNineRailItemsHaveAKey() {
        let keys = (0..<12).map(ProjectModule.key(at:))
        #expect(keys.prefix(9).map { $0! } == Array(1...9))
        #expect(keys.suffix(3).allSatisfy { $0 == nil })
    }

    @Test func everySpaceKeepsItsOwnModule() async {
        let (m, _, _) = await make()
        m.go(.settings, in: 1)
        #expect(m.moduleOf(1) == .settings && m.moduleOf(2) == .overview)
        m.go(.repos, in: 2)
        #expect(m.moduleOf(1) == .settings && m.moduleOf(2) == .repos)
    }

    @Test func theCrashToastOpensTheLogsAndTheOldRunPageIsTheRunModule() async {
        let (m, _, _) = await make()
        m.openProject(1, section: .run)
        #expect(m.moduleOf(1) == .run)
        m.openProject(2, module: .logs)
        #expect(m.moduleOf(2) == .logs)
    }

    @Test func anArchivedProjectIsFoundToo() async {
        let (m, _, _) = await make()
        var a = m.projects[0]
        a.archived = true
        m.archivedList = [a]
        m.projects = []
        #expect(m.project(a.id)?.archived == true)
    }

    @Test func detachForgetsTheCoreData() async {
        let (m, _, _) = await make()
        m.archivedList = m.projects
        m.runStates[1] = ProjectRunState(summary: RunSummary(state: .running), startedAt: Date())
        m.places = []
        m.go(.brain, in: 1)
        m.detach()
        #expect(m.archivedList.isEmpty && m.runStates.isEmpty && m.places == nil && m.modules.isEmpty)
        #expect(m.wizardDraft == nil && m.creating == nil && m.projects.isEmpty)
    }
}

@MainActor
struct SpaceRefreshTests {
    @Test func everyOpenSpaceIsRefreshedNotOnlyTheMainPanes() async {
        let (m, _, _) = await make()
        #expect(m.openID == nil)
        m.spaceAppeared(1)
        m.spaceAppeared(2)
        m.event(kind: "project.run_started")
        #expect(await until { m.tick(1) == 1 && m.tick(2) == 1 })
        m.spaceGone(2)
        m.event(kind: "project.run_stopped")
        #expect(await until { m.tick(1) == 2 })
        #expect(m.tick(2) == 1)
    }

    @Test func aBurstOfEventsIsOneRead() async {
        let (m, s, _) = await make()
        m.eventDelay = .milliseconds(60)
        let before = s.listReads
        for _ in 0..<10 { m.event(kind: "project.mirror_changed") }
        #expect(await until { s.listReads > before })
        try? await Task.sleep(for: .milliseconds(150))
        #expect(s.listReads == before + 1)
    }

    @Test func anAIEventReadsNoList() async {
        let (m, s, _) = await make()
        m.spaceAppeared(1)
        let before = s.listReads
        m.event(kind: "agent.state")
        m.event(kind: "agent.output")
        try? await Task.sleep(for: .milliseconds(80))
        #expect(s.listReads == before && m.tick(1) == 0)
    }

    @Test func readsAskedTogetherNeverPileUp() async {
        let (m, s, _) = await make()
        let before = s.listReads
        await withTaskGroup(of: Void.self) { g in
            for _ in 0..<8 { g.addTask { await m.reload() } }
        }
        // One under way, one more for everything asked meanwhile.
        #expect(s.listReads - before <= 2)
        #expect(m.load == .ready)
    }

    @Test func aCancelledReadDoesNotSayTheCoreIsSilent() async {
        let (m, s, _) = await make()
        s.runError = CancellationError()
        await m.refreshRun(1)
        #expect(!m.coreSilent)
        s.runError = URLError(.cancelled)
        await m.refreshRun(1)
        #expect(!m.coreSilent)
        s.runError = CoreFailureStub.refused
        await m.refreshRun(1)
        #expect(!m.coreSilent)
        s.runError = URLError(.timedOut)
        await m.refreshRun(1)
        #expect(m.coreSilent)
    }
}

private enum CoreFailureStub: Error { case refused }

@MainActor
struct SpaceBehaviourTests {
    @Test func startWaitsWhileAnotherStartIsUnderWay() {
        var p = ProjectItem(id: 1, slug: "a", name: "A", description: "", expose: false, repos: [], updatedAt: Date())
        #expect(p.controlBlock(canControl: true) == nil)
        let busy = p.controlBlock(canControl: false, busy: true)
        #expect(busy?.contains("under way") == true)
        p.stale = true
        #expect(p.controlBlock(canControl: true)?.contains("not answering") == true)
    }

    @Test func aPrivateProjectOpensItsPreviewAndOnlyAPublicOneTheBrowser() async {
        let (m, _, _) = await make()
        var p = m.projects[0]
        p.expose = false
        #expect(m.siteTarget(p) == .preview)
        p.expose = true
        #expect(m.siteTarget(p) == .browser(URL(string: "https://\(p.link)")!))
        p.expose = false
        m.openSite(p)
        #expect(m.moduleOf(p.id) == .live)
    }

    @Test func leavingAsksOnlyWhileSettingsHoldUnsavedChanges() async {
        let (m, _, host) = await make()
        var left = 0
        m.leaveSpace(1) { left += 1 }
        #expect(left == 1)
        m.setDraft(1, dirty: true)
        m.leaveSpace(1) { left += 1 }
        #expect(left == 1 && host.shell.dialog != nil)
        m.setDraft(1, dirty: false)
        m.leaveSpace(1) { left += 1 }
        #expect(left == 2)
    }

    @Test func oneLiveViewPerProjectUntilItsSpaceCloses() async {
        let (m, _, _) = await make()
        m.spaceAppeared(1)
        m.spaceAppeared(1)
        let a = m.liveWeb(for: 1)
        #expect(a === m.liveWeb(for: 1) && a !== m.liveWeb(for: 2))
        m.spaceGone(1)
        #expect(a === m.liveWeb(for: 1))
        m.spaceGone(1)
        #expect(a !== m.liveWeb(for: 1))
    }

    @Test func aPageMayOnlyStayOnItsOwnOrigin() {
        let origin = URL(string: "ainkrad-preview://p")!
        func decide(_ s: String, main: Bool = true) -> LiveWebView.Coordinator.Navigation {
            LiveWebView.Coordinator.decide(URL(string: s), from: origin, mainFrame: main)
        }
        #expect(decide("ainkrad-preview://p/about") == .allow)
        #expect(decide("https://evil.example/x") == .browser(URL(string: "https://evil.example/x")!))
        #expect(decide("file:///etc/hosts") == .block)
        #expect(decide("ainkrad-preview://other/") == .block)
        #expect(decide("https://evil.example/x", main: false) == .allow)
        let site = URL(string: "https://tidepool.ainkrad.io")!
        #expect(LiveWebView.Coordinator.decide(URL(string: "http://tidepool.ainkrad.io/a"), from: site, mainFrame: true) == .allow)
    }

    @Test func aStoppedLogIsReadOnceNotForEver() async {
        let source = FakeLogSource()
        let m = RunLogsModel(source: source)
        m.useStream = false
        m.keepReading = { false }
        await m.run()
        #expect(source.pageCalls.count == 1 && m.feed == .ended)
    }

    @Test func previewPicturesAreKeyedByCoreAndKeptSmall() {
        #expect(PreviewStore.fileName(core: "a.example", id: 3) != PreviewStore.fileName(core: "b.example", id: 3))
        #expect(PreviewStore.fileName(core: "x/y", id: 3) == "x_y-3.png")
        let big = NSImage(size: NSSize(width: 3000, height: 1500))
        #expect(PreviewStore.scaled(big).size.width == PreviewStore.maxWidth)
        #expect(PreviewStore.scaled(NSImage(size: NSSize(width: 200, height: 100))).size.width == 200)
    }
}
