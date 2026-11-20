import CoreKit
import Foundation
import Testing

@testable import Admin

@MainActor
@Suite("Show, export and the Activity history")
struct RevealActivityTests {
    private func world(v010: Bool = true) async -> (AdminModel, FakeService, FakeHost) {
        let s = FakeService()
        s.v010 = v010
        s.settingList = [setting("secrets.mode", value: 1, def: 0, min: 0, max: 2, unit: "count")]
        s.secretList = [secret("e5-07-old")]
        return await makeAdmin(s)
    }

    @Test("A shown value is asked for with Touch ID, then hides itself and is gone")
    func showHidesItself() async {
        let (admin, svc, host) = await world()
        await admin.secrets.reload()
        #expect(admin.secrets.revealSupported)
        await admin.secrets.show(admin.secrets.items[0])
        #expect(admin.secrets.shown?.value == "dummy-shown-1")
        #expect(host.reasons.last?.contains("hides itself after 15 seconds") == true)
        #expect(svc.log.contains("reveal e5-07-old"))
        #expect(await until { admin.secrets.shown == nil }, "the value leaves memory when the Core's time is up")
    }

    @Test("Declining Touch ID shows nothing and asks the Core nothing")
    func declinedShowsNothing() async {
        let (admin, svc, host) = await world()
        await admin.secrets.reload()
        host.declines = true
        await admin.secrets.show(admin.secrets.items[0])
        #expect(admin.secrets.shown == nil)
        #expect(!svc.log.contains { $0.hasPrefix("reveal") })
    }

    @Test("An older Core keeps the write-only list: no Show, no Export")
    func olderCoreKeepsToday() async {
        let (admin, _, _) = await world(v010: false)
        await admin.secrets.reload()
        #expect(!admin.secrets.revealSupported)
        #expect(!admin.secrets.canShow(admin.secrets.items[0]))
    }

    @Test("A file secret is exported, never shown")
    func filesAreNotShown() async {
        let (admin, _, _) = await world()
        await admin.secrets.reload()
        let file = SecretItem(
            name: "key-file", owner: "d_me", runners: [], delivery: "file", version: 1, size: 4, keyID: "k1",
            createdAt: Date(), updatedAt: Date(), kind: "file")
        #expect(!admin.secrets.canShow(file))
    }

