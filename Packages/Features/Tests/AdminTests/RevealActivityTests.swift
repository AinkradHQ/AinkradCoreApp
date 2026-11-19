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
        try SecretExport.write(
            [ExportedValue(name: "a", kind: "text", group: "Work", fileName: nil, value: "dummy-1")], directory: dir)
        let file = try #require(FileManager.default.contentsOfDirectory(atPath: dir.path).first)
        #expect(file.hasPrefix("ainkrad-secrets-") && file.hasSuffix(".json"))
        let path = dir.appendingPathComponent(file).path
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text.contains("dummy-1") && text.contains("\"group\""))
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

    @Test("The stream's news is worded, and kinds that are not news are left out")
    func liveEvents() async {
        let (admin, _, _) = await world()
        admin.event(kind: "terminal.opened")
        admin.event(kind: "setting.set")
        #expect(admin.liveEvents.map(\.text) == ["A terminal opened"])
    }
}
