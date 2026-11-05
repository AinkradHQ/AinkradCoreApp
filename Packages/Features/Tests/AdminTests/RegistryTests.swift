import CoreKit
import Foundation
import Testing

@testable import Admin

@MainActor
@Suite("Core settings and feature switches")
struct RegistryTests {
    private func world() async -> (AdminModel, FakeService, FakeHost) {
        let s = FakeService()
        s.settingList = [
            setting("api.request_burst", value: 120, def: 120, min: 10, max: 10_000, unit: "count"),
            setting(
                "api.requests_per_min", value: 600, def: 1200, min: 60, max: 60_000, unit: "per_minute",
                source: "server"),
            setting("auth.step_up_secs", value: 300, def: 300, min: 60, max: 900),
            setting("secrets.mode", value: 0, def: 0, min: 0, max: 2, unit: "count"),
            setting("auth.passkey_admin", value: 0, def: 0, min: 0, max: 1, unit: "count"),
            setting("mystery.thing", value: 5, def: 5, min: 0, max: 9, unit: "furlongs"),
        ]
        return await makeAdmin(s)
    }

    @Test("settings split into limits grouped by first word and the switches that gate a feature")
    func groups() async {
        let (admin, _, _) = await world()
        let r = admin.registry!
        #expect(r.state == .ready)
        #expect(r.groups.map(\.name) == ["api", "auth", "mystery"])
        #expect(r.groups[0].items.map(\.name) == ["request_burst", "requests_per_min"])
        #expect(r.switches.map(\.key) == ["secrets.mode", "auth.passkey_admin"])
        #expect(r.item("api.requests_per_min")?.isOverride == true)
        #expect(r.item("api.request_burst")?.isOverride == false)
    }

    @Test("an unknown unit shows its raw word, known ones their suffix")
    func units() async {
        let (admin, _, _) = await world()
        #expect(admin.registry.item("mystery.thing")?.unitLabel == "furlongs")
        #expect(admin.registry.item("auth.step_up_secs")?.unitLabel == "s")
        #expect(admin.registry.item("api.requests_per_min")?.unitLabel == "/min")
    }

    @Test("a value outside the limits is refused with its code, never clamped, and nothing is sent")
    func bounds() async {
        let (admin, service, host) = await world()
        let r = admin.registry!
        let s = r.item("auth.step_up_secs")!
        #expect(RegistryModel.check(s, "59")?.code == "out_of_bounds")
        #expect(RegistryModel.check(s, "901")?.message.contains("highest allowed, 15 min") == true)
        #expect(RegistryModel.check(s, "abc")?.code == "not_integer")
        #expect(RegistryModel.check(s, "") != nil)
        #expect(RegistryModel.check(s, " 600 ") == nil)
        r.beginEdit(s)
        r.draft = "5000"
        await r.saveEdit(s)
        #expect(r.issue?.code == "out_of_bounds")
        #expect(r.editing == "auth.step_up_secs", "the edit stays open")
        #expect(!service.log.contains { $0.hasPrefix("set ") })
        #expect(host.reasons.isEmpty, "Touch ID is not asked for a value that would be refused")
    }

    @Test("a valid edit asks for Touch ID, saves, closes the edit and offers Undo")
    func save() async {
        let (admin, service, host) = await world()
        let r = admin.registry!
        let s = r.item("auth.step_up_secs")!
        r.beginEdit(s)
        r.draft = "600"
        await r.saveEdit(s)
        #expect(service.log.contains("set auth.step_up_secs 600"))
        #expect(host.reasons.last?.contains("Touch ID unlocks for to 10 min") == true)
        #expect(r.editing == nil)
        #expect(r.item("auth.step_up_secs")?.value == 600)
        #expect(r.item("auth.step_up_secs")?.isOverride == true)
        #expect(host.shell.toast?.undo != nil)
    }

    @Test("Touch ID declined: nothing is saved and the edit is still there")
    func declined() async {
        let (admin, service, host) = await world()
        host.declines = true
        let r = admin.registry!
        let s = r.item("auth.step_up_secs")!
        r.beginEdit(s)
        r.draft = "600"
        await r.saveEdit(s)
        #expect(!service.log.contains { $0.hasPrefix("set ") })
        #expect(r.editing == "auth.step_up_secs")
        #expect(r.draft == "600")
        #expect(r.item("auth.step_up_secs")?.value == 300)
    }

