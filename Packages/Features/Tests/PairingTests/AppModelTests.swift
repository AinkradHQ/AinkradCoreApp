import Foundation
import Shell
import Testing

@testable import CoreKit
@testable import Pairing

@MainActor
struct AppModelTests {
    private func app(_ service: FakeService, paired: Bool = true) throws -> AppModel {
        let store = makeMemoryKeyStore()
        if paired {
            try store.saveIdentity(
                PairedIdentity(
                    deviceID: "d_me", coreFingerprint: String(repeating: "A", count: 43),
                    endpoint: URL(string: "http://127.0.0.1:7700")!))
        }
        let m = AppModel(keyStore: store, driver: FakeDriver()) { _ in service }
        m.stepUp.check = { _, _ in }  // never the Mac's real Touch ID
        return m
    }

    @Test func notPairedStartsFirstRun() async throws {
        let m = try app(FakeService(), paired: false)
        await m.start()
        #expect(m.phase == .firstRun && m.service == nil)
    }

    @Test func pairedOpensTheDesktopLive() async throws {
        let s = FakeService()
        s.deviceList = [FakeService.device("d_me", "Mac")]
        let m = try app(s)
        await m.start()
        #expect(m.phase == .desktop && m.shell.coreLink == .live)
        #expect(m.devices.active.map(\.id) == ["d_me"])
    }

    @Test func unreachableShowsOfflineNotAStop() async throws {
        let s = FakeService()
        s.connectError = CoreError.offline("refused")
        let m = try app(s)
        await m.start()
        #expect(m.phase == .desktop && m.shell.coreLink == .offline)
    }

    @Test func aWrongCoreStops() async throws {
        let s = FakeService()
        s.connectError = CoreError.coreIdentityMismatch(pinned: "a", served: "b")
        let m = try app(s)
        await m.start()
        #expect(m.phase == .blocked(Failure(kind: .identityMismatch)))
    }

    @Test func revokedByEventForgetsKeys() async throws {
        let m = try app(FakeService())
        await m.start()
        await m.handle(.ended(.revoked))
        #expect(m.phase == .blocked(Failure(kind: .revokedHere)))
    }

    @Test func eventsMoveTheStatus() async throws {
        let m = try app(FakeService())
        await m.start()
        await m.handle(.reconnecting)
        #expect(m.shell.coreLink == .reconnecting)
        await m.handle(.live)
        #expect(m.shell.coreLink == .live)
    }

    @Test func aCancelledTouchIDDoesNotRunTheActionAndSaysSoInline() async throws {
        let s = FakeService()
        s.stepUpError = CoreError.stepUpCancelled
        let m = try app(s)
        await m.start()
        var ran = false
        do {
            try await m.elevated("test", done: "renamed") { ran = true }
            Issue.record("it ran")
        } catch { #expect(error is StepUpDeclined) }
        #expect(!ran && m.shell.elevatedUntil == nil && m.shell.topDialog == nil, "no modal is left behind")
        let n = try #require(m.stepUpNotice)
        #expect(n.phase == .cancelled && n.title == "Cancelled, nothing was renamed.")
        #expect(n.detail.contains("Your edit is still here"))
    }

    @Test func aFailedTouchIDReadsDifferentlyFromACancel() async throws {
        let s = FakeService()
        s.stepUpError = CoreError.keyStore("sign")
        let m = try app(s)
        await m.start()
        await #expect(throws: StepUpDeclined.self) { try await m.elevated("test", done: "revoked") {} }
        let n = try #require(m.stepUpNotice)
        #expect(n.title == "Touch ID didn't match. Nothing was revoked." && n.phase != .cancelled)
    }

    @Test func tryingAgainAfterACancelElevatesRunsAndClearsTheNotice() async throws {
        let s = FakeService()
        s.stepUpError = CoreError.stepUpCancelled
        let m = try app(s)
        await m.start()
        await #expect(throws: StepUpDeclined.self) { try await m.elevated("test", done: "changed") {} }
        s.stepUpError = nil
        var ran = false
        try await m.elevated("test", done: "changed") { ran = true }
        #expect(ran && m.isElevated && s.stepUps == 2 && m.stepUpNotice == nil)
        // Already elevated: no second prompt.
        try await m.elevated("again", done: "changed") {}
        #expect(s.stepUps == 2)
    }

    @Test func stepUpFailuresAreToldApart() {
        #expect(StepUpPhase.from(CoreError.stepUpCancelled) == .cancelled)
        #expect(
            StepUpPhase.from(CoreError.stepUpUnavailable("This device has no step-up key, so it cannot elevate."))
                == .noKey)
        if case .failed = StepUpPhase.from(CoreError.keyStore("The Secure Enclave could not sign the step-up.")) {
        } else {
            Issue.record("failed")
        }
        if case .refused = StepUpPhase.from(CoreError.authFailed) {} else { Issue.record("refused") }
    }

