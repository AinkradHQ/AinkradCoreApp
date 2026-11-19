import Foundation
import Testing

@testable import Projects

struct InsightsWireTests {
    @Test func codeFactsAreRead() throws {
        let c = try InsightsWire.code(
            Data(#"[{"repo":"web","files":214,"branch":"main","ahead":2,"behind":0,"last_commit":{"sha":"abc","author":"Mia","message":"Fix the timer","at":"2026-11-19T10:00:00Z"}},{"repo":"api","files":3,"branch":"dev","ahead":0,"behind":1,"last_commit":null}]"#.utf8))
        #expect(c[0].files == 214 && c[0].ahead == 2 && c[0].last?.author == "Mia" && c[0].last?.at != nil)
        #expect(c[1].last == nil && c[1].behind == 1)
        #expect(throws: RunFailure.self) { try InsightsWire.code(Data("{}".utf8)) }
    }

    @Test func usageAndTrend() throws {
        let u = try InsightsWire.usage(
            Data(#"{"week_cost":4.2,"prev_week_cost":3.75,"sessions_week":5,"by_day":[1,2,3,0,0,1,2],"sessions":[{"id":"a","title":"Fix","state":"running","cost":0.4,"spark":[1,2]},{"id":"b","title":"Done","state":"done","cost":1.1,"spark":[]}]}"#.utf8))
        #expect(u.sessionsWeek == 5 && u.byDay.count == 7 && u.running == 1)
        #expect(u.trend == "Up 12% on last week")
        #expect(UsageInfo().trend == "No usage yet")
        #expect(UsageInfo(weekCost: 1).trend == "First week with usage")
        #expect(CostWords.money(0.004) == "<$0.01" && CostWords.money(4.2) == "$4.20")
    }

    @Test func changesDocsRecordsAndTuning() throws {
        let c = try InsightsWire.changes(
            Data(#"{"by_author":[{"who":"Mia","count":14}],"recent":[{"who":"AI","kind":"session","summary":"Edited login","at":"2026-11-19T10:00:00Z"}]}"#.utf8))
        #expect(c.byAuthor.first?.count == 14 && c.recent[0].kind == "session")
        let d = try InsightsWire.docs(Data(#"[{"note":"n1","session":"as_1","path":"plan.md","title":"Plan","session_title":"Fix login","project":"7","updated_at":"2026-11-19T10:00:00Z"}]"#.utf8))
        #expect(d[0].project == "7" && d[0].sessionTitle == "Fix login")
        let r = try InsightsWire.records(Data(#"{"records":[{"id":"r1","room":"x","room_name":"Atlas notes","type":"fact","body":"Uses SwiftUI"}],"total":1,"locked_rooms":0}"#.utf8))
        #expect(ProjectKnowledge.records(r, project: " atlas NOTES ").count == 1)
        #expect(ProjectKnowledge.records(r, project: "Other").isEmpty)
        #expect(try InsightsWire.tuning(Data(#"{"id":1,"fetch_interval_minutes":60,"default_environment":"Staging"}"#.utf8)) == ProjectTuning(fetchInterval: 60, defaultEnvironment: "Staging"))
        // An older answer without the fields keeps the Core's real default.
        #expect(try InsightsWire.tuning(Data(#"{"id":1}"#.utf8)) == ProjectTuning(fetchInterval: 15, defaultEnvironment: nil))
    }

    @Test func fetchIntervalWords() {
        #expect(FetchInterval.line(0) == "only when i ask" || FetchInterval.line(0).contains("ask"))
        #expect(FetchInterval.line(60) == "every hour")
        #expect(FetchInterval.line(15) == "every 15 minutes")
    }
}

final class FakeInsights: ProjectInsightsService, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var saved: [String] = []
    var refuse = false
    func code(project: Int64) async throws -> [CodeInfo] { [] }
    func usage(project: Int64) async throws -> UsageInfo { UsageInfo(weekCost: 2) }
    func changes(project: Int64) async throws -> ChangesInfo { ChangesInfo() }
    func area(_ area: String) async throws -> [KnownRecord] {
        [KnownRecord(id: "1", roomName: "Demo", kind: "fact", body: "a"), KnownRecord(id: "2", roomName: "Else", kind: "fact", body: "b")]
    }
    func sessionDocs() async throws -> [SessionDocItem] {
        [SessionDocItem(note: "n", session: "s", path: "p.md", title: "P", sessionTitle: nil, project: "1", updatedAt: nil),
         SessionDocItem(note: "m", session: "s", path: "q.md", title: "Q", sessionTitle: nil, project: "2", updatedAt: nil)]
    }
    func tuning(project: Int64) async throws -> ProjectTuning { ProjectTuning(fetchInterval: 10, defaultEnvironment: nil) }
    func setTuning(project: Int64, fetchInterval: Int?, defaultEnvironment: String?) async throws {
        try lock.withLock {
            if refuse { throw RunFailure(sentence: "no", code: "x") }
            saved.append("\(fetchInterval ?? -1) \(defaultEnvironment ?? "-")")
        }
    }
}

@MainActor
struct ProjectInsightsModelTests {
    private func make() -> (ProjectInsightsModel, FakeInsights) {
        let m = ProjectsModel(host: FakeHost(), defaults: UserDefaults(suiteName: "ins-\(UUID())")!)
        let f = FakeInsights()
        m.insightsService = f
        let p = ProjectItem(id: 1, slug: "demo", name: "Demo", description: "", expose: false, repos: [], updatedAt: Date())
        return (ProjectInsightsModel(model: m, project: p), f)
    }

    @Test func knowledgeAndDocsAreThisProjectsOnly() async {
        let (i, _) = make()
        await i.loadKnowledge()
        await i.loadDocs()
        #expect(i.knowledge?.map(\.id) == ["1"] && i.docs?.map(\.note) == ["n"])
    }

    @Test func aTuningChangeShowsAtOnceAndRollsBackOnRefusal() async {
        let (i, f) = make()
        await i.loadTuning()
        #expect(i.tuning.fetchInterval == 10 && i.tuningLoaded)
        await i.set(fetchInterval: 60)
        #expect(i.tuning.fetchInterval == 60 && f.saved == ["60 -"])
        f.refuse = true
        await i.set(fetchInterval: 0)
        #expect(i.tuning.fetchInterval == 60)
    }

    @Test func nothingLoadsOnAnOlderCore() async {
        let (i, _) = make()
        i.model.insightsService = nil
        await i.loadUsage()
        #expect(!i.supported && i.usage == nil)
    }
}
