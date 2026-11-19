import Accounts
import Admin
import Agents
import AppKit
import Brain
import CoreKit
import CoreUI
import Design
import Foundation
import Leyline
import Lore
import Observation
import Projects
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
    /// The setup wizard is the first screen; the typed-code first run is its fallback (and a pairing left half done).
    private(set) var wizard: SetupWizardModel!
    var useTypedCode = false
    /// What follows pairing: About you, an AI account, Look and the Mac runner (E3-1), over the desktop.
    private(set) var tour: SetupTourModel!
    /// Makes device invites (QR). Unavailable until the Core serves them.
    var invites: any InviteService = UnavailableInviteService()
    /// Invites that were still live when their dialog went away; withdrawn from the bell.
    private(set) var leftInvites: [String] = []
    private(set) var service: (any CoreService)?
    let stepUp = StepUpModel()
    /// Why the last elevated action did not run; shown inline by the panel that asked. Cleared by the next attempt.
    var stepUpNotice: StepUpNotice?
    private(set) var devices: DevicesModel!
    private(set) var lockouts: LockoutsModel!
    /// The runner inside this app: "Use this Mac as a runner" (N16).
    private(set) var macRunner: MacRunnerModel!
    /// Core version, API minor and this device's scopes (`GET /me`).
    let about = AboutModel()
    private(set) var addDevice: AddDeviceModel?
    /// The typed pairing of the Add wizard, so the Core's events refresh it like the plain one.
    private(set) var wizardPairing: AddDeviceModel?
    private(set) var addWizard: AddWizardModel?
    /// Terminals and runners (E5-05); nil until a Core connection exists.
    public private(set) var terminals: TerminalsModel?
    /// Core settings, Feature switches, Secrets, Audit and Ops (E5-07); its screens say "not connected" until a Core is open.
    public private(set) var admin: AdminModel!
    /// Provider accounts, pools and chains (E5-08); its screens say "not connected" until a Core is open.
    public private(set) var accounts: AccountsModel!
    /// Projects: the gallery and the project spaces (P7); its screens say "not connected" until a Core is open.
    public private(set) var projects: ProjectsModel!
    public private(set) var leyline: LeylineModel!
    /// Design: every design by category, the library, and the Designs island of a project space (V3-03).
    public private(set) var design: DesignModel!
    /// Lore: today's note and every note on the Core (R6-01); it says "not connected" until a Core is open.
    public private(set) var lore: LoreModel!
    /// The Brain (memory rooms and import). A real Core serves it through the signed module routes; Debug demo shows sample data.
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
    /// One per terminal Core has warned about: the toast it owns and the task that keeps its words fresh until `reap_at`.
    private var reaps: [String: (toast: UUID, watch: Task<Void, Never>)] = [:]
    private var expiry: Task<Void, Never>?
    /// The app unlock (E1-1): whether this Core serves it, the heartbeat that holds it, and what watches the Mac lock and sleep.
    private var unlockSupported = false
    private var beat: Task<Void, Never>?
    private var lockWatch: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    /// Seconds between heartbeats; the Core lapses an unlock after 90 s without one.
    var beatEvery: Duration = .seconds(30)
    /// The clock and the wait the reap watch runs on; a test replaces both so no real time passes.
    var reapNow: @Sendable () -> Date = { Date() }
    var reapPause: @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }

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
        macControl: any MacRunnerControl = LiveMacRunnerControl(),
        makeService: @escaping @MainActor (any KeyStore) throws -> any CoreService,
        sasSink: (@MainActor (String) -> Void)? = nil
    ) {
        self.agents = AgentsModel(shell: shell, notifier: SystemNotifier())
        self.keyStore = keyStore
        self.demo = demo
        self.makeService = makeService
        macRunner = MacRunnerModel(
            control: demo ? NoMacRunner() : macControl,
            deps: MacRunnerDeps(
                coreURL: { [weak self] in self?.coreURL.flatMap { URL(string: $0) } },
                makeInvite: { [weak self] name in
                    guard let self else { throw CancellationError() }
                    return try await self.elevated("Add this Mac to the Core as a runner.", done: "added") {
                        try await self.invites.createRunnerInvite(name: name)
                    }
                },
                attest: { [weak self] id in
                    guard let self else { throw CancellationError() }
                    try await self.elevated(
                        "Mark this Mac's runner as its own, so it can open real shells.", done: "recorded"
                    ) {
                        try await self.invites.attestBundledRunner(id)
                    }
                },
                revoke: { [weak self] id in
                    guard let self else { return "Not connected to a Core." }
                    return await TerminalHostAdapter(app: self).revokeRunner(id)
                }))
        firstRun = FirstRunModel(driver: driver, profile: shell.profile, sasSink: sasSink) { [weak self] in
            guard let self else { return }
            Task { await self.openDesktop() }
        }
        wizard = SetupWizardModel(driver: driver, discovery: BonjourDiscovery()) { [weak self] in
            guard let self else { return }
            Task { await self.openDesktop() }
        }
        tour = SetupTourModel(macRunner: macRunner, profile: shell.profile) { [weak self] items in await self?.saveMeProfile(items) ?? false }
        wizard.armTour = { [weak self] in self?.tour.arm() }
        devices = DevicesModel(host: self)
        lockouts = LockoutsModel(host: self)
        admin = AdminModel(host: AdminHostAdapter(app: self))
        accounts = AccountsModel(host: AdminHostAdapter(app: self))
        tour.accountCount = { [weak accounts] in accounts?.accountCount ?? 0 }
        brain = BrainModel(host: AdminHostAdapter(app: self))
        projects = ProjectsModel(host: AdminHostAdapter(app: self))
        leyline = LeylineModel(host: AdminHostAdapter(app: self))
        design = DesignModel(host: AdminHostAdapter(app: self), projects: projects)
        lore = LoreModel(host: AdminHostAdapter(app: self))
        projects.openNote = { [weak lore] id in lore?.open(note: id) }
        agents.loreNotes = { [weak lore] session in lore?.sessionDocs.filter { $0.session == session }.map(\.note) ?? [] }
        agents.openNoteInLore = { [weak lore] id in lore?.open(note: id) }
        lore.openSession = { [weak agents] id in agents?.openSession(id) }
        shell.waitingSource = { [weak agents] in agents?.waitingOnYou ?? 0 }
        shell.sessionCounts = { [weak agents] in agents?.sessionCounts ?? (0, 0) }
        agents.onRaiseBudget = { [weak accounts] s in accounts?.raiseBudget(forAccount: s.route?.account) }
        shell.unlock = { [weak self] in Task { await self?.unlockApp() } }
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

    /// An `ainkrad://connect` link was opened: it fills the wizard's paste screen, and the person presses Connect.
    public func open(url: URL) {
        guard url.scheme?.lowercased() == "ainkrad" else { return }
        // A cold launch from a link: wait until `start()` knows whether this Mac is paired.
        if phase == .starting {
            pendingURL = url
            return
        }
        guard phase == .firstRun else {
            shell.showToast(
                phase == .desktop
                    ? "This Mac is already connected to a Core." : "Sort out the connection problem first.")
            return
        }
        // Never mid-flow: a typed-code pairing past its form, or a claim in progress, keeps going.
        guard !useTypedCode || firstRun.stage == .form else {
            shell.showToast("Finish or cancel the pairing in progress first.")
            return
        }
        if wizard.receive(url: url) {
            useTypedCode = false
        } else {
            shell.showToast("Wait for the connection in progress to finish first.")
        }
    }

    /// A link that arrived before launch finished; the secret in it is dropped here as soon as it is applied or refused.
    private var pendingURL: URL?
    private func applyPendingURL() {
        guard let url = pendingURL else { return }
        pendingURL = nil
        open(url: url)
    }

    /// The background collector (E9-6): once the Core is live, one sync of the Mac collectors. Does nothing offline.
    public func collectInBackground() async {
        for _ in 0..<60 where shell.coreLink != .live { try? await Task.sleep(for: .seconds(1)) }
        guard shell.coreLink == .live else { return }
        await brain.collectNow()
    }

    public func start() async {
        guard phase == .starting else { return }
        defer { applyPendingURL() }
        if demo {
            phase = .desktop
            shell.coreLink = .live
            #if DEBUG
            let world = FakeAgentsAPI.prototypeWorld()
            FakeAgentsAPI.addShowcase(to: world)  // one session with every kind of content
            agents.attach(world)
            // No Core to approve against: a demo send skips Touch ID instead of always failing.
            agents.debugDropHost()
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
                useTypedCode = firstRun.stage != .form
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
            projects.attach(connection: live.connection)
            leyline.attach(connection: live.connection)
            leyline.openTerminal = { [weak model] id in await model?.openRemote(id) }
            // The Core records host terminals when a host asks: the pane shows it and can pause it.
            leyline.markRecording = { [weak model] terminal, paused in
                model?.recording[terminal] = paused.map { PaneRecording(paused: $0) }
            }
            model.pauseRecording = { [weak self] terminal in await self?.leyline.pauseRecording(terminal: terminal) }
            // The host page's Runner card: how its runner is doing, and a way into the runner's page.
            leyline.runnerGlance = { [weak self] id in
                self?.terminals?.runnerProgress(id: id).map {
                    RunnerGlance(online: $0.online, installing: $0.installing, percent: $0.percent)
                }
            }
            leyline.openRunner = { [weak self] id in self?.terminals?.openRunners(id) }
            // Who claimed a runner invite, from the device list the Admin app keeps.
            leyline.deviceLookup = { [weak self] id in
                self?.devices.items.first { $0.id == id }.map {
                    RunnerClaimer(id: $0.id, name: $0.name, platform: $0.platform, fingerprint: $0.fingerprint)
                }
            }
            design.attach(connection: live.connection)
            lore.attach(connection: live.connection)
            // A Core without the Brain module answers 404 and the pane says "Brain is coming".
            brain.use(CoreBrainService(transport: LiveBrainTransport(connection: live.connection)))
        }
        if let live = service as? LiveCoreService { invites = LiveInviteService(service: live) }
        phase = .desktop
        tour.startIfArmed()
        await connect()
    }

    /// The setup's About you answers into the Brain's Me space (`PUT /brain/me/profile`, API minor 95). False when this Core
    /// does not have the route yet or could not be reached: the Ready page says so.
    private func saveMeProfile(_ items: [SetupProfile.Item]) async -> Bool {
        guard (brain.apiMinor ?? 0) >= SetupTourModel.profileMinor, let live = service as? LiveCoreService,
            let body = try? JSONSerialization.data(
                withJSONObject: ["items": items.map { ["key": $0.key, "body": $0.body] }])
        else { return false }
        do {
            _ = try await LiveBrainTransport(connection: live.connection).send(
                "PUT", BrainRoutes.base + "/me/profile", body: body)
            return true
        } catch { return false }
    }

    /// Proves the Core and opens the session. Unreachable is a banner and a retry; anything else stops with its reason.
    func connect() async {
        guard let service else { return }
        retry?.cancel()
        shell.coreLink = .connecting
        do {
            try await service.connect()
            shell.coreLink = .live
            shell.retryAttempt = 0
            shell.nextRetryAt = nil
            shell.elevatedUntil = nil
            startEvents(service)
            if let api = service.agentsAPI { agents.attach(api) }
            about.use { try await service.about() }
            let me = await about.reload()
            brain.apiMinor = me?.apiMinor
            var admin = me?.isAdmin
            if admin == nil { admin = (try? await service.myScopes())?.contains("admin") }
            let isAdmin = admin ?? false
            agents.isAdmin = isAdmin
            showAdminPages(isAdmin)
            await refreshAll()
            await homeFeed?.refresh()
            await startUnlock()
            if isAdmin {
                await syncPendingPairings()
                await macRunner.reconcile()
            }
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
                shell.retryAttempt += 1
                shell.retrySpan = wait
                shell.nextRetryAt = Date().addingTimeInterval(wait)
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
    static let adminOnly = ["core", "switches", "ops", "secrets", "audit", "lockouts", "mac-runner"]
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
            lore.linkUp()
            shell.retryAttempt = 0
            shell.nextRetryAt = nil
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
        case .notice(let kind, let fields):
            if kind.hasPrefix("lore.note.") {
                lore.remote(fields)
            } else if kind == "brain.inbox" {
                brain.inboxNotice(
                    unsorted: Int(fields["unsorted"] ?? "") ?? 0, newRooms: Int(fields["new_rooms"] ?? "") ?? 0)
            } else {
                accountNotice(kind, fields)
            }
        case .toolInstall(let fields):
            terminals?.toolInstall(fields)
            accounts.toolInstall(fields)
        case .event(let kind, let pairing, _):
            terminals?.event(kind: kind)
            admin.event(kind: kind)
            accounts.event(kind: kind)
            projects.event(kind: kind)
            leyline.event(kind: kind)
            design.event(kind: kind)
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
        if kind == "terminal.reap_warning" {
            reapWarning(fields)
            return
        }
        if kind == "terminal.attached" || kind == "terminal.closed" {
            if let id = fields["terminal"] { clearReap(id) }
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

    // MARK: reap warning

    /// Core closes the terminal at `reap_at` unless a client attaches. The toast and a bell entry both stay until then, until
    /// the terminal is attached or closed, or until "Keep it" (opening the terminal is what keeps it).
    private func reapWarning(_ f: [String: String]) {
        let tid = f["terminal"] ?? "unknown"
        clearReap(tid)
        let at = AccountNotice.reapAt(f, now: reapNow())
        let toastID = UUID()
        let keep: @Sendable @MainActor () -> Void = { [weak self] in
            self?.clearReap(tid)
            if tid != "unknown" { _ = self?.terminals?.openTerminal(tid) }
        }
        func show(first: Bool = false) {
            let now = reapNow()
            let words = AccountNotice.toast(
                kind: "terminal.reap_warning", fields: f,
                terminal: { [terminals] in terminals?.displayName(ofTerminal: $0) },
                now: now)
            guard let words else { return }
            let name = f["terminal"].flatMap { terminals?.displayName(ofTerminal: $0) } ?? "A terminal"
            // After the first showing only the words move; a toast somebody dismissed or another replaced is left alone.
            if first ? true : shell.toast?.id == toastID {
                shell.showToast(
                    words, kind: .warn, actionTitle: "Keep it", id: toastID,
                    lifetime: max(7, at.timeIntervalSince(now)),
                    undo: keep)
            }
            shell.bell.add(
                BellItem(
                    id: "reap-\(tid)", kind: .alarm, title: "\(name) will close soon",
                    sub: "\(AccountNotice.closesIn(at, now: now)). Open it to keep it.", time: "now",
                    actions: [BellAction("Keep it", primary: true) { keep() }]))
        }
        show(first: true)
        reaps[tid] = (
            toastID,
            Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    // A `reap_at` that is already past (or passes while waiting) clears the entry; it never lingers.
                    let left = at.timeIntervalSince(self.reapNow())
                    if left <= 0 {
                        self.clearReap(tid)
                        return
                    }
                    await self.reapPause(min(15, left))
                    guard !Task.isCancelled, at.timeIntervalSince(self.reapNow()) > 0 else { continue }
                    show()
                }
            }
        )
    }

    private func clearReap(_ tid: String) {
        guard let r = reaps.removeValue(forKey: tid) else { return }
        r.watch.cancel()
        shell.bell.remove("reap-\(tid)")
        if shell.toast?.id == r.toast { shell.toast = nil }
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
        await wizardPairing?.refreshIfCurrent(id)
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
                sub: [DeviceWords.platform(info.platform), DeviceWords.keyNote(info.keyStorage)].joined(
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
    /// `admin` opens the form with the admin scopes already chosen (read, approve, admin).
    func openAddDevice(existing id: String? = nil, quick: Bool = false, admin: Bool = false) {
        guard service != nil else {
            shell.showToast("Connect to a Core first.")
            return
        }
        stepUpNotice = nil
        let model = AddDeviceModel(host: self, existing: id, quickMode: quick)
        if admin { model.scopes = ["read", "approve", "admin"] }
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

    /// Add a device or a runner: one guided flow (N17). `kind` skips the first screen (a runner's own Add button).
    func openAddWizard(kind: AddKind? = nil) {
        guard service != nil else {
            shell.showToast("Connect to a Core first.")
            return
        }
        stepUpNotice = nil
        let model = AddWizardModel(app: self, kind: kind)
        if kind != nil { model.step = .install }
        addWizard = model
        shell.present(
            ShellDialog(
                id: "add-wizard",
                onClose: { [weak self, weak model] in
                    self?.stepUpNotice = nil
                    model?.dialogDidClose()
                    self?.addWizard = nil
                }
            ) {
                AddWizardView(app: self, model: model, close: { [weak self] in self?.shell.closeDialog() })
            })
    }

    /// Add a runner (mockup 13): This Mac, another Mac, a server over SSH, or a server by command.
    func openAddRunner() {
        guard service != nil else {
            shell.showToast("Connect to a Core first.")
            return
        }
        stepUpNotice = nil
        let model = AddRunnerModel(app: self)
        shell.present(
            ShellDialog(
                id: "add-runner",
                onClose: { [weak self, weak model] in
                    self?.stepUpNotice = nil
                    Task { _ = await model?.requestClose() }
                }
            ) {
                AddRunnerView(app: self, model: model, close: { [weak self] in self?.shell.closeDialog() })
            })
    }

    func watch(typed m: AddDeviceModel) { wizardPairing = m }
    func unwatch(typed m: AddDeviceModel?) { if wizardPairing === m { wizardPairing = nil } }

    /// The runner's no-op test, in words.
    func testRunner(_ id: String) async -> String { await terminals?.test(runner: id) ?? "Not connected to a Core." }

    /// Add device, the QR way. Falls back to the typed-code quick flow while the Core cannot make invites.
    func openInviteDevice() {
        guard service != nil else {
            shell.showToast("Connect to a Core first.")
            return
        }
        guard invites.isAvailable else { return openAddDevice(quick: true) }
        stepUpNotice = nil
        let model = InviteDeviceModel(host: self)
        shell.present(
            ShellDialog(
                id: "invite-device",
                onClose: { [weak self, weak model] in
                    self?.stepUpNotice = nil
                    model?.dialogDidClose()
                }
            ) {
                InviteDeviceView(
                    app: self, model: model, close: { [weak self] in self?.shell.closeDialog() },
                    typedCode: { [weak self] in
                        self?.shell.closeDialog()
                        self?.openAddDevice()
                    })
            })
    }

    /// Add device by QR kept open on purpose: whatever is still live when the dialog goes (Esc, "Close anyway") is handed here and
    /// stays in the bell until it is withdrawn.
    func abandonInvites(_ ids: [String]) {
        for id in ids where !leftInvites.contains(id) { leftInvites.append(id) }
        shell.bell.add(
            BellItem(
                id: "invite-live", kind: .alarm, title: "A device QR is still live",
                sub: "Anyone who scans it can add a device. Withdraw it here; this will not survive quitting the app.",
                time: "now",
                actions: [
                    BellAction("Withdraw", primary: true) { [weak self] in Task { await self?.withdrawLeftInvites() } }
                ]))
    }

    func withdrawLeftInvites() async {
        let ids = leftInvites
        guard !ids.isEmpty else { return }
        do {
            let service = invites
            let failed: [String] = try await elevated("Withdraw the device QR.", done: "withdrawn") {
                try await withdrawInvites(ids, with: service)
            }
            leftInvites = failed
            if failed.isEmpty {
                shell.bell.remove("invite-live")
                shell.showToast("The device QR was withdrawn.")
            } else {
                shell.showToast("The Core could not be reached, so the QR is still live.", kind: .warn)
            }
        } catch { say(error) }
    }

    // MARK: elevation

    /// The Core's key fingerprint this Mac paired with, for the new device to compare against.
    var coreFingerprint: String? { (try? keyStore.loadIdentity())??.coreFingerprint }
    /// The Core's address (`https://host:port`), for the command a runner runs to pair.
    var coreURL: String? { (try? keyStore.loadIdentity())??.endpoint.absoluteString }

    /// The app unlock stands for the elevation the terminal and AI-session routes want; a fresh step-up (a danger action) is the
    /// per-action `elevatedUntil` window.
    var isElevated: Bool { isUnlocked || (shell.elevatedUntil.map { $0 > Date() } ?? false) }
    var isUnlocked: Bool { unlockSupported && shell.lock == .open }

    /// Touch ID, through the one sheet, shown only while the system prompt is up. True when the session is elevated (it may have
    /// been already). When it is not, `stepUpNotice` says why and the caller's panel shows it inline.
    func ensureElevated(
        _ reason: String, done: String, keepsEdit: Bool = true, force: Bool = false, session: Bool = false
    ) async -> Bool {
        guard let service else { return false }
        if isElevated && !force && !session { return true }
        stepUp.opensSession = session
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
            if session {
                _ = try await service.unlock(reason: reason)
            } else {
                setElevated(try await service.stepUp(reason: reason))
            }
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
        }
    }

    /// Runs an action that may need Touch ID. It runs first: the Core says what it wants. `step_up_required` on a danger action (D-4)
    /// asks a fresh Touch ID; with the app locked (it lapsed, or the Core restarted) the unlock comes first. `done` names what did not
    /// happen if the person says no. At most two prompts, then the Core's own answer stands.
    func elevated<T>(
        _ reason: String, done: String, keepsEdit: Bool = true, _ op: () async throws -> T
    ) async throws -> T {
        var asked = 0
        while true {
            do { return try await op() } catch {
                guard let why = CoreError.unwrapping(error), why.needsProof, asked < 2 else { throw error }
                asked += 1
                // `unlock_required` means the Core forgot the unlock: sign in again. `step_up_required` is a danger action.
                let ok =
                    why == .unlockRequired || (unlockSupported && shell.lock != .open)
                    ? await unlockApp()
                    : await ensureElevated(reason, done: done, keepsEdit: keepsEdit, force: true)
                guard ok else { throw StepUpDeclined() }
            }
        }
    }

    // MARK: app unlock (E1-1)

    /// After the session opens: unlock once (Touch ID), then hold it. A Core without the unlock leaves the app open and every danger
    /// or code-running action asks for its own Touch ID, as before.
    func startUnlock() async {
        guard let service else { return }
        unlockSupported = await service.supportsUnlock
        guard unlockSupported else {
            shell.lock = .open
            return
        }
        watchMacLock()
        if shell.lock == .open { shell.lock = .locked }
        await unlockApp()
    }

    /// One Touch ID opens the app until the Mac locks or sleeps or the app quits (D-5: no time cap). False when it was not given.
    @discardableResult
    func unlockApp() async -> Bool {
        guard unlockSupported, shell.lock != .checking else { return shell.lock == .open }
        shell.lock = .checking
        if await ensureElevated("Unlock Ainkrad.", done: "unlocked", keepsEdit: false, force: true, session: true) {
            shell.lock = .open
            stepUpNotice = nil
            holdUnlock()
            Task { [brain] in
                await brain?.reload()
                await brain?.openSealedRooms()
            }
            return true
        }
        shell.lock = .locked
        return false
    }

    /// The heartbeat: every 30 s while the app is open. A beat the Core refuses means it forgot the unlock (it restarted): the
    /// card comes back and one Touch ID opens it again.
    private func holdUnlock() {
        beat?.cancel()
        beat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.beatEvery ?? .seconds(30))
                guard !Task.isCancelled, let self, let service = self.service else { return }
                do { try await service.beatUnlock() } catch {
                    guard CoreError.unwrapping(error)?.needsProof == true else { continue }
                    self.lockApp(tellCore: false)
                    await self.unlockApp()
                    return
                }
            }
        }
    }

    /// The Mac locked or slept, or the app is going: the Core ends the unlock and the card covers the app.
    func lockApp(tellCore: Bool = true) {
        beat?.cancel()
        beat = nil
        guard unlockSupported else { return }
        shell.elevatedUntil = nil
        shell.lock = .locked
        admin.hideRevealed()  // a revealed value never outlives the unlock
        if tellCore, let service { Self.endInBackground(service) }
    }

    private func watchMacLock() {
        guard lockWatch.isEmpty, !demo else { return }
        let ws = NSWorkspace.shared.notificationCenter
        let dc = DistributedNotificationCenter.default()
        func on(_ c: NotificationCenter, _ name: Notification.Name, _ f: @escaping @MainActor (AppModel) -> Void) {
            let t = c.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { f(self) } }
            }
            lockWatch.append((c, t))
        }
        on(ws, NSWorkspace.willSleepNotification) { $0.lockApp() }
        // Waking: the screen may not lock at all, so no unlock notice would come. Ask once; if the screen is still locked the
        // prompt is refused and the card waits for `screenIsUnlocked`.
        on(ws, NSWorkspace.didWakeNotification) { m in
            m.lockApp(tellCore: false)
            Task {
                try? await Task.sleep(for: .seconds(1))
                await m.unlockApp()
            }
        }
        on(dc, Notification.Name("com.apple.screenIsLocked")) { $0.lockApp() }
        on(dc, Notification.Name("com.apple.screenIsUnlocked")) { m in Task { await m.unlockApp() } }
        // Quitting ends it too, so the Core does not wait out the 90 s.
        on(NotificationCenter.default, NSApplication.willTerminateNotification) { m in
            guard m.unlockSupported, let service = m.service else { return }
            Self.endInBackground(service)
        }
    }

    /// Tells the Core the unlock ended without blocking the main thread. An activity keeps the process (and a Mac going idle to sleep)
    /// alive for the one call; if the Mac sleeps or quits first, the Core lapses the unlock itself 90 s after the last beat.
    private static func endInBackground(_ service: any CoreService) {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated], reason: "Ending the app unlock")
        Task.detached {
            await service.endUnlock()
            ProcessInfo.processInfo.endActivity(activity)
        }
    }

    private func stopUnlock() {
        beat?.cancel()
        beat = nil
        lockWatch.forEach { $0.center.removeObserver($0.token) }
        lockWatch = []
        unlockSupported = false
        shell.lock = .open
    }

    // MARK: forgetting

    /// This Mac was revoked (by itself, from Devices) or the person chose to forget the Core: the keys go, first run returns.
    func forgetCore() async {
        stopUnlock()
        events?.cancel()
        retry?.cancel()
        homeFeed?.stop()
        homeFeed = nil
        agents.detach()
        await service?.close()
        await macRunner.coreForgotten()
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
        projects.detach()
        leyline.detach()
        design.detach()
        lore.detach()
        shell.linkNotice = nil
        shell.home = .empty
        shell.resetToFresh()
        firstRun.resetAll()
        leftInvites = []
        wizard.startOver()
        useTypedCode = false
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
    public var thisMacRunnerID: String? { macRunner.runnerID }

    public func openTerminal(on runner: String, session: String?) { terminals?.open(on: runner, session: session) }
    public func embeddedTerminal(on runner: String, session: String) -> AnyView? {
        terminals.map { AnyView(EmbeddedTerminal(model: $0, runner: runner, session: session)) }
    }

    /// Touch ID for the agent actions: nil when elevated, else the inline words for what happened.
    public func elevate(reason: String, force: Bool) async -> InlineNotice? {
        if isElevated && !force { return nil }
        if force && unlockSupported && shell.lock != .open {
            if await unlockApp() { return nil }
            return InlineNotice(title: "Touch ID did not run.")
        }
        if await ensureElevated(reason, done: "done", keepsEdit: true, force: force) { return nil }
        let n = stepUpNotice
        stepUpNotice = nil
        return n.map { InlineNotice(title: $0.title, detail: $0.detail, symbol: $0.symbol, tone: $0.tone) }
            ?? InlineNotice(title: "Touch ID did not run.")
    }
}
