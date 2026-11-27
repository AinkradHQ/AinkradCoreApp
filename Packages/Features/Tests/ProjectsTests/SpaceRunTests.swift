import Foundation
import Testing

@testable import Projects

// The project space and Run, on the Core's real JSON shapes (AinkradCore origin/development, crates/server/src/api/v1/projects).

struct LogTextTests {
    @Test func colourAndCursorCodesAreRemoved() {
        #expect(LogText.plain("\u{1B}[32mready\u{1B}[0m on :8000") == "ready on :8000")
        #expect(LogText.plain("\u{1B}[1;31;40mfail\u{1B}[K") == "fail")
        #expect(LogText.plain("\u{1B}]0;title\u{07}text") == "text")
        #expect(LogText.plain("plain") == "plain")
        // A progress bar that redraws with \r leaves its last draw.
        #expect(LogText.plain("10%\r50%\r100%") == "100%")
    }
}

struct LogWireTests {
    @Test func aPageReadsSeqAtAndLost() throws {
        let json =
            #"{"run":"r_1","lines":[{"seq":7,"service":"web","at":"2026-11-27T10:00:01.250Z","text":"up"}],"next":7,"lost":3}"#
        let p = try RunWire.logs(Data(json.utf8), after: 0)
        #expect(p.next == 7 && p.lost == 3 && p.lines[0].seq == 7 && p.lines[0].at != nil)
    }

    @Test func queryEscapesTheServiceAndRun() {
        let q = LiveRunLogSource.query(after: 4, service: "a b&c", run: "r/1", limit: 500)
        #expect(q == "after=4&service=a%20b&c&run=r%2F1&limit=500")
    }

