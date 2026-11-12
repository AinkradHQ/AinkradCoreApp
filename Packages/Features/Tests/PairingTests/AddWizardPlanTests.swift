import Foundation
import Testing

@testable import CoreKit
@testable import Pairing

struct AddWizardPlanTests {
    @Test func eachKindHasItsOwnWay() {
        #expect(AddWizardPlan.steps(.phone) == [.what, .install])
        #expect(AddWizardPlan.steps(.mac) == [.what, .install, .connect, .access, .done])
        #expect(AddWizardPlan.steps(.linuxRunner) == [.what, .install, .connect, .settings, .done])
        #expect(AddWizardPlan.steps(.macRunner) == AddWizardPlan.steps(.linuxRunner))
        #expect(AddWizardPlan.next(after: .install, .mac) == .connect)
        #expect(AddWizardPlan.next(after: .connect, .mac) == .access)
        #expect(AddWizardPlan.next(after: .access, .mac) == .done)
        #expect(AddWizardPlan.next(after: .done, .mac) == nil)
        #expect(AddWizardPlan.previous(before: .connect, .linuxRunner) == .install)
        #expect(AddWizardPlan.previous(before: .what, .mac) == nil)
    }

    @Test func accessChangesOnlyWhatDiffers() {
        #expect(!AddWizardPlan.needsChange(holds: ["approve", "read"], chosen: ["read", "approve"]))
        #expect(AddWizardPlan.needsChange(holds: AccessPreset.work.scopes, chosen: AccessPreset.watch.scopes))
        #expect(!AddWizardPlan.needsChange(holds: ["read"], chosen: []), "nothing chosen never strips a device")
    }

    @Test func theConnectLinesFollowTheInvite() {
        let waiting = AddWizardWords.connectLines(invited: true, connected: nil, checked: false)
        #expect(
            waiting.map(\.text) == ["Invite created · 15 minutes", "Waiting for the new device…", "Connection checked"])
        #expect(waiting.map(\.done) == [true, false, false])
        let done = AddWizardWords.connectLines(invited: true, connected: "Azure Dev", checked: true)
        #expect(done[1].text == "Azure Dev connected" && done.allSatisfy(\.done))
    }

    @Test func onlyADeviceChoosesAccess() {
        for k in AddKind.allCases { #expect(AddWizardPlan.steps(k).contains(.access) == (!k.isRunner && k != .phone)) }
        #expect(AddKind.linuxRunner.coreKind == "runner" && AddKind.mac.coreKind == "device")
    }

    @Test func presetsMapToTheCoresScopes() {
        #expect(AccessPreset.watch.scopes == ["read", "approve"])
        #expect(AccessPreset.work.scopes == ["read", "approve", "terminal", "agent"])
        #expect(AccessPreset.full.scopes == ["read", "approve", "terminal", "agent", "admin"])
        #expect(Set(AccessPreset.full.scopes).isSubset(of: Set(ScopeText.all)))
        #expect(AccessPreset.matching(["approve", "read"]) == .watch)
        #expect(AccessPreset.matching(["read"]) == .custom)
        #expect(AccessPreset.matching(Set(AccessPreset.work.scopes)) == .work)
        #expect(AccessPreset.standard(for: .phone) == .watch && AccessPreset.standard(for: .mac) == .work)
    }

    @Test func aMacThatHoldsLessHandsOnLess() {
        let r = AddWizardPlan.narrowed(AccessPreset.full.scopes, mine: ["read", "approve", "terminal", "agent"])
        #expect(r.granted == AccessPreset.work.scopes && r.dropped == ["admin"])
        #expect(AddWizardPlan.narrowed(["read"], mine: []).granted == ["read"], "unknown means not narrowed yet")
    }

    @Test func theRunnerCommandsCarryTheCodeAndTheChoices() {
        let c = AddWizardPlan.linuxCommand(
            core: "https://core.example.com:8443", code: "ABCDE-FGHJK", terminals: true, agents: false)
        #expect(
            c
                == "sudo ./deploy/install-linux.sh --binary ./ainkrad-runner --pty --pair https://core.example.com:8443 --code ABCDE-FGHJK"
        )
        let m = AddWizardPlan.macCommands(core: "https://c", code: "ABCDE-FGHJK", terminals: true, agents: true)
        #expect(
            m == [
                "ainkrad-runner pair https://c --code ABCDE-FGHJK",
                "ainkrad-runner connect --enable-pty --enable-agents",
            ])
    }
}

@MainActor
struct AddWizardModelTests {
    private func app() async throws -> (AppModel, FakeService) {
        let store = makeMemoryKeyStore()
        try store.saveIdentity(
            PairedIdentity(
                deviceID: "d_me", coreFingerprint: String(repeating: "A", count: 43),
                endpoint: URL(string: "https://core.example.com:8443")!))
        let service = FakeService()
        let m = AppModel(keyStore: store, driver: FakeDriver()) { _ in service }
        m.stepUp.check = { _, _ in }
        await m.start()
        m.shell.elevatedUntil = Date().addingTimeInterval(300)
        return (m, service)
    }

    @Test func choosingAKindSetsItsNameAndPreset() async throws {
        let (m, _) = try await app()
        let w = AddWizardModel(app: m)
        #expect(!w.canGoNext)
        w.choose(.phone)
        #expect(w.name == "iPhone" && w.preset == .watch && w.granted == ["read", "approve"])
        w.choose(.mac)
        #expect(w.name == "Mac" && w.preset == .work)
        w.setScope("admin", true)
        #expect(w.preset == .full, "the switches add up to a preset again")
        w.setScope("terminal", false)
        #expect(w.preset == .custom)
        w.pick(.full)
        #expect(w.scopes == Set(AccessPreset.full.scopes))
    }

    @Test func aRunnerGoesThroughInstallThenAMadeCodeThatCarriesTheCoreAddress() async throws {
        let (m, _) = try await app()
        let w = AddWizardModel(app: m, kind: .linuxRunner)
        w.step = .install
        await w.next()
        #expect(w.step == .connect)
        let typed = try #require(w.typed)
        #expect(typed.kind == "runner" && typed.effectiveScopes == ["runner"])
        guard case .code = typed.stage else {
            Issue.record("no code: \(typed.stage)")
            return
        }
        #expect(w.coreURL == "https://core.example.com:8443")
        #expect(!w.canGoNext, "the flow waits for the device")
        _ = await w.requestClose()
    }

    @Test func thePhoneFlowStopsAtComingSoon() async throws {
        let (m, _) = try await app()
        let w = AddWizardModel(app: m, kind: .phone)
        w.step = .install
        #expect(!w.canGoNext)
        await w.next()
        #expect(w.step == .install)
    }
}
