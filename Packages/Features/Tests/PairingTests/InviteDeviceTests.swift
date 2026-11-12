import AppKit
import Foundation
import Testing

@testable import CoreKit
@testable import Pairing

private let fp = Wire.b64(Data(repeating: 7, count: 32))

/// The Core's invite routes as they really behave: making and withdrawing (`reject`) both need a live Touch ID window, and a
/// status is about one id.
private final class FakeInvites: InviteService, @unchecked Sendable {
    var isAvailable = true
    weak var app: AppModel?
    var failWithdraw = false
    var createError: (any Error)?
    var demandStepUpOnce = false
    var withdrawDelay: Duration?
    var onCreate: (@Sendable (String) async -> Void)?
    var onWithdraw: (@Sendable (String) async -> Void)?
    private let lock = NSLock()
    private var _log: [String] = []
    private var overrides: [String: String] = [:]
    private var live: Set<String> = []
    private var spent: Set<String> = []
    private var gone: Set<String> = []
    private var held: Set<String> = []
    private var _created = 0
    var log: [String] { lock.withLock { _log } }
    var created: Int { lock.withLock { _created } }
    var withdrawn: [String] { log.filter { $0.hasPrefix("withdraw ") }.map { String($0.dropFirst(9)) } }

    func set(status: String, for id: String) { lock.withLock { overrides[id] = status } }
    /// A device claimed it: it is approved, so withdrawing it is a conflict from now on.
    func markUsed(_ id: String) {
        lock.withLock {
            live.remove(id)
            spent.insert(id)
        }
    }
    func hold(_ id: String) { lock.withLock { _ = held.insert(id) } }
    func release(_ id: String) { lock.withLock { _ = held.remove(id) } }
    private func isHeld(_ id: String) -> Bool { lock.withLock { held.contains(id) } }

    private func elevated() async -> Bool { await MainActor.run { app?.isElevated ?? false } }

    func status(_ pairingID: String) async throws -> String {
        while isHeld(pairingID) { try await Task.sleep(for: .milliseconds(5)) }
        return lock.withLock {
            let natural = live.contains(pairingID) ? "live" : spent.contains(pairingID) ? "approved" : "rejected"
            return overrides[pairingID] ?? natural
        }
    }

