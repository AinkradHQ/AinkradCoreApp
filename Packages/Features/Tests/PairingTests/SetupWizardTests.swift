import AppKit
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
    var failWithdraw = false
    private let lock = NSLock()
    private var _created = 0
    private var _withdrawn: [String] = []
    var created: Int { lock.withLock { _created } }
    var withdrawn: [String] { lock.withLock { _withdrawn } }
    func status(_ pairingID: String) async throws -> String { state }
    func withdraw(_ pairingID: String) async throws {
        if failWithdraw { throw CoreError.offline("down") }
        lock.withLock { _withdrawn.append(pairingID) }
    }
    func createInvite(name: String, scopes: [String]) async throws -> DeviceInvite {
        let n = lock.withLock {
            _created += 1
            return _created
        }
        return DeviceInvite(
            pairingID: "p_\(n)", name: name, scopes: scopes,
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
        await add.prepare()
        await add.create()
        let invite = try #require(add.invite)
        #expect(invite.scopes == ["read", "approve"], "the defaults, limited to what this device holds")
        #expect(try ConnectLink.parse(invite.link.text) == invite.link)
        #expect(invite.link.text.hasPrefix("ainkrad://connect?host=core.example.com&fp="))
    }

    @Test func changingWhatADeviceMayDoDropsTheOldQR() async throws {
        let m = try await app(invites: FakeInvites())
        let add = InviteDeviceModel(host: m)
        await add.prepare()
        await add.create()
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
        await add.prepare()
        await add.create()
        await add.refresh()
        #expect(!add.used && !add.ended)
        fake.state = "approved"
        await add.refresh()
        #expect(add.used)
        await add.create()
        #expect(!add.used, "a new code starts unused")
        await add.withdraw()
        #expect(add.ended && fake.withdrawn == ["p_2"])
    }

    // MARK: received links and mid-flow safety

    @Test func aLinkFromAnotherAppIsMarkedAndAPastedOneIsNot() {
        let m = wizard()
        m.receive(url: URL(string: good)!)
        #expect(m.receivedFromApp && m.link != nil)
        m.linkText = good + " "  // the person edits it: it is theirs now
        #expect(!m.receivedFromApp)
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
        let m = try await app(invites: FakeInvites())
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

    // MARK: no invite left behind

    private func inviteModel(
        _ fake: FakeInvites, _ board: FakeBoard = FakeBoard(), after: Duration = .seconds(60)
    ) async throws -> InviteDeviceModel {
        InviteDeviceModel(host: try await app(invites: fake), pasteboard: board, clearAfter: after)
    }

    @Test func openingTheDialogMakesNoInvite() async throws {
        let fake = FakeInvites()
        let add = try await inviteModel(fake)
        await add.prepare()
        #expect(add.invite == nil && fake.created == 0)
        await add.create()
        #expect(fake.created == 1)
    }

    @Test func anInviteIsWithdrawnWhenItIsReplaced() async throws {
        let fake = FakeInvites()
        let add = try await inviteModel(fake)
        await add.create()
        await add.create()
        await add.settle()
        #expect(fake.created == 2 && fake.withdrawn == ["p_1"])
    }

    @Test func anInviteIsWithdrawnWhenTheNameOrScopesChange() async throws {
        let fake = FakeInvites()
        let add = try await inviteModel(fake)
        await add.create()
        add.scopes = ["read"]
        await add.settle()
        #expect(fake.withdrawn == ["p_1"] && add.invite == nil)
        await add.create()
        add.name = "iPad"
        await add.settle()
        #expect(fake.withdrawn == ["p_1", "p_2"])
    }

    @Test func anInviteIsWithdrawnWhenTheDialogClosesButASpentOneIsNot() async throws {
        let fake = FakeInvites()
        let add = try await inviteModel(fake)
        await add.create()
        add.closed()
        await add.settle()
        #expect(fake.withdrawn == ["p_1"])
        let used = try await inviteModel(fake)
        await used.create()
        fake.state = "approved"
        await used.refresh()
        used.closed()
        await used.settle()
        #expect(fake.withdrawn == ["p_1"], "a claimed invite is a device now, not something to take back")
    }

    @Test func aFailedWithdrawNeverBlocksOrSurfaces() async throws {
        let fake = FakeInvites()
        fake.failWithdraw = true
        let add = try await inviteModel(fake)
        await add.create()
        add.closed()
        await add.settle()
        #expect(add.error == nil)
    }

    // MARK: the copied link

    @Test func copiedLinkIsClearedWhenUsedWithdrawnOrClosedButNeverSomethingElse() async throws {
        let fake = FakeInvites()
        let board = FakeBoard()
        let add = try await inviteModel(fake, board)
        await add.create()
        add.copyLink()
        #expect(board.text == add.invite?.link.text && add.copied)
        fake.state = "approved"
        await add.refresh()
        #expect(board.text == nil, "used: the link is taken back")
        let other = try await inviteModel(fake, board)
        await other.create()
        other.copyLink()
        board.userCopies("something else")
        other.closed()
        #expect(board.text == "something else", "never clear what the person copied since")
        let w = try await inviteModel(fake, board)
        await w.create()
        w.copyLink()
        await w.withdraw()
        #expect(board.text == nil)
    }

    @Test func theCopiedLinkClearsItselfAfterAWhile() async throws {
        let board = FakeBoard()
        let add = try await inviteModel(FakeInvites(), board, after: .milliseconds(20))
        await add.create()
        add.copyLink()
        try await Task.sleep(for: .milliseconds(200))
        #expect(board.text == nil && !add.copied)
    }

    @Test func theSystemPasteboardWritesConcealedAndTransientTypes() throws {
        let named = NSPasteboard(name: .init("ainkrad-test-\(UUID().uuidString)"))
        let sys = SystemLinkPasteboard(named)
        let count = sys.write(secret: "ainkrad://connect?x")
        let types = named.pasteboardItems?.first?.types ?? []
        #expect(types.contains(SystemLinkPasteboard.concealed) && types.contains(SystemLinkPasteboard.transient))
        #expect(named.string(forType: .string) == "ainkrad://connect?x" && named.changeCount == count)
        sys.clear()
        #expect(named.string(forType: .string) == nil)
        named.releaseGlobally()
    }
}

@MainActor
private final class FakeBoard: LinkPasteboard {
    private(set) var changeCount = 0
    private(set) var text: String?
    func write(secret text: String) -> Int {
        self.text = text
        changeCount += 1
        return changeCount
    }
    func userCopies(_ t: String) {
        text = t
        changeCount += 1
    }
    func clear() {
        text = nil
        changeCount += 1
    }
}
