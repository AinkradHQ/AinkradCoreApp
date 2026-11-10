import AppKit
import Foundation
import Testing

@testable import CoreKit
@testable import Pairing

private let fp = Wire.b64(Data(repeating: 7, count: 32))
private let secret = Wire.b64(Data(repeating: 9, count: 16))
private let good = "ainkrad://connect?host=core.example.com&fp=\(fp)&secret=\(secret)"

@MainActor
struct SetupWizardTests {
    private func wizard(
        _ d: FakeDriver = FakeDriver(), paired: @escaping @MainActor () -> Void = {}
    ) -> SetupWizardModel {
        SetupWizardModel(driver: d, onPaired: paired)
    }

    /// Runs `connect()` and waits for its task to leave `.connecting`.
    private func connect(_ m: SetupWizardModel) async {
        m.connect()
        for _ in 0..<200 where m.stage == .connecting { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func choicesLeadToTheInstallCommandOrThePasteScreen() {
        let m = wizard()
        #expect(m.stage == .choose)
        m.chooseNew()
        #expect(m.stage == .install)
        m.haveLink()
        #expect(m.stage == .connect)
        m.back()
        #expect(m.stage == .install, "back returns to where the person came from")
        m.back()
        m.chooseExisting()
        #expect(m.stage == .connect)
        m.back()
        #expect(m.stage == .choose)
    }

    @Test func theInstallCommandIsTheOneLine() {
        #expect(
            SetupWizardModel.installCommand
                == "curl -fsSL https://github.com/AinkradHQ/AinkradCore/releases/latest/download/get.sh | sudo sh")
    }

    @Test func aPastedLinkIsShownBeforeAnythingIsSent() {
        let d = FakeDriver()
        let m = wizard(d)
        m.chooseExisting()
        m.linkText = "Core is ready.\nLink: \(good)\nKeep it safe."
        #expect(m.link?.address == "core.example.com" && m.link?.coreFingerprint == fp && m.canConnect)
        #expect(d.claimedWith == nil)
        m.linkText = "https://example.com"
        #expect(m.link == nil && m.linkError != nil && !m.canConnect)
        m.linkText = "ainkrad://connect?host=core.example.com&fp=\(fp)"
        #expect(m.linkError?.contains("missing its secret") == true)
    }

    @Test func connectClaimsTheInviteAndLandsOnHome() async {
        let d = FakeDriver()
        d.approvals = [.success(.paired)]
        var landed = 0
        let m = wizard(d) { landed += 1 }
        m.chooseExisting()
        m.linkText = good
        await connect(m)
        guard case .qr(let qr)? = d.claimedWith?.0 else {
            Issue.record("not claimed with the invite")
            return
        }
        #expect(qr.host == "core.example.com" && qr.coreFingerprint == fp && d.claimedWith?.1 == nil)
        #expect(landed == 1)
    }

    @Test func aPairingThatStillWantsACheckCodeIsAFailureNotAutoConfirmed() async {
        let d = FakeDriver()  // default approvals: awaitingConfirmation, then paired
        var landed = 0
        let m = wizard(d) { landed += 1 }
        m.linkText = good
        await connect(m)
        guard case .failed = m.stage else {
            Issue.record("not failed")
            return
        }
        #expect(!d.confirmed && d.cancelled && landed == 0)
        #expect(m.linkText.isEmpty && m.link == nil, "the secret is gone")
    }

    @Test func aWrongOrUsedSecretIsSaidPlainly() async {
        let d = FakeDriver()
        d.claimResult = .failure(CoreError.pairingFailed)
        let m = wizard(d)
        m.linkText = good
        await connect(m)
        guard case .failed(let f) = m.stage else {
            Issue.record("not failed")
            return
        }
        #expect(f.kind == .badInvite && !f.fatal && f.text.contains("wrong, or it was already used"))
        #expect(m.link == nil && m.linkText.isEmpty, "a refused secret is useless, so it is dropped")
        m.tryAgain()
        #expect(m.stage == .connect)
    }

    @Test func aFingerprintMismatchIsLoudAndFatal() async {
        let d = FakeDriver()
        d.claimResult = .failure(CoreError.coreIdentityMismatch(pinned: fp, served: "other"))
        var landed = 0
        let m = wizard(d) { landed += 1 }
        m.linkText = good
        await connect(m)
        guard case .failed(let f) = m.stage else {
            Issue.record("not failed")
            return
        }
        #expect(f.kind == .identityMismatch && f.fatal && landed == 0)
        m.startOver()
        #expect(m.stage == .choose && m.linkText.isEmpty, "nothing is kept after a wrong Core")
    }

    @Test func anUnreachableHostIsOffline() async {
        let d = FakeDriver()
        d.claimResult = .failure(CoreError.offline("core.example.com did not answer."))
        let m = wizard(d)
        m.linkText = good
        await connect(m)
        guard case .failed(let f) = m.stage, case .offline = f.kind else {
            Issue.record("not offline")
            return
        }
        #expect(m.link != nil, "nothing reached the Core, so the link stays for another try")
    }

    @Test func anOpenedURLFillsThePasteScreenAndWaitsForConnect() {
        let d = FakeDriver()
        let m = wizard(d)
        m.receive(url: URL(string: good)!)
        #expect(m.stage == .connect && m.link != nil && d.claimedWith == nil)
    }

    // MARK: received links and mid-flow safety

    @Test func aLinkFromAnotherAppIsMarkedAndAPastedOneIsNot() {
        let m = wizard()
        m.receive(url: URL(string: good)!)
        #expect(m.receivedFromApp && m.link != nil)
        m.linkText = good + " "  // whitespace only: the same link, still from another app
        #expect(m.receivedFromApp)
        m.linkText = good.replacingOccurrences(of: "core.example.com", with: "evil.example.com")
        #expect(!m.receivedFromApp, "a different link is the person's own")
        m.chooseExisting()
        m.linkText = good
        #expect(!m.receivedFromApp)
    }

    @Test func aReceivedLinkIsIgnoredWhileClaiming() {
        let m = wizard()
        m.debugSet(.connecting, link: good)
        let other = "ainkrad://connect?host=evil.example.com&fp=\(fp)&secret=\(secret)"
        #expect(m.receive(url: URL(string: other)!) == false)
        #expect(m.stage == .connecting && m.link?.host == "core.example.com" && !m.receivedFromApp)
    }

    @Test func nothingIsHeldAfterAConnectOrATerminalFailure() async {
        let d = FakeDriver()
        d.approvals = [.success(.paired)]
        let m = wizard(d)
        m.receive(url: URL(string: good)!)
        await connect(m)
        #expect(m.linkText.isEmpty && m.link == nil && !m.receivedFromApp)
        let d2 = FakeDriver()
        d2.claimResult = .failure(CoreError.coreIdentityMismatch(pinned: fp, served: "x"))
        let m2 = wizard(d2)
        m2.linkText = good
        await connect(m2)
        #expect(m2.linkText.isEmpty && m2.link == nil)
    }

    private func firstRunApp(typedPast: Bool = false) throws -> AppModel {
        let m = AppModel(keyStore: makeMemoryKeyStore(), driver: FakeDriver()) { _ in FakeService() }
        m.phase = .firstRun
        if typedPast {
            m.useTypedCode = true
            m.firstRun.debugSet(.claiming, endpoint: "core.example.com", code: "ABCDEFGHJK")
        }
        return m
    }

    @Test func openURLIsRefusedOnTheDesktop() async throws {
        let m = try await pairedApp()
        m.open(url: URL(string: good)!)
        #expect(m.phase == .desktop && m.wizard.stage == .choose && m.wizard.link == nil)
    }

    @Test func openURLNeverBreaksAPairingInProgress() throws {
        let typed = try firstRunApp(typedPast: true)
        typed.open(url: URL(string: good)!)
        #expect(typed.useTypedCode && typed.wizard.link == nil, "the typed-code pairing keeps its screen")
        let claiming = try firstRunApp()
        claiming.wizard.debugSet(.connecting, link: good)
        claiming.open(url: URL(string: good)!)
        #expect(claiming.wizard.stage == .connecting)
        let fresh = try firstRunApp()
        fresh.open(url: URL(string: good)!)
        #expect(fresh.wizard.stage == .connect && fresh.wizard.receivedFromApp && !fresh.useTypedCode)
    }

    private func pairedApp(paired: Bool = true) async throws -> AppModel {
        let store = makeMemoryKeyStore()
        if paired {
            try store.saveIdentity(
                PairedIdentity(
                    deviceID: "d_me", coreFingerprint: fp, endpoint: URL(string: "https://core.example.com")!))
        }
        let m = AppModel(keyStore: store, driver: FakeDriver()) { _ in FakeService() }
        m.stepUp.check = { _, _ in }
        if paired { await m.start() }
        return m
    }

    @Test func aLinkOpenedDuringLaunchWaitsForThePhase() async throws {
        let unpaired = try await pairedApp(paired: false)
        unpaired.open(url: URL(string: good)!)
        #expect(unpaired.wizard.link == nil, "queued, not applied while starting")
        await unpaired.start()
        #expect(unpaired.phase == .firstRun && unpaired.wizard.stage == .connect && unpaired.wizard.receivedFromApp)
        let store = makeMemoryKeyStore()
        try store.saveIdentity(
            PairedIdentity(deviceID: "d_me", coreFingerprint: fp, endpoint: URL(string: "https://core.example.com")!))
        let paired = AppModel(keyStore: store, driver: FakeDriver()) { _ in FakeService() }
        paired.open(url: URL(string: good)!)
        await paired.start()
        #expect(paired.phase == .desktop && paired.wizard.link == nil && paired.wizard.linkText.isEmpty)
        #expect(paired.shell.toast != nil, "refused out loud")
    }

    @Test func aRefusedReceiveSaysSo() async throws {
        let m = try await pairedApp(paired: false)
        m.phase = .firstRun
        m.wizard.debugSet(.connecting, link: good)
        m.open(url: URL(string: good)!)
        #expect(m.shell.toast != nil)
    }
}
