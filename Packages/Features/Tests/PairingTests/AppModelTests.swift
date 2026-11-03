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
        return AppModel(keyStore: store, driver: FakeDriver()) { _ in service }
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

    @Test func aCancelledTouchIDDoesNotRunTheAction() async throws {
        let s = FakeService()
        s.stepUpError = CoreError.stepUpUnavailable("Touch ID was cancelled.")
        let m = try app(s)
        await m.start()
        var ran = false
        let work = Task { @MainActor in
            do { try await m.elevated("test") { ran = true } } catch { return error is StepUpDeclined }
            return false
        }
        for _ in 0..<200 where m.stepUp.phase != .cancelled { try await Task.sleep(for: .milliseconds(5)) }
        #expect(m.stepUp.phase == .cancelled)
        m.stepUp.choose(retry: false)
        #expect(await work.value && !ran && m.shell.elevatedUntil == nil)
    }

    @Test func tryingAgainAfterACancelElevatesAndRuns() async throws {
        let s = FakeService()
        s.stepUpError = CoreError.stepUpUnavailable("Touch ID was cancelled.")
        let m = try app(s)
        await m.start()
        var ran = false
        let work = Task { @MainActor in try await m.elevated("test") { ran = true } }
        for _ in 0..<200 where m.stepUp.phase != .cancelled { try await Task.sleep(for: .milliseconds(5)) }
        s.stepUpError = nil
        m.stepUp.choose(retry: true)
        try await work.value
        #expect(ran && m.isElevated && s.stepUps == 2)
        // Already elevated: no second prompt.
        try await m.elevated("again") {}
        #expect(s.stepUps == 2)
    }

    @Test func stepUpFailuresAreToldApart() {
        #expect(StepUpPhase.from(CoreError.stepUpUnavailable("Touch ID was cancelled.")) == .cancelled)
        #expect(
            StepUpPhase.from(CoreError.stepUpUnavailable("This device has no step-up key, so it cannot elevate."))
                == .noKey)
        if case .failed = StepUpPhase.from(CoreError.keyStore("The Secure Enclave could not sign the step-up.")) {
        } else {
            Issue.record("failed")
        }
        if case .refused = StepUpPhase.from(CoreError.authFailed) {} else { Issue.record("refused") }
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
        await add.approve()
        if case .approved = add.stage {} else { Issue.record("not approved") }
    }

    @Test func aRunnerGetsExactlyRunner() {
        let add = AddDeviceModel(
            host: AppModel(keyStore: makeMemoryKeyStore(), driver: FakeDriver()) { _ in FakeService() })
        add.kind = "runner"
        #expect(add.effectiveScopes == ["runner"])
    }
}
