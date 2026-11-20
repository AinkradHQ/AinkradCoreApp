import Foundation
import Testing

@testable import CoreKit

struct HostFactsTests {
    @Test func theHostFactsAreReadFromTheCoreHealthAnswer() throws {
        let json = """
            {"version":"0.10.0","uptime_secs":5,"host_cpu_pct":23.5,"ram_used_bytes":8400,"ram_total_bytes":16000,
             "disk_used_bytes":212,"fleet":{"working":1,"idle":1,"offline":1,"runners":[
               {"name":"Pine","state":"working","busy_pct":64},{"name":"Cedar","state":"offline"}]}}
            """
        let f = try #require(CoreHostFacts.decode(Data(json.utf8)))
        #expect(f.cpuPct == 23.5 && f.ramPct == 53 && f.diskUsedBytes == 212)
        #expect(f.fleet?.working == 1 && f.fleet?.runners.map(\.state) == ["working", "offline"])
        #expect(f.fleet?.runners.last?.busyPct == nil)
    }

    @Test func aCoreThatSaysNothingGivesEmptyFacts() throws {
        let f = try #require(CoreHostFacts.decode(Data(#"{"version":"0.9"}"#.utf8)))
        #expect(f == CoreHostFacts() && f.ramPct == nil)
    }

    @Test func theScheduleIsWorded() {
        #expect(CoreBackups(schedule: "daily").scheduleWords == "Every day")
        #expect(CoreBackups(schedule: "*-*-* 22:00:00").scheduleWords == "Every day at 22:00")
        #expect(CoreBackups(schedule: "Mon *-*-* 03:00").scheduleWords == "Mon *-*-* 03:00")
        #expect(CoreBackups().scheduleWords == nil)
    }

    @Test func theBackupAnswerGivesTheSquaresForTheLastDays() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_795_113_600)  // 2026-11-19 18:40 UTC
        let json = """
            {"helper":"present","installed":true,"schedule":"daily","next_at":"2026-11-20T00:12:00.000Z",
             "last_run":{"result":"success","running":false,"finished_at":"2026-11-19T10:42:00.000Z"},
             "history":[{"at":"2026-11-19T10:42:00.000Z","bytes":2100},{"at":"2026-11-17T10:42:00.000Z","bytes":2000}]}
            """
        let b = try #require(CoreBackups.decode(Data(json.utf8)))
        #expect(b.available && b.history.count == 2 && b.lastResult == "success")
        #expect(b.days(7, now: now, calendar: cal) == [false, false, false, false, true, false, true])
    }

    @Test func aMissingHelperIsNotAvailable() throws {
        let b = try #require(CoreBackups.decode(Data(#"{"helper":"absent"}"#.utf8)))
        #expect(!b.available && b.history.isEmpty)
    }

    @Test func theRetentionIsReadFromTheBackupAnswersAndItsOwnRoute() throws {
        let b = try #require(CoreBackups.decode(Data(#"{"helper":"present","installed":true,"keep":14}"#.utf8)))
        #expect(b.keep == 14)
        #expect(CoreBackups.decode(Data(#"{"helper":"present"}"#.utf8))?.keep == nil)
        let r = try #require(
            CoreBackupRetention.decode(Data(#"{"helper":"present","keep":7,"min":1,"max":60}"#.utf8)))
        #expect(r.keep == 7 && r.min == 1 && r.max == 60)
        #expect(CoreBackupRetention.decode(Data(#"{"helper":"absent","min":1,"max":60}"#.utf8)) == nil)
    }

    @Test func recentRestartsJoinTheRequestWithItsOutcome() {
        let asked = """
            {"items":[
              {"at":"2026-11-19T09:15:00.000Z","details":{"target":"runner","request_id":"A1"}},
              {"at":"2026-11-18T22:10:00.000Z","details":{"target":"core","request_id":"B2"}},
              {"at":"2026-11-17T14:02:00.000Z","details":{"target":"core"}}]}
            """
        let results = """
            {"items":[{"at":"2026-11-19T09:15:01.000Z","details":{"request_id":"A1","code":"not_installed"}},
                      {"at":"2026-11-18T22:10:01.000Z","details":{"request_id":"B2","code":"accepted"}}]}
            """
        let r = CoreRestart.decode(requested: Data(asked.utf8), results: Data(results.utf8))
        #expect(r.map(\.id) == ["A1", "B2"], "a row with no request id is dropped")
        #expect(r.map(\.worked) == [false, true])
        #expect(CoreRestart.decode(requested: Data(asked.utf8), results: nil).map(\.worked) == [true, true])
        #expect(CoreRestart.decode(requested: Data("nope".utf8), results: nil).isEmpty)
    }
}
