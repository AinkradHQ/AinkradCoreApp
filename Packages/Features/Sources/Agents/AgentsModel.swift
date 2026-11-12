import CoreKit
import CoreUI
import Foundation
import Observation
import Shell

/// Why an elevated action did not run, in words for an inline banner.
public struct InlineNotice: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var symbol: String
    public var tone: Tone
    public init(title: String, detail: String = "", symbol: String = "exclamationmark.triangle", tone: Tone = .warn) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.tone = tone
    }
}

/// What the app gives this module: Touch ID. Returns nil when the session is elevated, else the notice to show in place.
@MainActor
public protocol AgentsHost: AnyObject {
    func elevate(reason: String, force: Bool) async -> InlineNotice?
}

struct ElevationDeclined: Error { let notice: InlineNotice }

public enum BindingsPhase: Equatable, Sendable {
    case loading, ready
    case failed(String)
}

public enum AgentFilter: String, CaseIterable, Sendable { case all, needsYou, active, ended }
public enum AgentsLink: Equatable, Sendable {
    case live, reconnecting
    case ended(String)
}

/// The agents area: the session list, the transcripts, approvals, and everything done to a session. Fed by the Core's event
/// stream; it refetches on a gap. Views read it; they hold no state of the Core's.
@MainActor @Observable
public final class AgentsModel {
    public let shell: ShellModel
    public let sessions = SessionsStore()
    public internal(set) var transcripts: [String: TranscriptStore] = [:]
    public internal(set) var runners: [RunnerInfo] = []
    /// Chains a session can start from. Empty for a device that is not an admin: the sheet then offers a harness only.
    public internal(set) var chains: [ChainOption] = []
    public internal(set) var link: AgentsLink = .live
    public var filter: AgentFilter = .all
    /// What is typed in each session's composer.
    public var drafts: [String: String] = [:]
    /// The quick popup's prompt, carried into the advanced sheet.
    public var draftPrompt = ""
    /// The chain picked on the quick sheet's chip, carried into the advanced sheet.
    public var draftChain: Int64?
    public internal(set) var sending: Set<String> = []
    /// Sessions asked to stop that have not ended yet: the Core answers a cancel at once but the agent only stops after its tool
    /// call in flight (or the runner's grace), so the session reads as still running until then. Shown as "Cancelling".
    public internal(set) var stopping: [String: StopKind] = [:]
    /// Inline outcome of the last thing done to a session (composer, cancel, resume…), cleared by the next try.
    public internal(set) var notices: [String: InlineNotice] = [:]
    /// Approvals being decided, and why one did not go through.
    public internal(set) var deciding: Set<String> = []
    public internal(set) var approvalNotices: [String: InlineNotice] = [:]
    public internal(set) var notifierPermission: NotificationPermission = .notAsked
    public var selected: String?
    /// The runner the New session sheet starts on (set by the runner page); nil: the best ready one.
    public var newSessionRunner: String?
    /// Each session's name: the first line of its prompt (Core sends no title yet, KAN-455). Filled on create, from a loaded
    /// transcript, or by `loadTitle` when a tile shows.
    public internal(set) var titles: [String: String] = [:]
    /// Agents a session can be started as (those with a chain bound). Empty for a device that is not an admin.
    public internal(set) var agentNames: [String] = []
    /// Agent to chain, for Settings, Agents and chains. Empty for a device that is not an admin.
    public internal(set) var bindings: [AgentBinding] = []
    public internal(set) var bindingsPhase: BindingsPhase = .loading
    /// What the last bind or unbind of an agent said, in place, and the agent being written now.
    public internal(set) var bindingNotices: [String: InlineNotice] = [:]
    public internal(set) var bindingBusy: String?
    /// A write came back `forbidden_scope`: this device can read but not change.
    public internal(set) var bindingsReadOnly = false
    /// The AI Sessions sidebar entry, the filters, and what the person pinned or archived by hand (kept on this Mac).
    var scope: SessionScope = .active
    var filters = SessionFilters()
    public internal(set) var pinned: Set<String> = []
    public internal(set) var archived: Set<String> = []
    @ObservationIgnored var raiseBudgetHook: ((AgentSessionInfo) -> Void)?
    @ObservationIgnored var titleLoading: Set<String> = []

    var api: (any AgentsAPI)?
    /// Each open session's spend from Core's ledger (`SessionSpend.swift`).
    var ledgers: [String: SessionLedger] = [:]
    /// A run's attempts by run id, and account names by id, for the route cues (`SessionRouteView.swift`).
    var attempts: [String: [AgentSessionInfo]] = [:]
    var accountNames: [Int64: String] = [:]
    weak var host: (any AgentsHost)?
    let notifier: any ApprovalNotifier
    let defaults: UserDefaults
    @ObservationIgnored var feed: Task<Void, Never>?
    /// The load `attach` starts; tests await it so it cannot overlap their own calls.
    @ObservationIgnored var firstLoad: Task<Void, Never>?
    @ObservationIgnored var ticker: Task<Void, Never>?
    @ObservationIgnored var primed = false
    @ObservationIgnored var announced: Set<String> = []
    @ObservationIgnored var registered: Set<String> = []
    @ObservationIgnored var launcherIDs: Set<String> = []
    #if DEBUG
    @ObservationIgnored var held: [AgentSessionInfo] = []
    /// Which source the New session sheet opens on in the snapshot walk (`chain`, `agent` or `busy`).
    @ObservationIgnored public var debugSource: String?
    @ObservationIgnored var debugChainList: [ChainOption]?
    /// Keeps the Agents and chains page in the state a snapshot scene set (loading, failed) instead of reading again.
    @ObservationIgnored var debugFreezeBindings = false
    #endif

