import Accounts
import Admin
import Agents
import Brain
import CoreKit
import CoreUI
import Foundation
import Observation
import Shell
import SwiftUI
import Terminals

/// The app's root state: first run, the desktop, or a stop that needs a person. It owns the Core connection, turns its
/// events into the status cluster, the bell and the Devices and Lockouts screens, and runs every elevated action.
@MainActor @Observable
public final class AppModel {
    enum Phase: Equatable {
        case starting, firstRun, desktop
        case blocked(Failure)
    }

    public let shell = ShellModel()
    public let agents: AgentsModel
    var phase: Phase = .starting
    private(set) var firstRun: FirstRunModel!
    private(set) var service: (any CoreService)?
    let stepUp = StepUpModel()
    /// Why the last elevated action did not run; shown inline by the panel that asked. Cleared by the next attempt.
    var stepUpNotice: StepUpNotice?
    private(set) var devices: DevicesModel!
    private(set) var lockouts: LockoutsModel!
    /// Core version, API minor and this device's scopes (`GET /me`).
    let about = AboutModel()
    private(set) var addDevice: AddDeviceModel?
    /// Terminals and runners (E5-05); nil until a Core connection exists.
    public private(set) var terminals: TerminalsModel?
    /// Core settings, Feature switches, Secrets, Audit and Ops (E5-07); its screens say "not connected" until a Core is open.
    public private(set) var admin: AdminModel!
    /// Provider accounts, pools and chains (E5-08); its screens say "not connected" until a Core is open.
    public private(set) var accounts: AccountsModel!
    /// The Brain (memory rooms and health). Core does not serve it yet: Release says so; Debug demo shows sample data.
    public private(set) var brain: BrainModel!
    private var rateLimitEnd: Task<Void, Never>?
    private var restartedEnd: Task<Void, Never>?
    var confirmForget = false

    private let keyStore: any KeyStore
    private let makeService: @MainActor (any KeyStore) throws -> any CoreService
    private let demo: Bool
    private var events: Task<Void, Never>?
    private var homeFeed: HomeFeed?
    private var retry: Task<Void, Never>?
    private var noticeIDs: [String] = []
    private var expiry: Task<Void, Never>?

    /// The app: pairing and the connection live in the Keychain. `demo` (Debug) skips both and shows the sample desktop.
    public convenience init(keyStore: any KeyStore = makeKeychainKeyStore(), demo: Bool = false, sasFile: String? = nil)
    {
        var sink: (@MainActor (String) -> Void)?
        if let path = sasFile { sink = { sas in try? sas.write(toFile: path, atomically: true, encoding: .utf8) } }
        let driver: any PairingDriver = LivePairing(pairing: DevicePairing(keyStore: keyStore))
        self.init(
            keyStore: keyStore, driver: driver, demo: demo,
            makeService: { store in LiveCoreService(connection: try CoreConnection.open(keyStore: store)) },
            sasSink: sink)
    }

    init(
        keyStore: any KeyStore, driver: any PairingDriver, demo: Bool = false,
        makeService: @escaping @MainActor (any KeyStore) throws -> any CoreService,
        sasSink: (@MainActor (String) -> Void)? = nil
    ) {
        self.agents = AgentsModel(shell: shell, notifier: SystemNotifier())
        self.keyStore = keyStore
        self.demo = demo
        self.makeService = makeService
        firstRun = FirstRunModel(driver: driver, profile: shell.profile, sasSink: sasSink) { [weak self] in
            guard let self else { return }
            Task { await self.openDesktop() }
        }
        devices = DevicesModel(host: self)
        lockouts = LockoutsModel(host: self)
        admin = AdminModel(host: AdminHostAdapter(app: self))
        accounts = AccountsModel(host: AdminHostAdapter(app: self))
        brain = BrainModel(host: AdminHostAdapter(app: self))
        shell.waitingSource = { [weak agents] in agents?.waitingOnYou ?? 0 }
        agents.onRaiseBudget = { [weak accounts] s in accounts?.raiseBudget(forAccount: s.route?.account) }
        shell.elevate = { [weak self] in
            guard let self else { return }
            Task {
                // The chip has no panel to show a notice in, so its outcome is a toast.
                if await !self.ensureElevated("Unlock admin actions on this Mac for 5 minutes.", done: "unlocked"),
                    let n = self.stepUpNotice
                {
                    self.shell.showToast(n.title)
                    self.stepUpNotice = nil
                }
            }
        }
        shell.retryConnection = { [weak self] in
            guard let self else { return }
            Task { await self.connect() }
        }
        agents.setHost(self)
        accounts.connections.notify = { [weak self] id, title, body in
            self?.agents.notifyConnections(id: id, title: title, body: body)
        }
        Registration.install(into: self)
    }

    // MARK: launch

