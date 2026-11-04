#if DEBUG
import Accounts
import Admin
import CoreKit
import CryptoKit
import Foundation
import Shell

/// Debug only: puts the app in a named state for the self-snapshot runner (no keys sent, nothing leaves the app).
extension AppModel {
    public static let firstRunScenes = [
        "empty", "address", "bootstrap", "typed", "qr", "claiming", "sas", "sas-approved", "waiting", "approved",
        "offline", "ratelimit",
        "mismatch",
        "unproven", "clock", "rejected", "expired", "badcode", "sasmismatch", "oldapp", "revoked", "cancelled",
    ]

    public func debugFirstRun(_ scene: String) {
        phase = .firstRun
        let sas = ClaimInfo(
            sas: "K7QD-2M9X-R4TB-0W6E", deviceID: "d_01JC4X7Q3MZ8N5V2K9RT6HBEWA",
            coreFingerprint: "9F3C1D27B804E5A652C107DE4B983A60D1F78C2E")
        let addr = "core.example.net"
        func failed(_ k: Failure.Kind) {
            firstRun.debugSet(.failed(Failure(kind: k)), endpoint: addr, code: "ABCDEFGHJK")
        }
        switch scene {
        case "empty":
            firstRun.nameText = ""
            firstRun.debugSet(.form, step: .name)
        case "address": firstRun.debugSet(.form, endpoint: addr, step: .address)
        case "bootstrap": firstRun.debugSet(.form, step: .bootstrap)
        case "typed": firstRun.debugSet(.form, endpoint: addr, code: "abcdefghjk", step: .code)
        case "qr": firstRun.debugSet(.form, code: "ainkrad-pair:v1?h=core.example.net&p=443&c=…")
        case "claiming": firstRun.debugSet(.claiming, endpoint: addr, code: "ABCDEFGHJK")
        case "sas": firstRun.debugSet(.sas, endpoint: addr, code: "ABCDEFGHJK", claim: sas)
        case "sas-approved":
            firstRun.debugSet(.sas, endpoint: addr, code: "ABCDEFGHJK", claim: sas, approverApproved: true)
        case "waiting": firstRun.debugSet(.sas, endpoint: addr, code: "ABCDEFGHJK", claim: sas, matched: true)
        case "approved": firstRun.debugSet(.approved, endpoint: "https://\(addr)", claim: sas)
        case "offline": failed(.offline("The connection was refused."))
        case "ratelimit":
            firstRun.debugSet(
                .failed(Failure(kind: .rateLimited(42))), endpoint: addr, code: "ABCDEFGHJK",
                retryAt: Date().addingTimeInterval(42))
        case "mismatch": failed(.identityMismatch)
        case "unproven": failed(.unproven)
        case "clock": failed(.clockSkew(Int64(Date().timeIntervalSince1970) + 192))
        case "rejected": failed(.rejected)
        case "expired": failed(.expired)
        case "badcode": failed(.badCode)
        case "sasmismatch": failed(.sasMismatch)
        case "oldapp": failed(.oldApp)
        case "revoked": failed(.revokedHere)
        case "cancelled": failed(.cancelledAfterApproval("d_01JC4X7Q3MZ8N5V2K9RT6HBEWA"))
        default: break
        }
    }

    /// The Touch ID sheet while asking.
    public func debugStepUp() {
        stepUp.set(.asking("Make a pairing code for iPhone."))
        shell.presentOnTop(ShellDialog(id: "step-up", dismissible: false) { StepUpSheet(model: stepUp) })
    }

    /// An inline Touch ID outcome (`cancelled`, `failed`, `nokey`) in the panel that is open.
    public func debugNotice(_ scene: String, done: String) {
        let phase: StepUpPhase =
            scene == "cancelled"
            ? .cancelled : scene == "failed" ? .failed("The Secure Enclave could not sign the request.") : .noKey
        stepUpNotice = StepUpNotice(phase: phase, done: done)
    }

    public func debugClearNotice() { stepUpNotice = nil }

    /// Opens a device's page (`name`), or the list when nil.
    public func debugDetail(named name: String?) {
        devices.detailID = name.flatMap { n in devices.items.first { $0.name == n }?.id }
    }

    /// Live: revokes a device by name (as the Devices screen does), so the list can show the one-admin warning.
    public func debugRevoke(named name: String) async {
        guard let d = devices.items.first(where: { $0.name == name }) else { return }
        _ = await devices.revoke(d)
    }

    public func debugOpenRename(named name: String) {
        guard let d = devices.items.first(where: { $0.name == name }) else { return }
        shell.present(ShellDialog(id: "rename") { RenameDialog(app: self, device: d) })
    }