    @Test("The export file is JSON with the values, readable by its owner only")
    func exportFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ainkrad-secrets-test.json")
        try Data("old".utf8).write(to: url)  // a file the person chose to replace
        try SecretExport.write(
            [ExportedValue(name: "a", kind: "text", group: "Work", fileName: nil, value: "dummy-1")], to: url)
        let path = url.path
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text.contains("dummy-1") && text.contains("\"group\""))
    }

    @Test("An export asks for a fresh Touch ID, then writes where the person chose; cancelling asks nothing")
    func exportIsFresh() async throws {
        let (admin, svc, host) = await world()
        await admin.secrets.reload()
        #expect(admin.secrets.exportSupported)
        admin.secrets.chooseExportFile = { nil }
        await admin.secrets.export()
        #expect(host.forces.isEmpty && !svc.log.contains { $0.hasPrefix("export") })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        admin.secrets.chooseExportFile = { url }
        await admin.secrets.export()
        #expect(host.forces == [true])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("The export action does not wait for the reveal route")
    func exportHasItsOwnGate() async {
        let (admin, _, _) = await world(v010: false)
        await admin.secrets.reload()
        #expect(!admin.secrets.exportSupported)
    }

    @Test("The shown value never prints")
    func neverPrints() {
        let v = ShownSecret(name: "a", value: "dummy-secret", until: Date())
        #expect(!"\(v)".contains("dummy-secret") && !String(reflecting: v).contains("dummy-secret"))
        let r = RevealedValue(name: "a", kind: "text", value: "dummy-secret", hideAfter: 15)
        #expect(!"\(r)".contains("dummy-secret"))
    }

    @Test("The Core's counts become the heatmap and the kind bars")
    func statsShapeTheCharts() async {
        let (admin, svc, _) = await world()
        let day = { (d: String, n: Int) in
            AuditDayStat(
                date: d, hours: (0..<24).map { $0 == 10 ? n : 0 }, total: n, kinds: ["secrets": n, "terminals": 1],
                needsAttention: 0)
        }
        svc.statsDays = [day("2026-11-19", 4), day("2026-11-18", 2)]
        await admin.audit.reloadStats()
        #expect(admin.audit.stats.count == 2)
        let cells = ActivityStats.cells(admin.audit.stats)
        #expect(cells[0][10] == 1 && cells[1][10] == 0.5 && cells[0][0] == 0)
        #expect(ActivityStats.series(admin.audit.stats) { $0.total } == [2, 4], "oldest first")
        #expect(ActivityStats.bars(admin.audit.stats, .secrets) == [0.5, 1])
        #expect(ActivityStats.dayLabel("2026-11-19", index: 0) == "Today")
    }

    @Test("The Core's history arrives with Ops, and a Core without it leaves the charts to what this Mac sampled")
    func opsHistory() async {
        let (admin, svc, _) = await world()
        svc.metricsText = "ainkrad_uptime_seconds 5\n"
        svc.history = [
            OpsPoint(at: Date(), cpuPct: 5, memoryBytes: 1e8, diskUsedPct: 40),
            OpsPoint(at: Date(), cpuPct: 7, memoryBytes: 1.1e8, diskUsedPct: 40),
        ]
        await admin.ops.reload()
        #expect(admin.ops.coreHistory.count == 2)
        let (old, oldSvc, _) = await world(v010: false)
        oldSvc.metricsText = "ainkrad_uptime_seconds 5\n"
        oldSvc.history = svc.history
        await old.ops.reload()
        #expect(old.ops.coreHistory.isEmpty)
    }

    @Test("Ops brings the machine, the fleet and the backups, and Back up now asks the Core once")
    func hostBackupsAndFleet() async {
        let (admin, svc, _) = await world()
        svc.metricsText = "ainkrad_uptime_seconds 5\n"
        svc.host = CoreHostFacts(
            cpuPct: 20, ramUsedBytes: 8, ramTotalBytes: 16, fleet: CoreFleet(working: 1, idle: 0, offline: 1))
        svc.backupInfo = CoreBackups(schedule: "daily", history: [CoreBackupFile(at: Date(), bytes: 9)])
        await admin.ops.reload()
        #expect(admin.ops.host?.ramPct == 50 && admin.ops.host?.fleet?.offline == 1)
        #expect(admin.ops.backups?.available == true)
        await admin.ops.backUpNow()
        #expect(svc.log.contains("backup-now"))
        #expect(admin.ops.backupNote == "Backup started. It finishes by itself.")
        #expect(admin.ops.backups?.running == true, "read again after the start")
    }

    @Test("Ops brings the recent restarts, worded, and an older Core has none")
    func recentRestarts() async {
        let rows = [
            CoreRestart(id: "A", at: Date(), target: "core"),
            CoreRestart(id: "B", at: Date(), target: "runner", worked: false),
        ]
        let (admin, svc, _) = await world()
        svc.metricsText = "ainkrad_uptime_seconds 5\n"
        svc.restartRows = rows
        await admin.ops.reload()
        #expect(admin.ops.restarts.map(\.id) == ["A", "B"])
        #expect(ActivityWords.restart(rows[0]) == ("Core", "restarted on request"))
        #expect(ActivityWords.restart(rows[1]) == ("Runner", "could not be restarted"))
        let (old, oldSvc, _) = await world(v010: false)
        oldSvc.metricsText = "ainkrad_uptime_seconds 5\n"
        oldSvc.restartRows = rows
        await old.ops.reload()
        #expect(old.ops.restarts.isEmpty)
    }

    @Test("An older Core shows no host figures and no backups")
    func olderCoreHasNoHost() async {
        let (admin, svc, _) = await world(v010: false)
        svc.metricsText = "ainkrad_uptime_seconds 5\n"
        svc.host = CoreHostFacts(cpuPct: 20)
        svc.backupInfo = CoreBackups()
        await admin.ops.reload()
        #expect(admin.ops.host == nil && admin.ops.backups == nil)
    }

    @Test("The Ops words")
    func opsWords() {
        #expect(
            ActivityWords.load(10) == "Quiet" && ActivityWords.load(50) == "Busy" && ActivityWords.load(90) == "Heavy")
        #expect(ActivityWords.room(42) == "Plenty free" && ActivityWords.room(95) == "Almost full")
        #expect(ActivityWords.fleet(CoreFleet(working: 1, idle: 0, offline: 2)) == "1 working, 2 offline")
        #expect(ActivityWords.fleet(CoreFleet(working: 0, idle: 0, offline: 0)) == "No runners yet")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_795_113_600)  // 2026-11-19 18:40 UTC
        let tonight = Date(timeIntervalSince1970: 1_795_113_600 + 4 * 3600)  // 22:40 the same day
        #expect(ActivityWords.next(tonight, now: now, calendar: cal).hasPrefix("Next one tonight at"))
        #expect(
            ActivityWords.next(now.addingTimeInterval(86_400), now: now, calendar: cal).hasPrefix(
                "Next one tomorrow at"))
        #expect(ActivityWords.last(now.addingTimeInterval(-3600), now: now, calendar: cal).hasPrefix("Today"))
        #expect(ActivityWords.last(now.addingTimeInterval(-86_400), now: now, calendar: cal).hasPrefix("Yesterday"))
    }

    @Test("The stream's news is worded, and kinds that are not news are left out")
    func liveEvents() async {
        let (admin, _, _) = await world()
        admin.event(kind: "terminal.opened")
        admin.event(kind: "setting.set")
        #expect(admin.liveEvents.map(\.text) == ["A terminal opened"])
    }
}