    /// The Core's `reject`: Touch ID window needed; live or claimed only (409 `conflict` for anything else), 404 for unknown.
    func withdraw(_ pairingID: String) async throws {
        await onWithdraw?(pairingID)
        if let d = withdrawDelay { try await Task.sleep(for: d) }
        guard await elevated() else { throw CoreError.stepUpRequired }
        if demandStepUpOnce {
            demandStepUpOnce = false
            throw CoreError.stepUpRequired
        }
        if failWithdraw { throw CoreError.offline("down") }
        try lock.withLock {
            guard live.contains(pairingID) else {
                if spent.contains(pairingID) || gone.contains(pairingID) {
                    throw CoreError.http(status: 409, code: "conflict", message: "That pairing is not pending.")
                }
                throw CoreError.http(status: 404, code: "not_found", message: "Unknown pairing.")
            }
            live.remove(pairingID)
            gone.insert(pairingID)
            _log.append("withdraw \(pairingID)")
        }
    }
    func createInvite(name: String, scopes: [String]) async throws -> DeviceInvite {
        guard await elevated() else { throw CoreError.stepUpRequired }
        let id = lock.withLock {
            _created += 1
            _log.append("create p_\(_created)")
            return "p_\(_created)"
        }
        await onCreate?(id)
        if let createError { throw createError }
        lock.withLock { _ = live.insert(id) }
        return DeviceInvite(
            pairingID: id, name: name, scopes: scopes,
            link: try ConnectLink(host: "core.example.com", coreFingerprint: fp, secret: Data(repeating: 1, count: 16)))
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

@MainActor
struct InviteDeviceTests {
    private struct Rig {
        let add: InviteDeviceModel
        let app: AppModel
        let service: FakeService
        let fake: FakeInvites
        let board: FakeBoard
    }

    private func rig(after: Duration = .seconds(60)) async throws -> Rig {
        let fake = FakeInvites()
        let store = makeMemoryKeyStore()
        try store.saveIdentity(
            PairedIdentity(deviceID: "d_me", coreFingerprint: fp, endpoint: URL(string: "https://core.example.com")!))
        let service = FakeService()
        let m = AppModel(keyStore: store, driver: FakeDriver()) { _ in service }
        m.stepUp.check = { _, _ in }
        m.invites = fake
        fake.app = m
        await m.start()
        m.shell.elevatedUntil = Date().addingTimeInterval(300)
        let board = FakeBoard()
        return Rig(
            add: InviteDeviceModel(host: m, pasteboard: board, clearAfter: after), app: m, service: service, fake: fake,
            board: board)
    }

    private func expire(_ r: Rig) { r.app.shell.elevatedUntil = Date().addingTimeInterval(-1) }

    @Test func theInviteQRCarriesTheSameLinkFormat() async throws {
        let r = try await rig()
        await r.add.prepare()
        await r.add.create()
        let invite = try #require(r.add.invite)
        #expect(invite.scopes == ["read", "approve"], "the defaults, limited to what this device holds")
        #expect(try ConnectLink.parse(invite.link.text) == invite.link)
    }

    @Test func openingTheDialogMakesNoInvite() async throws {
        let r = try await rig()
        await r.add.prepare()
        #expect(r.add.invite == nil && r.fake.created == 0)
    }

    // MARK: nothing left live

    @Test func aNewCodeIsMadeBeforeTheOldOneIsWithdrawnInTheSameElevation() async throws {
        let r = try await rig()
        await r.add.create()
        await r.add.create()
        #expect(r.fake.log == ["create p_1", "create p_2", "withdraw p_1"])
        #expect(r.add.invite?.pairingID == "p_2" && !r.add.stillLive)
    }

    @Test func aNewCodeAfterTheTouchIDWindowExpiredDoesNotLeakTheOldOne() async throws {
        let r = try await rig()
        await r.add.create()
        expire(r)
        await r.add.create()
        #expect(r.service.stepUps == 1, "one prompt covers both")
        #expect(r.fake.log == ["create p_1", "create p_2", "withdraw p_1"])
    }

    @Test func aFailedWithdrawOfTheOldOneStaysTrackedAndSaid() async throws {
        let r = try await rig()
        await r.add.create()
        r.fake.failWithdraw = true
        await r.add.create()
        #expect(r.add.invite?.pairingID == "p_2" && r.add.leftover == ["p_1"] && r.add.stillLive)
        r.fake.failWithdraw = false
        #expect(await r.add.requestClose())
        #expect(Set(r.fake.withdrawn) == ["p_1", "p_2"])
    }

    @Test func closingAfterTheWindowExpiredAsksTouchIDAndWithdraws() async throws {
        let r = try await rig()
        await r.add.create()
        expire(r)
        #expect(await r.add.requestClose())
        #expect(r.fake.withdrawn == ["p_1"] && r.service.stepUps == 1)
    }

    @Test func cancellingTouchIDOnCloseKeepsTheQRTrackedAndSaysItIsLive() async throws {
        let r = try await rig()
        await r.add.create()
        expire(r)
        r.app.stepUp.check = { _, _ in throw CancellationError() }
        // A miss keeps the Touch ID sheet up until the person presses Cancel.
        let stepUp = r.app.stepUp
        let cancel = Task {
            try? await Task.sleep(for: .milliseconds(900))
            stepUp.cancel()
        }
        #expect(await r.add.requestClose() == false)
        cancel.cancel()
        #expect(r.add.stillLive && r.add.invite?.pairingID == "p_1" && r.fake.withdrawn.isEmpty)
        r.app.stepUp.check = { _, _ in }
        #expect(await r.add.requestClose())
        #expect(r.fake.withdrawn == ["p_1"])
    }

    @Test func aCoreThatCannotBeReachedIsSaidPlainlyAndNothingIsForgotten() async throws {
        let r = try await rig()
        await r.add.create()
        r.fake.failWithdraw = true
        #expect(await r.add.requestClose() == false)
        #expect(r.add.error?.contains("still live") == true && r.add.stillLive)
        r.fake.failWithdraw = false
        #expect(await r.add.requestClose())
    }

    @Test func aSpentInviteIsNotWithdrawnOnClose() async throws {
        let r = try await rig()
        await r.add.create()
        r.fake.markUsed("p_1")
        await r.add.refresh()
        #expect(await r.add.requestClose() && r.fake.withdrawn.isEmpty)
    }

    @Test func changingTheFormWithinTheWindowWithdrawsTheOldQR() async throws {
        let r = try await rig()
        await r.add.create()
        r.add.scopes = ["read"]
        await r.add.settle()
        #expect(r.fake.withdrawn == ["p_1"] && r.add.invite == nil && !r.add.stillLive)
    }

    @Test func changingTheFormAfterTheWindowExpiredKeepsTheOldQRTrackedAndSaid() async throws {
        let r = try await rig()
        await r.add.create()
        expire(r)
        r.add.name = "iPad"
        await r.add.settle()
        #expect(r.fake.withdrawn.isEmpty && r.add.leftover == ["p_1"] && r.add.stillLive)
        #expect(await r.add.requestClose())
        #expect(r.fake.withdrawn == ["p_1"])
    }

    @Test func aStalePollAboutAnOldInviteDoesNotEndTheNewOne() async throws {
        let r = try await rig()
        await r.add.create()
        r.fake.hold("p_1")
        let poll = Task { await r.add.refresh() }
        try await Task.sleep(for: .milliseconds(30))
        await r.add.create()
        r.fake.release("p_1")
        await poll.value
        #expect(r.add.invite?.pairingID == "p_2" && r.add.live && !r.add.ended)
        await r.add.withdraw()
        #expect(r.fake.withdrawn.contains("p_2"))
    }

    @Test func closingWhileAQRIsBeingMadeWithdrawsWhatWasMade() async throws {
        let r = try await rig()
        let add = r.add
        r.fake.onCreate = { _ in _ = await add.requestClose() }
        await add.create()
        #expect(add.invite == nil && r.fake.withdrawn == ["p_1"] && !add.stillLive)
    }

    @Test func editingWhileAQRIsBeingMadeWithdrawsWhatWasMade() async throws {
        let r = try await rig()
        let add = r.add
        r.fake.onCreate = { _ in await MainActor.run { add.scopes = ["read"] } }
        await add.create()
        #expect(add.invite == nil && r.fake.withdrawn == ["p_1"])
    }

    @Test func escapeHandsALiveQRToTheBellWhereItCanBeWithdrawn() async throws {
        let r = try await rig()
        await r.add.create()
        r.add.dialogDidClose()
        #expect(r.app.leftInvites == ["p_1"] && r.app.shell.bell.items.contains { $0.id == "invite-live" })
        expire(r)
        await r.app.withdrawLeftInvites()
        #expect(r.fake.withdrawn == ["p_1"] && r.app.leftInvites.isEmpty)
        #expect(!r.app.shell.bell.items.contains { $0.id == "invite-live" })
    }

    @Test func closeAnywayAlsoHandsItOver() async throws {
        let r = try await rig()
        await r.add.create()
        r.add.abandon()
        #expect(r.app.leftInvites == ["p_1"])
    }

    // MARK: spent, gone and racing invites

    @Test func aSpentInviteIsGoneNotAnErrorOnClose() async throws {
        let r = try await rig()
        await r.add.create()
        r.fake.markUsed("p_1")  // a device claimed it; the poll has not noticed yet
        #expect(await r.add.requestClose())
        #expect(r.add.error == nil && !r.add.stillLive)
    }

    @Test func replacingAnInviteThatWasClaimedMeanwhileLeavesNothingBehind() async throws {
        let r = try await rig()
        await r.add.create()
        r.fake.markUsed("p_1")
        await r.add.create()
        #expect(r.add.leftover.isEmpty && !r.add.stillLive && r.add.invite?.pairingID == "p_2")
        #expect(await r.add.requestClose())
        #expect(r.fake.withdrawn == ["p_2"])
    }

    @Test func twoWithdrawsOfTheSameInviteDoNotResurrectIt() async throws {
        let r = try await rig()
        await r.add.create()
        r.fake.withdrawDelay = .milliseconds(60)
        r.add.scopes = ["read"]  // the quiet withdraw starts
        await r.add.create()  // and this one withdraws the same id inside its elevation
        await r.add.settle()
        #expect(r.fake.withdrawn == ["p_1"], "withdrawn once; the second attempt was a conflict")
        #expect(r.add.leftover.isEmpty && !r.add.stillLive && r.add.invite?.pairingID == "p_2")
    }

    @Test func theBellWithdrawOnASpentInviteClearsTheItem() async throws {
        let r = try await rig()
        await r.add.create()
        r.add.dialogDidClose()
        #expect(r.app.shell.bell.items.contains { $0.id == "invite-live" })
        r.fake.markUsed("p_1")
        await r.app.withdrawLeftInvites()
        #expect(r.app.leftInvites.isEmpty && !r.app.shell.bell.items.contains { $0.id == "invite-live" })
    }

    @Test func theBellItemSaysItDoesNotSurviveQuitting() async throws {
        let r = try await rig()
        await r.add.create()
        r.add.abandon()
        let item = try #require(r.app.shell.bell.items.first { $0.id == "invite-live" })
        #expect(item.sub?.contains("will not survive quitting the app") == true)
    }

    @Test func theWithdrawButtonOnASpentInviteSaysUsedNotAnError() async throws {
        let r = try await rig()
        await r.add.create()
        r.fake.markUsed("p_1")
        await r.add.withdraw()
        #expect(r.add.error == nil && r.add.used && !r.add.live)
    }

    @Test func touchIDBeingNeededIsAskedAgainNotSwallowed() async throws {
        let r = try await rig()
        await r.add.create()
        r.add.abandon()
        r.fake.demandStepUpOnce = true
        await r.app.withdrawLeftInvites()
        #expect(r.app.leftInvites.isEmpty && r.fake.withdrawn == ["p_1"] && r.service.stepUps == 1)
    }

    // MARK: closing while something is in flight

    @Test func doneDuringACreateThatFailsHandsTheOldQRToTheBell() async throws {
        let r = try await rig()
        let add = r.add
        await add.create()
        r.fake.createError = CoreError.offline("down")
        r.fake.onCreate = { _ in _ = await add.requestClose() }
        await add.create()
        #expect(r.app.leftInvites == ["p_1"] && r.app.shell.bell.items.contains { $0.id == "invite-live" })
    }

    @Test func doneWhileTouchIDIsOpenForACreateHandsTheOldQRToTheBell() async throws {
        let r = try await rig()
        let add = r.add
        await add.create()
        expire(r)
        r.app.stepUp.check = { _, _ in _ = await add.requestClose() }
        await add.create()
        #expect(r.app.leftInvites == ["p_1"] && r.fake.created == 1)
    }

    @Test func doneDuringAWithdrawThatFailsHandsTheQRToTheBell() async throws {
        let r = try await rig()
        let add = r.add
        await add.create()
        r.fake.failWithdraw = true
        r.fake.onWithdraw = { _ in _ = await add.requestClose() }
        await add.withdraw()
        #expect(r.app.leftInvites == ["p_1"])
    }

    @Test func aSecondDoneWhileTheFirstIsAskingTouchIDIsIgnored() async throws {
        let r = try await rig()
        await r.add.create()
        expire(r)
        r.app.stepUp.check = { _, _ in try? await Task.sleep(for: .milliseconds(50)) }
        async let first = r.add.requestClose()
        async let second = r.add.requestClose()
        let results = await [first, second]
        #expect(results.filter { $0 }.count == 1 && r.fake.withdrawn == ["p_1"])
    }

    @Test func theStillLiveNoticeGoesAwayOnceTheQRIsWithdrawn() async throws {
        let r = try await rig()
        await r.add.create()
        expire(r)
        r.fake.failWithdraw = true
        #expect(await r.add.requestClose() == false)
        #expect(r.add.stillLive)
        r.fake.failWithdraw = false
        await r.add.withdraw()
        #expect(!r.add.stillLive)
    }

    @Test func forgettingTheCoreForgetsTheBellsInvites() async throws {
        let r = try await rig()
        await r.add.create()
        r.add.abandon()
        await r.app.forgetCore()
        #expect(r.app.leftInvites.isEmpty)
    }

    // MARK: the copied link

    @Test func copiedLinkIsClearedWhenUsedWithdrawnOrClosedButNeverSomethingElse() async throws {
        let a = try await rig()
        await a.add.create()
        a.add.copyLink()
        #expect(a.board.text == a.add.invite?.link.text && a.add.copied)
        a.fake.markUsed("p_1")
        await a.add.refresh()
        #expect(a.board.text == nil, "used: the link is taken back")
        let b = try await rig()
        await b.add.create()
        b.add.copyLink()
        b.board.userCopies("something else")
        _ = await b.add.requestClose()
        #expect(b.board.text == "something else", "never clear what the person copied since")
        let c = try await rig()
        await c.add.create()
        c.add.copyLink()
        await c.add.withdraw()
        #expect(c.board.text == nil)
    }

    @Test func theCopiedLinkClearsItselfAfterAWhile() async throws {
        let r = try await rig(after: .milliseconds(20))
        await r.add.create()
        r.add.copyLink()
        #expect(await until { r.board.text == nil })
        #expect(!r.add.copied)
    }

    @Test func theCopiedLinkIsClearedWhenTheAppQuits() async throws {
        let r = try await rig()
        await r.add.create()
        r.add.copyLink()
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        #expect(r.board.text == nil)
        r.board.userCopies("mine")
        r.add.copyLink()
        r.board.userCopies("changed since")
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        #expect(r.board.text == "changed since")
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