    @Test func theOnlyAdminWarningAndFilters() async throws {
        let s = FakeService()
        var admin = FakeService.device("d_me", "Mac", scopes: ["read", "admin"])
        admin.stepup = true
        var runner = FakeService.device("d_r", "linux-01", scopes: ["runner"])
        runner.kind = "runner"
        var odd = FakeService.device("d_x", "Odd", scopes: ["read"])
        odd.kind = "satellite"
        s.deviceList = [admin, runner, odd]
        let m = try app(s)
        await m.start()
        #expect(m.devices.onlyAdmin?.id == "d_me")
        m.devices.filter = .runners
        #expect(m.devices.shown.map(\.id) == ["d_r"])
        m.devices.filter = .devices
        #expect(m.devices.shown.map(\.id) == ["d_me"], "an unknown kind is not a device")
        m.devices.filter = .all
        #expect(m.devices.shown.count == 3 && m.devices.shown.contains { $0.kind == "satellite" })
        var second = FakeService.device("d_2", "iPhone", scopes: ["read", "admin"])
        second.stepup = true
        s.deviceList.append(second)
        await m.devices.reload()
        #expect(m.devices.onlyAdmin == nil)
    }

    @Test func renameGoesThroughElevationAndUpdatesTheList() async throws {
        let s = FakeService()
        s.deviceList = [FakeService.device("d_me", "Mac"), FakeService.device("d_2", "iPad")]
        let m = try app(s)
        await m.start()
        s.elevated = Date().addingTimeInterval(300)
        m.shell.elevatedUntil = s.elevated
        let ok = await m.devices.rename(s.deviceList[1], to: " Tablet ")
        #expect(ok && s.renamed == ["Tablet"] && m.devices.items.contains { $0.name == "Tablet" })
        #expect(m.shell.toast != nil)
        #expect(await m.devices.rename(s.deviceList[1], to: "  ") == false && m.devices.dialogError != nil)
    }

    @Test func revokingThisMacReturnsToFirstRun() async throws {
        let s = FakeService()
        s.deviceList = [FakeService.device("d_me", "Mac")]
        let m = try app(s)
        await m.start()
        m.shell.elevatedUntil = Date().addingTimeInterval(300)
        #expect(await m.devices.revoke(s.deviceList[0]))
        #expect(s.revoked == ["d_me"] && m.phase == .firstRun && m.service == nil)
    }

    @Test func scopesNeedAtLeastOne() async throws {
        let s = FakeService()
        s.deviceList = [FakeService.device("d_2", "iPad", scopes: ["read", "approve"])]
        let m = try app(s)
        await m.start()
        #expect(await m.devices.setScopes(s.deviceList[0], []) == false)
    }

    @Test func lockoutWordsAndClear() async throws {
        #expect(LockoutsModel.describe("ip:203.0.113.77") == "address 203.0.113.77")
        #expect(LockoutsModel.describe("ipdev:198.51.100.4:d_9") == "address 198.51.100.4 with device d_9")
        #expect(LockoutsModel.describe("stepup:d_9") == "Touch ID for device d_9")
        let s = FakeService()
        let m = try app(s)
        await m.start()
        m.shell.elevatedUntil = Date().addingTimeInterval(300)
        await m.lockouts.clear(LockoutInfo(key: "ip:1.2.3.4", lockedUntil: Date().addingTimeInterval(60), strikes: 1))
        #expect(s.cleared == ["ip:1.2.3.4"])
    }