    public func debugCloseStepUp() { shell.closeTopDialog() }

    /// Live: the first-run form filled and sent, as a person would.
    public func debugPair(endpoint: String, code: String) async {
        firstRun.endpointText = endpoint
        firstRun.typeCode(code)
        await firstRun.submit()
    }

    public var debugFirstRunStage: String {
        switch firstRun.stage {
        case .form: "form"
        case .claiming: "claiming"
        case .sas: firstRun.approverApproved ? "approver-approved" : "sas"
        case .approved: "approved"
        case .failed(let f): "failed: \(f.title)"
        }
    }
    public func debugConfirmMatch() async { await firstRun.confirmMatch() }
    public func debugFinishFirstRun() { firstRun.finish() }
    public var debugPhase: String { "\(phase)" }

    /// Live: the Add device dialog, filled and sent.
    public func debugOpenAddDevice() { openAddDevice() }
    public func debugCreateAddDevice(name: String) async {
        addDevice?.name = name
        await addDevice?.create()
    }
    /// The admin states on sample data (E5-07), for screenshots and clicking through. Needs no Core.
    public func debugAdminDemo() -> AdminDemo {
        AdminDemo(admin: admin) { [weak self] n in
            self?.stepUpNotice = n == nil ? nil : StepUpNotice(phase: .cancelled, done: "stored", keepsEdit: true)
        }
    }
    /// The Core app's states on sample data (E5-08), for screenshots and clicking through. Needs no Core.
    public func debugAccountsDemo() -> AccountsDemo {
        AccountsDemo(model: accounts) { [weak self] n in
            self?.stepUpNotice = n == nil ? nil : StepUpNotice(phase: .cancelled, done: "changed", keepsEdit: true)
        }
    }
    public var debugLinkIsLive: Bool { shell.coreLink == .live }
    public var debugPairingCode: String? {
        if case .code(let p)? = addDevice?.stage { return p.code }
        return nil
    }
    public var debugAddStage: String {
        switch addDevice?.stage {
        case .form?, .creating?, nil: "form"
        case .code?: "code"
        case .claimed?: "claimed"
        case .approved?: "approved"
        case .ended?: "ended"
        }
    }
    public func debugApproveAddDevice() async { await addDevice?.approve() }
    public func debugCloseDialog() { shell.closeDialog() }
    /// Snapshots: leave a first-run scene for the (sample) desktop.
    public func debugShowDesktop() { phase = .desktop }
    public func debugOpenSettings(_ id: String) {
        shell.settings.selected = id
        shell.open(.settings)
    }
    public var debugDevices: Int { devices.items.count }
    public var debugLockouts: Int { lockouts.items.count }
    public func debugReload() async { await refreshAll() }
}
#endif

/// Debug only: keys in memory, with a software step-up key so a test can elevate with no Touch ID. Release never has one: a
/// step-up key with no user verification proves nothing beyond the routine key (CoreKit refuses to make one).
public func makeDebugKeyStore() -> any KeyStore { DebugKeyStore(base: makeMemoryKeyStore()) }

private struct SoftStepUp: DeviceKey {
    let key = P256.Signing.PrivateKey()
    var storage: KeyStorage { .software }
    var spki: Data { key.publicKey.derRepresentation }
    func sign(_ message: Data) throws -> Data { try key.signature(for: message).rawRepresentation }
}

private final class DebugKeyStore: KeyStore, @unchecked Sendable {
    let base: any KeyStore
    private let lock = NSLock()
    private var stepup: SoftStepUp?
    init(base: any KeyStore) { self.base = base }

    func key(_ role: KeyRole, reason: String) throws -> (any DeviceKey)? {
        role == .stepup ? lock.withLock { stepup } : try base.key(role, reason: reason)
    }
    func generateKey(_ role: KeyRole) throws -> (any DeviceKey)? {
        guard role == .stepup else { return try base.generateKey(role) }
        let k = SoftStepUp()
        lock.withLock { stepup = k }
        return k
    }
    func deleteKey(_ role: KeyRole) throws {
        if role == .stepup { lock.withLock { stepup = nil } } else { try base.deleteKey(role) }
    }
    func loadIdentity() throws -> PairedIdentity? { try base.loadIdentity() }
    func saveIdentity(_ identity: PairedIdentity) throws { try base.saveIdentity(identity) }
    func loadPending() throws -> PendingPairing? { try base.loadPending() }
    func savePending(_ pending: PendingPairing) throws { try base.savePending(pending) }
    func clearPending() throws { try base.clearPending() }
    func wipe() throws {
        lock.withLock { stepup = nil }
        try base.wipe()
    }
}