    @Test func secretsReadKindAndUse() throws {
        let s = try RunWire.secrets(
            Data(
                #"[{"name":"tls_key","kind":"multiline","description":"edge","version":2,"size":9,"updated_at":"2026-11-18T10:00:00Z","last_used_at":null,"use_count":4}]"#
                    .utf8))
        #expect(s[0].kind == "multiline" && s[0].useCount == 4 && s[0].lastUsedAt == nil && s[0].description == "edge")
        let body = RunWire.secretBody(SecretInput(value: "x", kind: "file", description: "", fileName: "k.json"))
        #expect(
            body["kind"] as? String == "file" && body["file_name"] as? String == "k.json" && body["description"] == nil)
        #expect(RunWire.secretBody(SecretInput(value: "x"))["file_name"] == nil)
        let v = try RunWire.versions(
            Data(
                #"[{"version":2,"origin":"compose","created_by":"d","created_at":"2026-11-18T10:00:00Z"},{"version":1,"origin":"manual","created_by":"d","created_at":"2026-11-17T10:00:00Z"}]"#
                    .utf8))
        #expect(v.map(\.version) == [2, 1] && v[0].origin == "compose")
    }

    @Test func envValuesThatAreNotStringsAreKept() throws {
        let spec = #"{"services":{"api":{"image":"x","env":{"PORT":8000,"DEBUG":true,"KEY":"${secret:app_key}"}}}}"#
        let v = try RunWire.specVersion(Data(#"{"version":1,"origin":"manual","spec":\#(spec)}"#.utf8))
        #expect(v.services[0].secrets == ["app_key"])
        #expect(RunWire.text(8000 as NSNumber) == "8000" && RunWire.text(true as NSNumber) == "true")
    }

    @Test func runStatusReadsStopReasonAndActivity() throws {
        let r = try RunWire.run(
            Data(
                #"{"state":"stopped","stop_reason":"idle","last_activity_at":"2026-11-27T09:00:00Z","error":null}"#.utf8
            ))
        #expect(r.stopReason == "idle" && r.lastActivityAt != nil)
    }
}

struct SpecDiffContextTests {
    private func file(_ n: Int, changing: Set<Int> = []) -> String {
        (1...n).map { changing.contains($0) ? "new \($0)" : "line \($0)" }.joined(separator: "\n")
    }

    @Test func changesComeInFileOrderWithContextAndGaps() {
        let d = SpecDiff.lines(from: file(20), to: file(20, changing: [3, 15]))
        let signs = d.map(\.kind)
        // line 3 changes: removed before added, both before line 15's change.
        let firstRemoved = signs.firstIndex(of: .removed)!
        let lastAdded = signs.lastIndex(of: .added)!
        #expect(d[firstRemoved].text == "line 3" && d[lastAdded].text == "new 15")
        #expect(d[firstRemoved + 1].kind == .added && d[firstRemoved + 1].text == "new 3")
        // Three unchanged lines stand before the first change (lines 1 and 2 here) and a gap marks what was left out.
        #expect(d.first?.kind == .context && d.contains { $0.kind == .gap })
        #expect(!d.contains { $0.text == "line 9" })
        #expect(d.contains { $0.text == "line 13" } && d.contains { $0.text == "line 18" })
    }

    @Test func nothingChangedIsEmpty() { #expect(SpecDiff.lines(from: file(5), to: file(5)).isEmpty) }
}

struct SetupStageTests {
    private func item(repos: [RepoItem], draft: RunDraft? = nil, checked: Bool = false, run: RunSummary? = nil)
        -> ProjectItem
    {
        var p = ProjectItem(
            id: 1, slug: "a", name: "A", description: "", expose: true, repos: repos, updatedAt: Date(), run: run)
        p.draft = draft
        p.setupChecked = checked
        return p
    }

    private func repo(fetched: Bool, error: String? = nil) -> RepoItem {
        RepoItem(
            id: 1, name: "r", remoteURL: "https://x/r", branch: "main", primary: true,
            fetchedAt: fetched ? Date() : nil, fetchError: error)
    }

    @Test func theStageFollowsTheCore() {
        #expect(item(repos: []).setup == .noRepos)
        #expect(item(repos: [repo(fetched: false)]).setup == .copying)
        #expect(item(repos: [repo(fetched: false, error: "no")]).setup == .copyFailed("no"))
        #expect(item(repos: [repo(fetched: true)]).setup == .checking)
        #expect(item(repos: [repo(fetched: true)], checked: true).setup == .needsSetup)
        let d = RunDraft(source: "docker-compose.yml", services: ["web"], secrets: [])
        #expect(item(repos: [repo(fetched: true)], draft: d, checked: true).setup == .ready(d))
        #expect(item(repos: [repo(fetched: true)], run: RunSummary(state: .stopped)).setup == .ran)
    }

    @Test func startWaitsOnlyForRealReasons() {
        let r = [repo(fetched: true)]
        #expect(item(repos: r, checked: true).startBlock != nil)
        #expect(item(repos: r).startBlock != nil)
        let missing = RunDraft(source: "x", services: ["web"], secrets: ["jwt_secret"])
        #expect(item(repos: r, draft: missing, checked: true).startBlock?.contains("jwt_secret") == true)
        let ready = RunDraft(source: "x", services: ["web"], secrets: [])
        #expect(item(repos: r, draft: ready, checked: true).startBlock == nil)
        #expect(item(repos: r, run: RunSummary(state: .stopped)).startBlock == nil)
    }

    @Test func aStaleRunningProjectIsNotClaimedRunning() {
        var p = item(repos: [repo(fetched: true)], run: RunSummary(state: .running, services: 3))
        #expect(p.badge.label == "Running")
        p.stale = true
        #expect(p.badge.label == "Status unknown" && p.subtitle.contains("Last seen running"))
    }

    @Test func limitWordsUseTheProjectsOwn() {
        #expect(ProjectRules.limits(cpu: 2, memMb: 2048) == "2 CPUs, 2 GB")
        #expect(ProjectRules.limits(cpu: 1, memMb: 512) == "1 CPU, 512 MB")
        #expect(ProjectRules.limits(cpu: 0.5, memMb: 1536) == "0.5 CPUs, 1.5 GB")
        #expect(ProjectRules.idleWords(minutes: 45, never: false) == "after 45 min with no visits")
        #expect(ProjectRules.idleWords(minutes: 45, never: true) == "never")
    }
}

@MainActor
struct CrashLoopTests {
    private func crash(_ cfg: Int64, ago: TimeInterval, now: Date) -> RunRecord {
        RunRecord(
            id: UUID().uuidString, state: "failed", configID: cfg, environment: nil, runner: "d",
            startedAt: now.addingTimeInterval(-ago - 10), stoppedAt: now.addingTimeInterval(-ago), stopReason: "crash",
            error: nil)
    }

    @Test func threeCrashesInTenMinutesWithNothingLiveIsALoop() {
        let now = Date()
        #expect(
            CrashLoop.detect(
                [crash(1, ago: 60, now: now), crash(1, ago: 200, now: now), crash(1, ago: 400, now: now)], now: now))
        #expect(!CrashLoop.detect([crash(1, ago: 60, now: now), crash(1, ago: 200, now: now)], now: now))
        // Spread over an hour: not a loop.
        #expect(
            !CrashLoop.detect(
                [crash(1, ago: 60, now: now), crash(1, ago: 1800, now: now), crash(1, ago: 3000, now: now)], now: now))
        // Different configurations do not add up.
        #expect(
            !CrashLoop.detect(
                [crash(1, ago: 60, now: now), crash(2, ago: 200, now: now), crash(3, ago: 400, now: now)], now: now))
    }

    @Test func aLiveRunOfTheConfigurationEndsTheLoop() {
        let now = Date()
        let live = RunRecord(
            id: "l", state: "running", configID: 1, environment: nil, runner: "d", startedAt: now, stoppedAt: nil,
            stopReason: nil, error: nil)
        #expect(
            !CrashLoop.detect(
                [live, crash(1, ago: 60, now: now), crash(1, ago: 200, now: now), crash(1, ago: 400, now: now)],
                now: now))
    }

    @Test func reasonsHaveTheirOwnWords() {
        #expect(ProjectsModel.reason("crash") != ProjectsModel.reason("runner_lost"))
        #expect(ProjectsModel.reason("user") == "You stopped it.")
        #expect(ProjectsModel.reason("weird").contains("weird"))
    }
}