    public init(
        shell: ShellModel, notifier: any ApprovalNotifier, defaults: UserDefaults = .standard,
        host: (any AgentsHost)? = nil
    ) {
        self.shell = shell
        self.notifier = notifier
        self.defaults = defaults
        self.host = host
        pinned = Set(defaults.stringArray(forKey: "aisessions.pinned") ?? [])
        archived = Set(defaults.stringArray(forKey: "aisessions.archived") ?? [])
        registerBase()
        notifier.onOpen = { [weak self] id in
            if id == "connections" {
                self?.shell.launcher.entry("connections")?.run()
            } else if !id.isEmpty {
                self?.openSession(id)
            }
        }
    }

    /// A notification that is not about a session (a connection that needs you, CN5); a click opens Connections.
    public func notifyConnections(id: String, title: String, body: String) {
        notifier.post(id: id, title: title, body: body, session: "connections")
    }

    func setChains(_ list: [ChainOption]) {
        #if DEBUG
        chains = debugChainList ?? list
        #else
        chains = list
        #endif
    }

    public func setHost(_ host: any AgentsHost) { self.host = host }

    // MARK: preferences

    /// Banners for new approvals. On by default; the macOS permission still has the last word.
    public var notifyApprovals: Bool {
        get {
            access(keyPath: \.notifyApprovals)
            return defaults.object(forKey: "agents.notify.approvals") as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.notifyApprovals) { defaults.set(newValue, forKey: "agents.notify.approvals") }
        }
    }

    /// This device holds the admin scope: only then does the Core send it account news, and only then the tiles show.
    public var isAdmin = false

    /// Banners for the account push kinds (`account_health`, `account_failover`, `account_expired`). On by default.
    public func notifies(_ pushKind: String) -> Bool {
        access(keyPath: \.notifyApprovals)
        return defaults.object(forKey: "agents.notify.\(pushKind)") as? Bool ?? true
    }
    public func setNotifies(_ pushKind: String, _ on: Bool) {
        withMutation(keyPath: \.notifyApprovals) { defaults.set(on, forKey: "agents.notify.\(pushKind)") }
    }

    /// A banner for an account event, when the person wants that kind and macOS allows it.
    public func postAccountBanner(_ pushKind: String, _ id: String, _ title: String, _ body: String) {
        guard isAdmin, notifies(pushKind) else { return }
        notifier.post(id: id, title: title, body: body, session: "")
    }

    /// The app has put its own question about notifications to the person once. Never again on its own.
    public var askedAboutNotifications: Bool {
        get {
            access(keyPath: \.askedAboutNotifications)
            return defaults.bool(forKey: "agents.notify.asked")
        }
        set {
            withMutation(keyPath: \.askedAboutNotifications) { defaults.set(newValue, forKey: "agents.notify.asked") }
        }
    }

    /// Show the polite question: macOS has not been asked and the person has not been either.
    public var shouldAskAboutNotifications: Bool { notifierPermission == .notAsked && !askedAboutNotifications }

    public func refreshPermission() async {
        await notifier.refresh()
        notifierPermission = notifier.permission
    }

    /// The person said yes in the app's words: now macOS asks, once.
    public func turnOnNotifications() async {
        askedAboutNotifications = true
        notifierPermission = await notifier.request()
    }

    public func declineNotificationsForNow() { askedAboutNotifications = true }

    // MARK: connection

    /// Starts following the Core. The stream goes first so nothing that happens during the first load is missed.
    public func attach(_ api: any AgentsAPI) {
        detach()
        self.api = api
        link = .live
        feed = Task { [weak self] in
            for await f in api.events() {
                guard let self, !Task.isCancelled else { return }
                await self.handle(f)
            }
        }
        Task { await refreshPermission() }
        firstLoad = Task { await reloadAll() }
    }

    public func detach() {
        feed?.cancel()
        ticker?.cancel()
        feed = nil
        ticker = nil
        api = nil
        primed = false
        announced = []
        for id in registered { shell.bell.remove(id) }
        registered = []
    }

    /// The list, the runners' names and every live session's tail (a pending approval is only in a transcript).
    public func reloadAll() async {
        guard let api else { return }
        await sessions.reload(api)
        if let r = try? await api.runners() { runners = r }
        setChains((try? await api.chains()) ?? [])
        agentNames = (try? await api.agents()) ?? []
        await loadBindings()
        for s in sessions.items where s.live && transcripts[s.id] == nil { _ = store(s.id) }
        for (id, t) in transcripts { await t.refresh(api, knownLast: sessions.session(id)?.lastSeq ?? 0) }
        syncDerived()
        primed = true
    }

    func store(_ id: String) -> TranscriptStore {
        if let t = transcripts[id] { return t }
        let t = TranscriptStore(sessionID: id)
        transcripts[id] = t
        return t
    }

    /// A session's transcript, loaded on first ask.
    public func transcript(_ id: String) -> TranscriptStore {
        let first = transcripts[id] == nil
        let t = store(id)
        if first, let api {
            Task { [weak self] in
                await t.refresh(api, knownLast: self?.sessions.session(id)?.lastSeq ?? 0)
                self?.syncDerived()
            }
        }
        return t
    }

    public func retryList() { Task { await reloadAll() } }
    public func loadMore() { if let api { Task { await sessions.loadMore(api) } } }
    public func loadEarlier(_ id: String) {
        guard let api, let t = transcripts[id] else { return }
        Task { await t.loadEarlier(api) }
    }

    // MARK: events

    func handle(_ f: AgentFeed) async {
        switch f {
        case .live: link = .live
        case .reconnecting: link = .reconnecting
        case .gap: await reloadAll()
        case .ended(let why): link = .ended(why)
        case .event(let e): await apply(e)
        }
    }

    func apply(_ e: AgentEvent) async {
        guard let api else { return }
        if e.kind.hasPrefix("runner.") {  // a runner came or went: its chip and slots must follow
            if let r = try? await api.runners() { runners = r }
            return
        }
        guard let id = e.session else { return }
        switch e.kind {
        case "agent.created", "agent.state", "agent.ended", "agent.message", "agent.turn_ended", "agent.title":
            await refreshSession(id)
            if e.kind != "agent.created", let t = transcripts[id] { await t.refresh(api, knownLast: lastSeq(id)) }
        case "agent.transcript":
            if let t = transcripts[id] { await t.refresh(api, knownLast: lastSeq(id)) }
        case "agent.approval_requested", "agent.approval_decided":
            await refreshSession(id)
            await store(id).refresh(api, knownLast: lastSeq(id))
        default: break  // a kind this build does not know
        }
        syncDerived()
    }

    func lastSeq(_ id: String) -> Int64 { sessions.session(id)?.lastSeq ?? 0 }

    func refreshSession(_ id: String) async {
        guard let api, let s = try? await api.session(id) else { return }
        sessions.upsert(s)
    }

    // MARK: derived

    public func runnerName(_ id: String) -> String { runners.first { $0.id == id }?.name ?? id }

    /// Approvals nobody has answered yet, oldest first.
    public var pending: [ApprovalRequest] {
        let now = Date()
        return transcripts.values.flatMap { t in
            let over = sessions.session(t.sessionID)?.over ?? false
            return t.approvals.values.filter { $0.status(now: now, sessionOver: over) == .pending }
        }
        .sorted { $0.requestedAt < $1.requestedAt }
    }

    /// Approvals answered or expired in this run, newest first, for the inbox's Decided list.
    public var decided: [ApprovalRequest] {
        let now = Date()
        return transcripts.values.flatMap { t in
            let over = sessions.session(t.sessionID)?.over ?? false
            return t.approvals.values.filter { $0.status(now: now, sessionOver: over) != .pending }
        }
        .sorted { $0.requestedAt > $1.requestedAt }
    }

    /// What a session's pane shows above its composer: what waits on you, and the latest request nobody answered in time (while the
    /// session is still going, so you know to ask it again).
    public func cards(for id: String) -> [ApprovalRequest] {
        let now = Date()
        guard let t = transcripts[id] else { return [] }
        let over = sessions.session(id)?.over ?? false
        let all = t.approvalList
        let waiting = all.filter { $0.status(now: now, sessionOver: over) == .pending }
        let lapsed = over ? nil : all.last { $0.status(now: now, sessionOver: over) == .expired }
        return waiting + (lapsed.map { [$0] } ?? [])
    }

    /// "Waiting on you": approvals nobody has answered, and nothing else. Alerts and Brain-inbox items are counted by their own
    /// owners. The list header, the filter, the footer and the shell's status bar and bell all read this one number.
    public var waitingOnYou: Int { pending.count }

    public func waiting(_ id: String) -> Bool { pending.contains { $0.session == id } }

    public func shown() -> [AgentSessionInfo] {
        let waitingIDs = Set(pending.map(\.session))
        let rows = sessions.items.filter { s in
            switch filter {
            case .all: true
            case .needsYou: waitingIDs.contains(s.id)
            case .active: s.live
            case .ended: s.over
            }
        }
        return rows.sorted { waitingIDs.contains($0.id) && !waitingIDs.contains($1.id) }
    }

    public func count(_ f: AgentFilter) -> Int {
        let waitingIDs = Set(pending.map(\.session))
        return sessions.items.filter { s in
            switch f {
            case .all: true
            case .needsYou: waitingIDs.contains(s.id)
            case .active: s.live
            case .ended: s.over
            }
        }.count
    }
}