    @Test("history loads on demand, newest first, and again after a change")
    func history() async {
        let (admin, service, _) = await world()
        service.historyByKey["auth.step_up_secs"] = [
            SettingChangeItem(seq: 3, at: Date(timeIntervalSince1970: 30), actor: .user(1), old: 120, new: 300),
            SettingChangeItem(seq: 9, at: Date(timeIntervalSince1970: 90), actor: .system, old: 300, new: nil),
        ]
        let r = admin.registry!
        await r.toggleHistory("auth.step_up_secs")
        guard case .ready(let list)? = r.history["auth.step_up_secs"] else {
            Issue.record("history not ready")
            return
        }
        #expect(list.map(\.seq) == [9, 3])
        #expect(r.openHistory == "auth.step_up_secs")
        await r.toggleHistory("auth.step_up_secs")
        #expect(r.openHistory == nil)
        await r.toggleHistory("auth.step_up_secs")
        let s = r.item("auth.step_up_secs")!
        r.beginEdit(s)
        r.draft = "400"
        await r.saveEdit(s)
        #expect(service.log.filter { $0 == "history auth.step_up_secs" }.count == 3, "a save reads the history again")
        #expect(SettingChangeWords.text(list[0]) == "300 → reset to default")
        #expect(SettingChangeWords.text(list[1]) == "120 → 300 (+180)")
    }

    @Test("reset is for overrides and says what comes back")
    func reset() async {
        let (admin, service, host) = await world()
        let r = admin.registry!
        await r.reset(r.item("api.requests_per_min")!)
        #expect(service.log.contains("reset api.requests_per_min"))
        #expect(r.item("api.requests_per_min")?.value == 1200)
        #expect(host.reasons.last?.contains("default, 1,200 a minute") == true)
    }

    @Test("a switch changes through Touch ID and an Undo puts it back")
    func switches() async {
        let (admin, service, host) = await world()
        let r = admin.registry!
        await r.set(r.item("secrets.mode")!, to: 1, reason: "Set secrets.mode to 1.")
        #expect(r.secretsMode == 1)
        host.shell.toast?.undo?()
        await settle()
        #expect(service.log.contains("reset secrets.mode"), "the previous value was the default, so Undo resets")
        #expect(r.secretsMode == 0)
    }

    @Test("the Core's own refusal of a value shows in the edit with its code")
    func serverRefuses() async {
        let (admin, service, _) = await world()
        let r = admin.registry!
        let s = r.item("auth.step_up_secs")!
        service.failure = AdminFailure(status: 400, code: "out_of_bounds", message: "Too far.", errorID: "e1")
        r.beginEdit(s)
        r.draft = "300"
        await r.saveEdit(s)
        #expect(r.issue?.code == "out_of_bounds")
        #expect(r.editing != nil)
    }

    @Test("changes are paused while the Core is unreachable: a toast says so and nothing is sent")
    func paused() async {
        let (admin, service, host) = await world()
        host.pausedReason = "Changes are paused while Home Core is unreachable."
        let r = admin.registry!
        await r.set(r.item("secrets.mode")!, to: 1, reason: "x")
        #expect(!service.log.contains { $0.hasPrefix("set ") })
        #expect(host.shell.toast?.message.contains("paused") == true)
    }
}

@MainActor
@Suite("Section states")
struct StateTests {
    @Test("a missing admin scope is its own state, an error carries its code and error_id")
    func states() async {
        let s = FakeService()
        s.failure = CoreError.forbiddenScope
        let (admin, _, host) = await makeAdmin(s)
        #expect(admin.secrets.state == .forbidden)
        #expect(admin.audit.state == .forbidden)
        s.failure = AdminFailure(status: 500, code: "internal", message: "Went wrong.", errorID: "err_1")
        await admin.ops.reload()
        #expect(admin.ops.state == .failed(code: "internal", message: "Went wrong.", errorID: "err_1"))
        s.failure = CoreError.rateLimited(retryAfter: 30)
        await admin.ops.reload()
        #expect(host.rateLimits.count == 1 && host.rateLimits[0] == 30)
        s.failure = nil
        s.settingList = []
        await admin.registry.reload()
        #expect(admin.registry.state == .empty)
    }

    @Test("not connected: no service, nothing loaded")
    func detached() async {
        let (admin, _, _) = await makeAdmin()
        admin.detach()
        #expect(!admin.isConnected)
        #expect(admin.registry.items.isEmpty)
    }
}