/// A log the test feeds by hand: pages for the poll, and a stream the test can push into or fail.
final class FakeLogSource: RunLogSource, @unchecked Sendable {
    private let lock = NSLock()
    var pages: [RunLogPage] = []
    var pageCalls: [(Int, String?)] = []
    var streamCalls: [(Int, String?)] = []
    var streamPages: [RunLogPage]?
    var streamError: (any Error)?

    func page(after: Int, service: String?) async throws -> RunLogPage {
        lock.withLock {
            pageCalls.append((after, service))
            return pages.isEmpty ? RunLogPage(next: after) : pages.removeFirst()
        }
    }

    func stream(after: Int, service: String?) -> AsyncThrowingStream<RunLogPage, any Error>? {
        let (list, err): ([RunLogPage]?, (any Error)?) = lock.withLock {
            streamCalls.append((after, service))
            return (streamPages, streamError)
        }
        guard let list else { return nil }
        return AsyncThrowingStream { out in
            for p in list { out.yield(p) }
            if let err { out.finish(throwing: err) } else { out.finish() }
        }
    }
}

private func line(_ seq: Int, _ text: String, _ service: String = "web", at: Date? = nil) -> ProjectLive.LogLine {
    ProjectLive.LogLine(service: service, text: text, seq: seq, at: at)
}