    public func start() async {
        guard phase == .starting else { return }
        if demo {
            phase = .desktop
            shell.coreLink = .live
            #if DEBUG
            agents.attach(FakeAgentsAPI.prototypeWorld())
            brain.use(SampleBrainService())
            #endif
            return
        }
        do {
            if try keyStore.loadIdentity() != nil {
                await openDesktop()
            } else {
                phase = .firstRun
                await firstRun.resume()
            }
        } catch { phase = .blocked(Failure.from(error)) }
    }

    func openDesktop() async {
        do { service = try makeService(keyStore) } catch {
            phase = .blocked(Failure.from(error))
            return
        }
        shell.home.coreName = (try? keyStore.loadIdentity())??.endpoint.host() ?? "Home Core"
        if let live = service as? LiveCoreService {
            homeFeed = HomeFeed(shell: shell, source: LiveHomeSource(connection: live.connection))
            let model = TerminalsModel(host: TerminalHostAdapter(app: self), connection: live.connection)
            model.install()
            terminals = model
            admin.attach(connection: live.connection)
            accounts.attach(connection: live.connection)
        }
        phase = .desktop
        await connect()
    }

    /// Proves the Core and opens the session. Unreachable is a banner and a retry; anything else stops with its reason.
    func connect() async {
        guard let service else { return }
        retry?.cancel()
        shell.coreLink = .connecting
        do {
            try await service.connect()
            shell.coreLink = .live
            shell.elevatedUntil = nil
            startEvents(service)
            if let api = service.agentsAPI { agents.attach(api) }
            about.use { try await service.about() }
            let me = await about.reload()
            var admin = me?.isAdmin
            if admin == nil { admin = (try? await service.myScopes())?.contains("admin") }
            let isAdmin = admin ?? false
            agents.isAdmin = isAdmin
            showAdminPages(isAdmin)
            await refreshAll()
            await homeFeed?.refresh()
            if isAdmin { await syncPendingPairings() }
        } catch {
            let f = Failure.from(error)
            switch f.kind {
            case .offline, .unproven, .rateLimited:
                shell.coreLink = .offline
                var wait = 8.0
                if case .rateLimited(let after)? = CoreError.unwrapping(error) {
                    noteRateLimit(after)
                    wait = max(wait, after ?? 0)
                }
                retry = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(wait))
                    if !Task.isCancelled { await self?.connect() }
                }
            default:
                shell.coreLink = .none
                phase = .blocked(f)
            }
        }
    }

    /// Settings sections and launcher entries that need `admin` are out of reach of a device that does not hold it.
    static let adminOnly = ["core", "switches", "ops", "secrets", "audit", "lockouts"]
    private var stashed: [LauncherEntry] = []
    func showAdminPages(_ admin: Bool) {
        shell.settings.hidden = admin ? [] : Set(Self.adminOnly)
        if admin {
            stashed.forEach(shell.launcher.register)
            stashed = []
        } else {
            let ids = Set(Self.adminOnly.flatMap { [$0, "admin-\($0)"] })
            stashed = shell.launcher.entries.filter { ids.contains($0.id) }
            stashed.forEach { shell.launcher.unregister($0.id) }
        }
    }

    func refreshAll() async {
        await devices.reload()
        await lockouts.reload()
        terminals?.resync()
        admin.resync()
        accounts.resync()
    }

    private func startEvents(_ service: any CoreService) {
        events?.cancel()
        events = Task { [weak self] in
            for await e in service.events() {
                guard let self, !Task.isCancelled else { return }
                await self.handle(e)
            }
        }
    }

    func handle(_ e: ServiceEvent) async {
        switch e {
        case .live:
            shell.coreLink = .live
            if shell.linkNotice == .renewing {
                shell.linkNotice = nil
                shell.showToast("Session renewed. Nothing was lost.")
            }
        case .reconnecting: shell.coreLink = .reconnecting
        case .renewing:
            shell.coreLink = .reconnecting
            shell.linkNotice = .renewing
        case .rateLimited(let after):
            shell.coreLink = .reconnecting
            noteRateLimit(after)
        case .restarted:
            shell.coreLink = .live
            shell.elevatedUntil = nil
            shell.linkNotice = .restarted
            restartedEnd?.cancel()
            restartedEnd = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                if !Task.isCancelled, self?.shell.linkNotice == .restarted { self?.shell.linkNotice = nil }
            }
        case .gap:
            await refreshAll()
            await syncPendingPairings()
        case .ended(let error):
            let f = Failure.from(error)
            if case .revokedHere = f.kind { try? keyStore.wipe() }
            shell.coreLink = .none
            phase = .blocked(f)
        case .notice(let kind, let fields): accountNotice(kind, fields)
        case .event(let kind, let pairing, _):
            terminals?.event(kind: kind)
            admin.event(kind: kind)
            accounts.event(kind: kind)
            homeFeed?.event(kind: kind)
            if kind.hasPrefix("device.") || kind == "pairing.approved" { await devices.reload() }
            if kind.hasPrefix("auth.") { await lockouts.reload() }
            if kind.hasPrefix("pairing."), let pairing { await pairingEvent(kind, pairing) }
        }
    }

    // MARK: account events

    /// An account event in plain words: a bell entry (the newest 20 stay) and, for the push kinds, a macOS banner.
    /// The screens that show the account already refresh on the same event (`accounts.event`).
    public func accountNotice(_ kind: String, _ fields: [String: String]) {
        if let id = AccountNotice.clearedID(kind: kind, fields: fields) {
            shell.bell.remove(id)
            noticeIDs.removeAll { $0 == id }
            return
        }
        if let words = AccountNotice.toast(
            kind: kind, fields: fields, terminal: { [terminals] in terminals?.displayName(ofTerminal: $0) })
        {
            // Core closes a reaped terminal unless a client attaches meanwhile, so opening it is what keeps it.
            let keep = fields["terminal"].map { id in
                { @Sendable @MainActor [weak self] in _ = self?.terminals?.openTerminal(id) }
            }
            shell.showToast(words, kind: .warn, actionTitle: "Keep it", undo: keep)
            return
        }
        guard
            let n = AccountNotice.make(
                kind: kind, fields: fields, account: { [accounts] in accounts.accountName($0) },
                pool: { [accounts] in accounts.poolName($0) })
        else { return }
        shell.bell.add(BellItem(id: n.id, kind: n.isAlarm ? .alarm : .event, title: n.title, sub: n.sub, time: "now"))
        CoreAnnounce.settled("account-\(n.id)", n.title)
        noticeIDs.removeAll { $0 == n.id }
        noticeIDs.append(n.id)
        while noticeIDs.count > 20 { shell.bell.remove(noticeIDs.removeFirst()) }
        if let push = n.pushKind, let banner = n.banner {
            agents.postAccountBanner(push, n.id, banner.title, banner.body)
        }
    }

    // MARK: rate limit

    /// The Core said slow down: the banner counts the wait down, changes are paused until it ends.
    func noteRateLimit(_ after: TimeInterval?) {
        let wait = max(after ?? 30, 1)
        shell.linkNotice = .rateLimited(until: Date().addingTimeInterval(wait))
        rateLimitEnd?.cancel()
        rateLimitEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self, case .rateLimited? = self.shell.linkNotice else { return }
            self.shell.linkNotice = nil
            self.shell.showToast("Rate limit lifted. Changes are back.")
        }
    }

    // MARK: pairings

    private func pairingEvent(_ kind: String, _ id: String) async {
        await addDevice?.refreshIfCurrent(id)
        switch kind {
        case "pairing.claimed":
            guard let info = try? await service?.pairing(id) else { return }
            addJoinBell(id, info)
        case "pairing.approved", "pairing.rejected", "pairing.expired", "pairing.burned":
            shell.bell.remove("pairing-\(id)")
        default: break
        }
    }

    private func addJoinBell(_ id: String, _ info: PairingInfo) {
        shell.bell.add(  // the same id as the live path, so a claim seen twice is one item
            BellItem(
                id: "pairing-\(id)", kind: .approval, title: "\(info.name ?? "A new device") wants to join",
                sub: [DeviceWords.platform(info.platform), DeviceWords.storage(info.keyStorage)].joined(
                    separator: " · "),
                time: "now",
                actions: [BellAction("Review", primary: true) { [weak self] in self?.openAddDevice(existing: id) }]))
    }

    /// Claims that came before this app connected (or while the stream had a gap) never fired a live event: ask the Core.
    /// A device without `admin` is refused, and that is fine: it has nothing to approve.
    func syncPendingPairings() async {
        guard let list = try? await service?.pendingPairings() else { return }
        for p in list { addJoinBell(p.id, p) }
    }

    /// `quick` makes the code at once with the defaults; otherwise the form opens (advanced).
    func openAddDevice(existing id: String? = nil, quick: Bool = false) {
        guard service != nil else {
            shell.showToast("Connect to a Core first.")
            return
        }
        stepUpNotice = nil
        let model = AddDeviceModel(host: self, existing: id, quickMode: quick)
        addDevice = model
        shell.present(
            ShellDialog(
                id: "add-device",
                onClose: { [weak self] in
                    self?.addDevice = nil
                    self?.stepUpNotice = nil
                }
            ) {
                AddDeviceView(app: self, model: model, close: { [weak self] in self?.shell.closeDialog() })
            })
    }

    // MARK: elevation

    /// The Core's key fingerprint this Mac paired with, for the new device to compare against.
    var coreFingerprint: String? { (try? keyStore.loadIdentity())??.coreFingerprint }

    var isElevated: Bool { shell.elevatedUntil.map { $0 > Date() } ?? false }

    /// Touch ID, through the one sheet, shown only while the system prompt is up. True when the session is elevated (it may have
    /// been already). When it is not, `stepUpNotice` says why and the caller's panel shows it inline.
    func ensureElevated(_ reason: String, done: String, keepsEdit: Bool = true, force: Bool = false) async -> Bool {
        guard let service else { return false }
        if isElevated && !force { return true }
        stepUpNotice = nil
        stepUp.set(.asking(reason))
        shell.presentOnTop(ShellDialog(id: "step-up", dismissible: false) { StepUpSheet(model: stepUp) })
        defer { shell.closeTopDialog() }
        // Touch ID is asked in the sheet first (Apple's embedded view), so the key then signs with no system panel and the
        // full-screen Space never jumps. A miss keeps the sheet up with Try again / Cancel instead of closing it.
        guard await stepUp.confirm(reason) else {
            stepUpNotice = StepUpNotice(phase: .cancelled, done: done, keepsEdit: keepsEdit)
            return false
        }
        do {
            setElevated(try await service.stepUp(reason: reason))
            stepUp.set(.done)
            try? await Task.sleep(for: .milliseconds(450))  // the tick, before the sheet leaves
            return true
        } catch {
            let phase = StepUpPhase.from(error)
            stepUpNotice = StepUpNotice(phase: phase, done: done, keepsEdit: keepsEdit)
            if case .failed = phase {
                stepUp.set(phase)
                try? await Task.sleep(for: .milliseconds(600))  // the shake
            }
            return false
        }
    }

    private func setElevated(_ until: Date) {
        shell.elevatedUntil = until
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            guard !Task.isCancelled, let self, self.shell.elevatedUntil == until else { return }
            self.shell.elevatedUntil = nil
            self.shell.showToast("Admin actions locked again. The next one asks for Touch ID.", kind: .warn)
        }
    }

    /// Runs an action that needs elevation: Touch ID first when the session is not elevated, and once more if the Core still
    /// says `step_up_required` (the session may have been renewed). `done` names what did not happen if Touch ID does not elevate.
    func elevated<T>(
        _ reason: String, done: String, keepsEdit: Bool = true, _ op: () async throws -> T
    ) async throws -> T {
        guard await ensureElevated(reason, done: done, keepsEdit: keepsEdit) else { throw StepUpDeclined() }
        do { return try await op() } catch {
            guard case .stepUpRequired = CoreError.unwrapping(error) else { throw error }
            shell.elevatedUntil = nil
            shell.showToast("The Core answered 403 step_up_required. Asking for Touch ID, then retrying.", kind: .warn)
            guard await ensureElevated(reason, done: done, keepsEdit: keepsEdit, force: true) else {
                throw StepUpDeclined()
            }
            return try await op()
        }
    }

    // MARK: forgetting

    /// This Mac was revoked (by itself, from Devices) or the person chose to forget the Core: the keys go, first run returns.
    func forgetCore() async {
        events?.cancel()
        retry?.cancel()
        homeFeed?.stop()
        homeFeed = nil
        agents.detach()
        await service?.close()
        service = nil
        // A key that stays behind would pin the old Core again on the next launch, so a refused delete stops here.
        do { try keyStore.wipe() } catch {
            phase = .blocked(Failure.from(error))
            return
        }
        shell.elevatedUntil = nil
        shell.coreLink = .none
        shell.bell.removeAll()
        shell.dialog = nil
        shell.overlay = nil
        shell.closeAllPanes()
        terminals = nil
        admin.detach()
        accounts.detach()
        brain.detach()
        shell.linkNotice = nil
        shell.home = .empty
        shell.resetToFresh()
        firstRun.resetAll()
        phase = .firstRun
    }

    func tryAgain() async {
        phase = .desktop
        await connect()
    }

    /// Words for the toast after something went wrong.
    func say(_ error: any Error) {
        if error is StepUpDeclined { return }
        shell.showToast(CoreError.unwrapping(error)?.localizedDescription ?? error.localizedDescription)
    }
}

extension AppModel: AgentsHost {
    /// Touch ID for the agent actions: nil when elevated, else the inline words for what happened.
    public func elevate(reason: String, force: Bool) async -> InlineNotice? {
        if isElevated && !force { return nil }
        if await ensureElevated(reason, done: "done", keepsEdit: true, force: force) { return nil }
        let n = stepUpNotice
        stepUpNotice = nil
        return n.map { InlineNotice(title: $0.title, detail: $0.detail, symbol: $0.symbol, tone: $0.tone) }
            ?? InlineNotice(title: "Touch ID did not run.")
    }
}
