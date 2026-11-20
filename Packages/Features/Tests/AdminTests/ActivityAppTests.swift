import Foundation
import Testing

@testable import Admin

@MainActor
@Suite("Activity app")
struct ActivityAppTests {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func unattended(_ seq: Int64) -> AuditItem {
        var a = audit(seq, action: "agent.started")
        a.origin = AuditOrigin(kind: "schedule", reference: nil, rootKind: "schedule", rootReference: nil)
        return a
    }

    @Test("the cards count what is loaded: all, today, secrets, and rows nobody watched")
    func summary() {
        let old = AuditItem(
            seq: 1, at: Date(timeIntervalSince1970: 0), action: "secret.created", actor: .user(1), entityKind: nil,
            entityRef: nil, details: "{}")
        let rows = [old, audit(2), audit(3, action: "secret.leased"), unattended(4)]
        let now = Date(timeIntervalSince1970: 86_400 * 3)
        let s = AuditModel.summary(rows, now: now, calendar: utc)
        #expect(s == AuditSummary(total: 4, today: 0, secrets: 2, unattended: 1))
        let same = AuditModel.summary(rows, now: Date(timeIntervalSince1970: 100), calendar: utc)
        #expect(same.today == 4)
    }

    @Test("a trend needs two points in time, and counts only the rows asked for")
    func trend() {
        #expect(AuditModel.trend([audit(1)]) { _ in true }.isEmpty)
        let rows = (1...10).map { audit(Int64($0), action: $0 % 2 == 0 ? "secret.leased" : "setting.set") }
        let all = AuditModel.trend(rows, count: 4) { _ in true }
        let secrets = AuditModel.trend(rows, count: 4) { $0.action.hasPrefix("secret.") }
        #expect(all.count == 4 && secrets.count == 4)
        #expect(all.max() == 1 && secrets.max() == 1)
        #expect(AuditModel.trend(rows, count: 4) { _ in false } == [0, 0, 0, 0])
    }

    @Test("a hand-off from a connection's History opens Audit with that filter, once")
    func handoff() async {
        let (admin, _, host) = await makeAdmin()
        host.shell.settings.handoff = ["audit.kind": "connection.", "audit.target": "connection:2"]
        admin.takeHandoff()
        #expect(admin.activityTab == .audit)
        #expect(admin.audit.filter.kind == "connection." && admin.audit.filter.target == "connection:2")
        #expect(host.shell.settings.handoff.isEmpty)
        admin.activityTab = .ops
        admin.takeHandoff()
        #expect(admin.activityTab == .ops, "an empty hand-off changes nothing")
    }

    @Test("Secrets and Activity are launcher entries, and Settings keeps only Core settings and Feature switches")
    func install() async {
        let (admin, _, host) = await makeAdmin()
        admin.install()
        let ids = host.shell.launcher.entries.map(\.id)
        for id in ["secrets", "activity", "admin-ops", "admin-audit", "admin-core", "admin-switches"] {
            #expect(ids.contains(id), "\(id) is registered")
        }
        #expect(!ids.contains("admin-secrets"))
        host.shell.launcher.entry("admin-audit")?.run()
        #expect(admin.activityTab == .audit)
        #expect(host.shell.panes.contains { $0.id == "activity" })
    }

    @Test("the strip lists only what the Core reported, in order")
    func strip() async {
        let s = FakeService()
        s.metricsText = "ainkrad_runners 2\nainkrad_agent_sessions 3\nainkrad_disk_free_percent 40\n"
        let (admin, _, _) = await makeAdmin(s)
        #expect(admin.ops.strip.map(\.id) == ["ainkrad_agent_sessions", "ainkrad_runners"])
        #expect(admin.ops.strip.map(\.value) == ["3", "2"])
    }
}
