import Foundation
import Testing

@testable import CoreKit
@testable import Pairing

private let fp = Wire.b64(Data(repeating: 7, count: 32))
private let secret = Wire.b64(Data(repeating: 9, count: 16))
private let good = "ainkrad://connect?host=core.example.com&fp=\(fp)&secret=\(secret)"

private final class FakeInvites: InviteService, @unchecked Sendable {
    var isAvailable = true
    var state = "live"
    private(set) var withdrawn: [String] = []
    func status(_ pairingID: String) async throws -> String { state }
    func withdraw(_ pairingID: String) async throws { withdrawn.append(pairingID) }
    func createInvite(name: String, scopes: [String]) async throws -> DeviceInvite {
        DeviceInvite(
            pairingID: "p_7", name: name, scopes: scopes,
            link: try ConnectLink(host: "core.example.com", coreFingerprint: fp, secret: Data(repeating: 1, count: 16)))
    }
}

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

    @Test func aCoreThatAsksForAConfirmationIsConfirmed() async {
        let d = FakeDriver()  // default approvals: awaitingConfirmation, then paired
        var landed = 0
        let m = wizard(d) { landed += 1 }
        m.linkText = good
        await connect(m)
        #expect(d.confirmed && landed == 1)
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
        m.tryAgain()
        #expect(m.stage == .connect && m.link != nil, "the link stays for a retry")
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
    }

    @Test func anOpenedURLFillsThePasteScreenAndWaitsForConnect() {
        let d = FakeDriver()
        let m = wizard(d)
        m.receive(url: URL(string: good)!)
        #expect(m.stage == .connect && m.link != nil && d.claimedWith == nil)
    }

    // MARK: Add device by QR

    private func app(invites: any InviteService) async throws -> AppModel {
        let store = makeMemoryKeyStore()
        try store.saveIdentity(
            PairedIdentity(deviceID: "d_me", coreFingerprint: fp, endpoint: URL(string: "https://core.example.com")!))
        let m = AppModel(keyStore: store, driver: FakeDriver()) { _ in FakeService() }
        m.stepUp.check = { _, _ in }
        m.invites = invites
        await m.start()
        m.shell.elevatedUntil = Date().addingTimeInterval(300)
        return m
    }

    @Test func theInviteQRCarriesTheSameLinkFormat() async throws {
        let m = try await app(invites: FakeInvites())
        let add = InviteDeviceModel(host: m)
        await add.quick()
        let invite = try #require(add.invite)
        #expect(invite.scopes == ["read", "approve"], "the defaults, limited to what this device holds")
        #expect(try ConnectLink.parse(invite.link.text) == invite.link)
        #expect(invite.link.text.hasPrefix("ainkrad://connect?host=core.example.com&fp="))
    }

    @Test func changingWhatADeviceMayDoDropsTheOldQR() async throws {
        let m = try await app(invites: FakeInvites())
        let add = InviteDeviceModel(host: m)
        await add.quick()
        #expect(add.invite != nil)
        add.scopes = ["read", "terminal"]
        #expect(add.invite == nil)
        await add.create()
        #expect(add.invite?.scopes == ["read", "terminal"])
        add.scopes = []
        #expect(!add.canCreate)
    }

    @Test func untilTheCoreServesInvitesAddDeviceKeepsTheTypedCodeFlow() async throws {
        let m = try await app(invites: UnavailableInviteService())
        m.openInviteDevice()
        #expect(m.shell.dialog?.id == "add-device")
        let live = try await app(invites: FakeInvites())
        live.openInviteDevice()
        #expect(live.shell.dialog?.id == "invite-device")
    }

    @Test func aClaimedInviteShowsUsedAndAWithdrawnOneEnds() async throws {
        let fake = FakeInvites()
        let m = try await app(invites: fake)
        let add = InviteDeviceModel(host: m)
        await add.quick()
        await add.refresh()
        #expect(!add.used && !add.ended)
        fake.state = "approved"
        await add.refresh()
        #expect(add.used)
        await add.create()
        #expect(!add.used, "a new code starts unused")
        await add.withdraw()
        #expect(add.ended && fake.withdrawn == ["p_7"])
    }
}