@MainActor
struct RunLogsModelTests {
    @Test func linesGapsAndCleanText() {
        let m = RunLogsModel(source: FakeLogSource())
        m.ingest(RunLogPage(lines: [line(1, "\u{1B}[32mok\u{1B}[0m"), line(2, "two")], next: 2, lost: 0))
        m.ingest(RunLogPage(lines: [line(9, "nine")], next: 9, lost: 6))
        #expect(m.lineCount == 3 && m.skipped == 6)
        #expect(m.entries.map(\.kind).contains(.skipped(6)))
        #expect(RunLogsModel.gapWords(6) == "6 lines skipped" && RunLogsModel.gapWords(1) == "1 line skipped")
        if case .line(let l) = m.entries[0].kind { #expect(l.text == "ok") }
        #expect(m.copyText.contains("… 6 lines skipped") && m.copyText.hasPrefix("web  ok"))
    }

    @Test func searchKeepsMatchingLinesOnly() {
        let m = RunLogsModel(source: FakeLogSource())
        m.ingest(RunLogPage(lines: [line(1, "GET / 200"), line(2, "ERROR boom"), line(3, "get /x 404")], next: 3))
        m.search = "get"
        #expect(m.shown.count == 2 && m.matchLine == "2 of 3 lines")
        m.search = "nothing"
        #expect(m.shown.isEmpty)
        m.search = ""
        #expect(m.shown.count == 3 && m.matchLine == nil)
    }

    @Test func timesAreInTheCopy() {
        let m = RunLogsModel(source: FakeLogSource())
        m.ingest(RunLogPage(lines: [line(1, "a", at: Date(timeIntervalSince1970: 1_700_000_000))], next: 1))
        #expect(!m.copyText.contains(":"))
        m.showTimes = true
        #expect(m.copyText.range(of: #"^\d\d:\d\d:\d\d web  a$"#, options: .regularExpression) != nil)
    }

    @Test func theWindowKeepsTheNewestLines() {
        let m = RunLogsModel(source: FakeLogSource())
        let many = (1...(RunLogsModel.cap + 50)).map { line($0, "l\($0)") }
        m.ingest(RunLogPage(lines: many, next: many.count))
        #expect(m.entries.count == RunLogsModel.cap)
        if case .line(let l) = m.entries.last!.kind { #expect(l.text == "l\(RunLogsModel.cap + 50)") }
    }

    @Test func scrollingUpPausesFollowAndTheEndResumesIt() {
        let m = RunLogsModel(source: FakeLogSource())
        var t = Date()
        m.now = { t }
        #expect(m.follow)
        m.ingest(RunLogPage(lines: [line(1, "a")], next: 1))
        // The end leaves view right after a line arrived: that is the list growing, not the person scrolling.
        m.endVisible(false)
        #expect(m.follow)
        t = t.addingTimeInterval(1)
        m.endVisible(false)
        #expect(!m.follow)
        // New lines no longer ask the view to scroll.
        let tick = m.scrollTick
        m.ingest(RunLogPage(lines: [line(2, "b")], next: 2))
        #expect(m.scrollTick == tick)
        m.endVisible(true)
        #expect(m.follow)
        m.endVisible(false)
        m.jumpToLatest()
        #expect(m.follow && m.scrollTick > tick)
    }

    @Test func changingTheServiceStartsOverFromTheServer() {
        let m = RunLogsModel(source: FakeLogSource())
        m.ingest(RunLogPage(lines: [line(1, "a")], next: 5, lost: 2))
        m.setService("api")
        #expect(m.entries.isEmpty && m.skipped == 0 && m.service == "api")
    }

    @Test func theStreamIsReadAndEndsWhenTheRunDoes() async {
        let src = FakeLogSource()
        src.streamPages = [RunLogPage(lines: [line(1, "a")], next: 1), RunLogPage(lines: [line(2, "b")], next: 2)]
        let m = RunLogsModel(source: src)
        await m.run()
        #expect(m.lineCount == 2 && m.feed == .ended && src.pageCalls.isEmpty)
        #expect(src.streamCalls.first?.0 == 0)
    }

    @Test func aFailedStreamFallsBackToPolling() async {
        let src = FakeLogSource()
        src.streamPages = []
        src.streamError = CocoaError(.fileReadUnknown)
        src.pages = [RunLogPage(lines: [line(1, "polled")], next: 1)]
        let m = RunLogsModel(source: src)
        m.pollEvery = .milliseconds(20)
        let task = Task { await m.run() }
        #expect(await until { m.lineCount == 1 })
        task.cancel()
        #expect(m.feed == .polling && src.pageCalls.first?.0 == 0)
    }

    @Test func aSourceWithoutAStreamPollsFromTheLastLine() async {
        let src = FakeLogSource()
        src.pages = [RunLogPage(lines: [line(1, "a")], next: 1), RunLogPage(lines: [line(2, "b")], next: 2)]
        let m = RunLogsModel(source: src)
        m.pollEvery = .milliseconds(20)
        let task = Task { await m.run() }
        #expect(await until { m.lineCount == 2 })
        task.cancel()
        #expect(src.pageCalls.prefix(2).map(\.0) == [0, 1])
    }

    @Test func theFilterIsAskedOfTheServerNotDoneHere() async {
        let src = FakeLogSource()
        src.pages = [RunLogPage(lines: [line(1, "a", "api")], next: 1)]
        let m = RunLogsModel(source: src)
        m.pollEvery = .milliseconds(20)
        m.setService("api")
        let task = Task { await m.run() }
        #expect(await until { m.lineCount == 1 })
        task.cancel()
        #expect(src.pageCalls.first?.1 == "api")
    }
}

@MainActor
struct SetupReadTests {
    private func make(_ run: FakeRunService) -> ProjectsModel {
        let m = ProjectsModel(host: FakeHost(), defaults: UserDefaults(suiteName: "space-\(UUID())")!)
        m.runService = run
        return m
    }

    private let spec =
        #"{"services":{"web":{"image":"x","env":{"K":"${secret:jwt_secret}","L":"${secret:app_key}"}},"db":{"image":"p"}}}"#

    @Test func aSpecMeansReadyAndNamesTheMissingSecrets() async {
        let v = try! RunWire.specVersion(Data(#"{"version":1,"origin":"compose","spec":\#(spec)}"#.utf8))
        let run = FakeRunService(versions: [v], stored: [SecretItem(name: "app_key", version: 1, updatedAt: nil)])
        let r = await ProjectsModel.readSetup(run, 1)
        #expect(r?.draft?.services == ["db", "web"] && r?.draft?.secrets == ["jwt_secret"])
        #expect(r?.draft?.source == "docker-compose.yml" && r?.draft?.manual == false)
    }

    @Test func noSpecIsNeedsSetupNotEndlessSettingUp() async {
        let r = await ProjectsModel.readSetup(FakeRunService(versions: []), 1)
        #expect(r == SetupRead(draft: nil))
        var p = ProjectItem(
            id: 1, slug: "a", name: "A", description: "", expose: true,
            repos: [
                RepoItem(
                    id: 1, name: "r", remoteURL: "u", branch: "main", primary: true, fetchedAt: Date(), fetchError: nil)
            ],
            updatedAt: Date())
        let m = make(FakeRunService(versions: []))
        m.setupStates[1] = r!
        p = m.applying(p)
        #expect(p.setup == .needsSetup && p.startBlock != nil)
    }

    @Test func aProjectThatRanHasItsServiceCount() async {
        let v = try! RunWire.specVersion(Data(#"{"version":1,"origin":"manual","spec":\#(spec)}"#.utf8))
        let m = make(FakeRunService(versions: [v]))
        m.setupStates[1] = await ProjectsModel.readSetup(m.runService, 1)!
        m.runStates[1] = ProjectRunState(summary: RunSummary(state: .stopped), startedAt: Date())
        let p = m.applying(
            ProjectItem(id: 1, slug: "a", name: "A", description: "", expose: true, repos: [], updatedAt: Date()))
        #expect(p.run?.services == 2 && p.draft?.manual == true)
    }

    @Test func startingShowsOnlyWhatTheCoreReportsNoEasing() {
        let m = make(FakeRunService(versions: []))
        m.runStates[1] = ProjectRunState(
            summary: RunSummary(state: .starting), startedAt: Date().addingTimeInterval(-50), runner: "d_1")
        m.runnerNames["d_1"] = "core-oracle"
        let p0 = ProjectItem(id: 1, slug: "a", name: "A", description: "", expose: true, repos: [], updatedAt: Date())
        let none = m.applying(p0)
        // 50 s in and nothing reported: no bar value (the old easing would have said 83%).
        #expect(none.live?.progress == nil && none.live?.progressLine == "Starting on core-oracle…")
        m.liveParts[1] = LiveParts(services: [
            ProjectLive.Service(name: "web", memory: "1 MB", state: .up),
            ProjectLive.Service(name: "db", memory: "–", state: .down),
        ])
        let some = m.applying(p0)
        #expect(some.live?.progress == 0.5 && some.live?.progressLine.contains("1 of 2 services up") == true)
    }

    @Test func aStoppedRunSaysWhyAndWhen() {
        let m = make(FakeRunService(versions: []))
        let seen = Date().addingTimeInterval(-3600)
        m.runStates[1] = ProjectRunState(
            summary: RunSummary(state: .stopped), startedAt: seen, stopReason: "idle", runner: "d_1",
            lastActivityAt: seen)
        let p = m.applying(
            ProjectItem(id: 1, slug: "a", name: "A", description: "", expose: true, repos: [], updatedAt: Date()))
        #expect(p.live?.stopWords == "It stopped after a while with no visits." && p.live?.lastActivity == seen)
    }

    @Test func aCrashLoopGetsItsOwnMessage() {
        let m = make(FakeRunService(versions: []))
        m.runStates[1] = ProjectRunState(summary: RunSummary(state: .stopped), startedAt: Date(), stopReason: "crash")
        m.liveParts[1] = LiveParts(crashLoop: true)
        let p = m.applying(
            ProjectItem(id: 1, slug: "a", name: "A", description: "", expose: true, repos: [], updatedAt: Date()))
        #expect(p.live?.failure == ProjectsModel.crashLoopWords && p.run?.state == .failed)
    }

    @Test func theCoreGoingSilentMarksProjectsStaleAndComingBackClearsIt() {
        let m = make(FakeRunService(versions: []))
        m.runStates[1] = ProjectRunState(summary: RunSummary(state: .running), startedAt: Date())
        m.projects = [
            m.applying(
                ProjectItem(id: 1, slug: "a", name: "A", description: "", expose: true, repos: [], updatedAt: Date()))
        ]
        #expect(m.projects[0].badge.label == "Running")
        m.markSilent(true)
        #expect(m.projects[0].stale && m.projects[0].badge.label == "Status unknown")
        m.markSilent(false)
        #expect(!m.projects[0].stale && m.projects[0].badge.label == "Running")
    }
}

@MainActor
struct RunRealBehaviourTests {
    private func make() async -> (RunConfigsModel, FakeConfigsService) {
        let m = ProjectsModel(host: FakeHost(), defaults: UserDefaults(suiteName: "space-\(UUID())")!)
        let svc = FakeConfigsService()
        m.configsService = svc
        m.insightsService = FakeInsightsDefaultEnv()
        let r = RunConfigsModel(model: m, projectID: 1)
        await r.load()
        return (r, svc)
    }

    @Test func runUsesTheProjectsDefaultEnvironmentUntilOnePicked() async {
        let (r, svc) = await make()
        #expect(r.defaultEnv == "Staging" && r.runEnv == "Staging" && r.env == "Staging")
        let p = ProjectItem(id: 1, slug: "d", name: "D", description: "", expose: false, repos: [], updatedAt: Date())
        await r.start(r.configs[0], project: p)
        #expect(svc.calls.contains("start 1 Staging replace=false"))
        r.runEnvChoice = "Development"
        #expect(r.runEnv == "Development")
        // A choice that no longer exists falls back to the default.
        r.runEnvChoice = "Gone"
        #expect(r.runEnv == "Staging")
    }

    @Test func eachConfigurationKeepsItsOwnPendingEdit() async throws {
        let (r, svc) = await make()
        svc.items.append(
            RunConfigItem(
                id: 2, name: "Worker", command: "work", workdir: "", runner: "automatic", port: nil, restart: false))
        await r.load()
        r.edit(r.configs[0], RunConfigPatch(command: "one"))
        r.edit(r.configs[1], RunConfigPatch(port: 9000))
        try await Task.sleep(for: .milliseconds(1300))
        #expect(Set(svc.calls.filter { $0.hasPrefix("update") }) == ["update command", "update port"])
    }

    @Test func aFailedRevealSaysWhy() async {
        let (r, svc) = await make()
        svc.refuseReveal = true
        await r.toggleReveal(r.vars.first { $0.key == "A" }!)
        #expect(r.revealed.isEmpty && r.writeError?.contains("Could not show A") == true)
    }

    @Test func entriesThatAreNotSavedSayWhy() {
        #expect(ProjectConfigFormRules.port("99999") != nil && ProjectConfigFormRules.port("abc") != nil)
        #expect(ProjectConfigFormRules.port("") == nil && ProjectConfigFormRules.port("8080") == nil)
        #expect(ProjectConfigFormRules.name("  ") != nil && ProjectConfigFormRules.command("") != nil)
    }

    @Test func historyNamesRunnersAndKeepsUnknownStates() async {
        let (r, svc) = await make()
        svc.runnerList = [RunnerOption(id: "d_1", name: "core-oracle")]
        await r.load()
        #expect(r.runnerName("d_1") == "core-oracle" && r.runnerName("d_9") == "d_9")
        let odd = RunRecord(
            id: "x", state: "paused", configID: 1, environment: nil, runner: "d_1", startedAt: nil, stoppedAt: nil,
            stopReason: nil, error: nil)
        #expect(!odd.live)
        #expect(HistoryWords.badge(odd).0 == "Paused" && HistoryWords.badge(odd).1 == .queue)
    }
}

final class FakeInsightsDefaultEnv: ProjectInsightsService, @unchecked Sendable {
    func code(project: Int64) async throws -> [CodeInfo] { [] }
    func usage(project: Int64) async throws -> UsageInfo { UsageInfo() }
    func changes(project: Int64) async throws -> ChangesInfo { ChangesInfo() }
    func area(_ area: String, room: String?) async throws -> [KnownRecord] { [] }
    func sessionDocs() async throws -> [SessionDocItem] { [] }
    func tuning(project: Int64) async throws -> ProjectTuning {
        ProjectTuning(fetchInterval: 15, defaultEnvironment: "Staging", roomID: "room_a", roomName: "Atlas")
    }
    func setTuning(project: Int64, fetchInterval: Int?, defaultEnvironment: String?) async throws {}
    func unarchive(project: Int64) async throws {}
}
