import Foundation
import Testing

@testable import Projects

@MainActor
struct ModulePagesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func session(_ t: String, _ s: ProjectLive.Session.State, harness: String = "Codex", id: String? = nil)
        -> ProjectLive.Session
    {
        ProjectLive.Session(title: t, state: s, harness: harness, when: "1 h", branch: "ai/\(t.lowercased())", id: id)
    }

    // MARK: AI Sessions

    @Test func sessionsGroupByWhatTheyNeedInOrderAndDropEmptyGroups() {
        let all = SessionGroups.entries([
            session("Done one", .done), session("Wait", .needsYou), session("Run", .running),
            session("Done two", .done),
        ])
        let g = SessionGroups.groups(all, query: "")
        #expect(g.map(\.title) == ["Needs you", "Working", "Done this week"])
        #expect(g[2].items.map(\.session.title) == ["Done one", "Done two"])
        #expect(
            SessionGroups.groups(Array(all.filter { $0.session.state == .done }), query: "").map(\.title) == [
                "Done this week"
            ])
    }

    @Test func sessionSearchKeepsTitleToolAndBranchMatches() {
        let all = SessionGroups.entries([
            session("Fix coupon", .needsYou, harness: "Claude Code"), session("Upload images", .running),
        ])
        #expect(SessionGroups.groups(all, query: "claude").flatMap(\.items).count == 1)
        #expect(SessionGroups.groups(all, query: "ai/upload").flatMap(\.items).count == 1)
        #expect(SessionGroups.groups(all, query: "zzz").isEmpty)
    }

    // MARK: selection

    @Test func theArrowsMoveWithinTheListAndStopAtTheEnds() {
        let ids = ["a", "b", "c"]
        #expect(ModuleNav.step(ids, from: nil, by: 1) == "a")
        #expect(ModuleNav.step(ids, from: "a", by: 1) == "b")
        #expect(ModuleNav.step(ids, from: "c", by: 1) == "c")
        #expect(ModuleNav.step(ids, from: "a", by: -1) == "a")
        #expect(ModuleNav.step([], from: "a", by: 1) == nil)
    }

    @Test func aPickThatLeftTheListFallsBackToTheFirstRow() {
        #expect(ModuleNav.effective("b", in: ["a", "b"]) == "b")
        #expect(ModuleNav.effective("gone", in: ["a", "b"]) == "a")
        #expect(ModuleNav.effective(nil, in: []) == nil)
    }

    // MARK: Brain

    @Test func brainSortsDecisionsOutOfKnowledgeAndCountsEachSection() {
        func rec(_ id: String, _ kind: String) -> KnownRecord {
            KnownRecord(id: id, room: "r", roomName: "Room", kind: kind, body: "text \(id)")
        }
        let c = BrainContent(
            room: nil, rules: [rec("1", "rule")],
            knowledge: [rec("2", "decision"), rec("3", "fact"), rec("4", "Decision")])
        #expect(c.count(.rules) == 1 && c.count(.decisions) == 2 && c.count(.knowledge) == 1)
        #expect(c.count(.about) == 0 && c.count(.sources) == 0)
        #expect(c.items(.decisions, matching: "text 4").count == 1)
        #expect(c.items(.decisions, matching: "nothing").isEmpty)
    }

    // MARK: Activity

    private func run(_ id: String, _ state: String, hoursAgo: Double, error: String? = nil) -> RunRecord {
        RunRecord(
            id: id, state: state, configID: nil, environment: nil, runner: "Studio Mac",
            startedAt: now.addingTimeInterval(-hoursAgo * 3600), stoppedAt: nil, stopReason: nil, error: error)
    }

    private func repo(failed: Bool = false) -> RepoItem {
        RepoItem(
            id: 1, name: "api", remoteURL: "u", branch: "main", primary: true, fetchedAt: now.addingTimeInterval(-600),
            fetchError: failed ? "no" : nil)
    }

    @Test func activityMixesRunsCodeAndChangesNewestFirstAndFiltersByKind() {
        let changes = ChangesInfo(
            byAuthor: [],
            recent: [
                ChangeLine(who: "Codex", kind: "session", summary: "Fix rounding", at: now.addingTimeInterval(-7200)),
                ChangeLine(who: "you", kind: "commit", summary: "Bump Laravel", at: now.addingTimeInterval(-9000)),
            ])
        let e = ActivityFeed.events(
            repos: [repo()], runs: [run("1", "failed", hoursAgo: 30, error: "STRIPE_SECRET missing")], names: [:],
            changes: changes)
        #expect(e.map(\.kind) == [.code, .ai, .code, .runs])
        #expect(e.last?.title == "Start failed" && e.last?.detail == "STRIPE_SECRET missing" && e.last?.tone == .fail)
        #expect(ActivityFeed.filter(e, .code).count == 2 && ActivityFeed.filter(e, .brain).isEmpty)
        #expect(ActivityFeed.filter(e, .all).count == 4)
    }

    @Test func activityGroupsByDayWithTodayAndYesterday() {
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        let e = [
            ActivityEvent(id: "a", kind: .runs, tone: .run, title: "A", detail: "", at: noon),
            ActivityEvent(
                id: "b", kind: .runs, tone: .run, title: "B", detail: "", at: noon.addingTimeInterval(-86_400)),
            ActivityEvent(
                id: "c", kind: .runs, tone: .run, title: "C", detail: "", at: noon.addingTimeInterval(-86_400 * 5)),
        ]
        let days = ActivityFeed.days(e, now: noon, calendar: cal)
        #expect(days.map(\.title).prefix(2) == ["Today", "Yesterday"] && days.count == 3)
    }

    // MARK: Logs

    private func entry(_ id: Int, _ service: String, _ text: String) -> LogEntry {
        LogEntry(id: id, kind: .line(ProjectLive.LogLine(service: service, text: text)))
    }

    @Test func logLevelsReadWarningsAndErrors() {
        #expect(LogLevel.of("GET / 200 in 84 ms") == .info)
        #expect(LogLevel.of("Slow query: products.search 812 ms") == .warning)
        #expect(LogLevel.of("exited with code 1") == .error)
        #expect(LogLevel.of("Missing environment variable STRIPE_SECRET") == .error)
    }

    @Test func logRowsFilterByServiceAndSearchLive() {
        let rows = [entry(1, "api", "GET /a 200"), entry(2, "web", "GET / 200"), entry(3, "api", "Missing key")]
        #expect(LogView.rows(rows, service: nil, query: "").count == 3)
        #expect(LogView.rows(rows, service: "api", query: "").count == 2)
        #expect(LogView.rows(rows, service: "api", query: "missing").map(\.id) == [3])
        #expect(LogView.rows(rows, service: nil, query: "GET").count == 2)
        #expect(LogView.text(LogView.rows(rows, service: "web", query: "")) == "web GET / 200")
    }

    @Test func aGapRowOnlyShowsInTheUnfilteredLog() {
        let rows = [LogEntry(id: 1, kind: .skipped(5)), entry(2, "api", "x")]
        #expect(LogView.rows(rows, service: nil, query: "").count == 2)
        #expect(LogView.rows(rows, service: "api", query: "").count == 1)
        #expect(LogView.rows(rows, service: nil, query: "x").count == 1)
    }

    // MARK: Repos

    @Test func aBrokenRepoNamesItsReasonInTheList() {
        let broken = RepoItem(
            id: 2, name: "admin", remoteURL: "u", branch: "main", primary: false, fetchedAt: nil, fetchError: "x",
            state: "failed", reason: "not_found_or_private")
        #expect(RepoWords.broken(broken) && !RepoWords.broken(repo()))
        #expect(RepoWords.line(broken, now: now) == "main · can’t fetch · GitHub lost access")
        #expect(RepoWords.path("git@github.com:lanterna-co/api.git") == "github.com/lanterna-co/api")
        #expect(
            RepoWords.web("https://github.com/lanterna-co/api.git")?.absoluteString
                == "https://github.com/lanterna-co/api")
    }
}