    @Test func addDeviceFlowReachesTheCodeAndApproval() async throws {
        let s = FakeService()
        let m = try app(s)
        await m.start()
        m.shell.elevatedUntil = Date().addingTimeInterval(300)
        let add = AddDeviceModel(host: m)
        await add.prepare()
        #expect(add.mine == ["read", "approve", "admin"] && !add.canCreate)
        add.name = "iPhone"
        add.scopes = ["read", "admin"]
        #expect(add.canCreate)
        await add.create()
        guard case .code(let p) = add.stage else {
            Issue.record("no code")
            return
        }
        #expect(p.code == "ABCDEFGHJK")
        await add.refresh()  // the fake says: claimed
        guard case .claimed(let info) = add.stage else {
            Issue.record("not claimed")
            return
        }
        #expect(info.sas == "AAAA-BBBB-CCCC-DDDD")
        // Approving needs the check code typed from the new device's screen, every group of it.
        await add.approve()
        if case .claimed = add.stage {} else { Issue.record("approved without the typed check code") }
        add.typed = "aaaa bbbb"
        #expect(add.typed == "AAAA-BBBB" && add.groupsMatching == 2 && !add.checkMatches && !add.checkMismatch)
        add.typed = "aaaa-bbbx-"
        #expect(add.groupsMatching == 1 && add.checkMismatch)
        add.typed = "AAAA-BBBB-CCCC-DDDD-EEEE"
        #expect(add.typed == "AAAA-BBBB-CCCC-DDDD" && add.checkMatches)
        await add.approve()
        if case .approved = add.stage {} else { Issue.record("not approved") }
    }

    @Test func lockMeterMeasuresAgainstTheNextLengthUp() {
        #expect(LockMeter.total(40) == 60 && LockMeter.total(61) == 120 && LockMeter.total(3000) == 3600)
        #expect(LockMeter.total(5000) == 5000 && LockMeter.total(0) == 60)
        #expect(Countdown.text(272) == "4:32" && Countdown.text(8) == "0:08")
    }

    @Test func aRefusedScopeIsExplainedAndTakenBackNotShownAsABareError() async throws {
        let s = FakeService()
        let m = try app(s)
        await m.start()
        m.shell.elevatedUntil = Date().addingTimeInterval(300)
        let add = AddDeviceModel(host: m)
        await add.prepare()
        add.name = "iPhone"
        add.scopes = ["read", "admin"]
        s.refuseCreate = true
        await add.create()
        #expect(add.stage == .form)
        #expect(add.error?.contains("only hand on the scopes it holds") == true)
        #expect(add.error?.contains("read, approve, admin") == true)
    }

    @Test func quickAddDeviceMakesTheCodeWithTheSheetsDefaults() async throws {
        let s = FakeService()
        let m = try app(s)
        await m.start()
        m.shell.elevatedUntil = Date().addingTimeInterval(300)
        let add = AddDeviceModel(host: m, quickMode: true)
        await add.quick()
        #expect(add.name == AddDeviceModel.quickName && add.kind == "device")
        #expect(add.effectiveScopes == ["read", "approve"])
        guard case .code(let p) = add.stage else {
            Issue.record("no code")
            return
        }
        #expect(p.code == "ABCDEFGHJK" && add.error == nil)
    }

    @Test func quickAddDeviceFallsBackToTheFormWithTheReason() async throws {
        let s = FakeService()
        let m = try app(s)
        await m.start()
        m.shell.elevatedUntil = Date().addingTimeInterval(300)
        s.refuseCreate = true
        let add = AddDeviceModel(host: m, quickMode: true)
        await add.quick()
        #expect(add.stage == .form)
        #expect(add.error?.contains("only hand on the scopes it holds") == true)
    }

    @Test func addDeviceLauncherHasAQuickAndAnAdvancedEntry() async throws {
        let m = try app(FakeService())
        await m.start()
        #expect(m.shell.launcher.entry("add-device")?.isAction == true)
        #expect(m.shell.launcher.entry("add-device-advanced")?.title == "Add device (advanced)…")
    }

    @Test func aRunnerGetsExactlyRunner() {
        let add = AddDeviceModel(
            host: AppModel(keyStore: makeMemoryKeyStore(), driver: FakeDriver()) { _ in FakeService() })
        add.kind = "runner"
        #expect(add.effectiveScopes == ["runner"])
    }
}
