import Foundation
import Testing

@testable import Admin

@MainActor
@Suite("Audit paging and filters")
struct AuditTests {
    private func world(_ n: Int) async -> (AdminModel, FakeService) {
        let s = FakeService()
        s.auditRows = (1...n).map { audit(Int64($0), action: $0 % 2 == 0 ? "device.revoked" : "setting.set") }
        let (admin, service, _) = await makeAdmin(s)
        return (admin, service)
    }

    @Test("the first page is the newest rows; Load older continues from next_before without repeats")
    func paging() async {
        let (admin, service) = await world(120)
        let a = admin.audit!
        #expect(a.items.count == AuditModel.pageSize)
        #expect(a.items.first?.seq == 120)
        #expect(a.hasMore)
        await a.loadOlder()
        #expect(a.items.count == 100)
        #expect(Set(a.items.map(\.seq)).count == 100)
        await a.loadOlder()
        #expect(a.items.count == 120)
        #expect(!a.hasMore, "the last page has no next_before")
        #expect(service.auditQueries.map(\.before) == [nil, 71, 21])
    }

    @Test("the density counts loaded rows per slice of their span, and the kinds are the ones loaded")
    func densityAndKinds() async {
        let (admin, _) = await world(30)
        let a = admin.audit!
        let d = a.density(slices: 4)
        #expect(d != nil && d?.cells.count == 4 && d?.cells.max() == 1)
        #expect(a.knownKinds == ["device.revoked", "setting.set"])
        a.reset()
        #expect(a.density() == nil && a.knownKinds.isEmpty)
    }

    @Test("a filter reads from the top again after a moment, and only kind, target and actor can be set")
    func filtering() async {
        let (admin, service) = await world(30)
        let a = admin.audit!
        a.filter.kind = "device."
        a.filter.actor = .system
        try? await Task.sleep(for: .milliseconds(600))
        let last = service.auditQueries.last
        #expect(last?.before == nil)
        #expect(last?.filter.kind == "device.")
        #expect(last?.filter.actor == .system)
        #expect(a.items.allSatisfy { $0.action.hasPrefix("device.") })
        #expect(service.auditQueries.filter { $0.filter.kind == "device." }.count == 1, "two edits, one search")
        a.clearFilters()
        try? await Task.sleep(for: .milliseconds(600))
        #expect(a.filter.isEmpty && a.items.count == 30)
    }

    @Test("no rows and a filter is not the empty state; no rows and no filter is")
    func empty() async {
        let (admin, _) = await world(1)
        admin.audit.filter.kind = "zzz"
        try? await Task.sleep(for: .milliseconds(600))
        #expect(admin.audit.items.isEmpty)
        #expect(admin.audit.state == .ready)
        let s = FakeService()
        let (bare, _, _) = await makeAdmin(s)
        #expect(bare.audit.state == .empty)
    }

    @Test("arrow keys move the selection and stop at the ends")
    func selection() async {
        let (admin, _) = await world(5)
        let a = admin.audit!
        a.move(1)
        #expect(a.selected == 5)
        a.move(1)
        a.move(1)
        #expect(a.selected == 3)
        a.move(-1)
        a.move(-1)
        a.move(-1)
        #expect(a.selected == 5)
        #expect(a.selection?.seq == 5)
    }
}

@MainActor
@Suite("Ops and metrics")
struct OpsTests {
    static let text = """
        # HELP ainkrad_uptime_seconds Seconds since this process started.
        # TYPE ainkrad_uptime_seconds gauge
        ainkrad_uptime_seconds 3725
        # HELP ainkrad_devices_active Paired, unrevoked devices by kind.
        # TYPE ainkrad_devices_active gauge
        ainkrad_devices_active{kind="app"} 2
        ainkrad_devices_active{kind="runner"} 1
        ainkrad_disk_free_percent 37.6
        ainkrad_db_size_bytes 1048576
        ainkrad_alarm_active{alarm="backup_age"} 1
        ainkrad_alarm_active{alarm="disk_free"} 0
        not a metric line
        """

    @Test("Prometheus text parses to samples, labels and HELP; junk is skipped")
    func parse() {
        let p = PrometheusText.parse(Self.text)
        #expect(p.samples.count == 7)
        #expect(p.samples.first { $0.name == "ainkrad_uptime_seconds" }?.value == 3725)
        #expect(
            p.samples.filter { $0.name == "ainkrad_devices_active" }.map(\.labelText) == ["kind=app", "kind=runner"])
        #expect(p.help["ainkrad_uptime_seconds"] == "Seconds since this process started.")
    }

    @Test("tiles and alarms show only what the metrics name")
    func tiles() async {
        let s = FakeService()
        s.metricsText = Self.text
        let (admin, _, _) = await makeAdmin(s)
        let o = admin.ops!
        #expect(o.state == .ready)
        #expect(o.tiles.map(\.title) == ["Uptime", "Devices", "Disk free", "Database size"])
        #expect(o.tiles[0].value == "1 h 2 min")
        #expect(o.tiles[1].value == "app 2 · runner 1")
        #expect(o.tiles[2].value == "38%")
        #expect(
            o.alarms == [AlarmState(name: "backup_age", raised: true), AlarmState(name: "disk_free", raised: false)])
        #expect(o.tiles[0].help == "Seconds since this process started.")
    }

    @Test("each look adds one history point for a count-like tile, and a labelled series gets none")
    func history() async {
        let s = FakeService()
        s.metricsText = Self.text
        let (admin, _, _) = await makeAdmin(s)
        let o = admin.ops!
        await o.reload()
        #expect(o.history["ainkrad_disk_free_percent"]?.count == 2)
        #expect(o.history["ainkrad_devices_active"] == nil, "devices carry labels, so there is no single series")
    }

    @Test("an empty answer is the empty state")
    func none() async {
        let (admin, _, _) = await makeAdmin()
        #expect(admin.ops.state == .empty)
    }
}
