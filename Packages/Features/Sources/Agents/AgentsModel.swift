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
    public internal(set) var link: AgentsLink = .live
    public var filter: AgentFilter = .all
    /// What is typed in each session's composer.
    public var drafts: [String: String] = [:]
    public internal(set) var sending: Set<String> = []
    /// Inline outcome of the last thing done to a session (composer, cancel, resume…), cleared by the next try.
    public internal(set) var notices: [String: InlineNotice] = [:]
    /// Approvals being decided, and why one did not go through.
    public internal(set) var deciding: Set<String> = []
    public internal(set) var approvalNotices: [String: InlineNotice] = [:]
    public internal(set) var notifierPermission: NotificationPermission = .notAsked
    public var selected: String?

    var api: (any AgentsAPI)?
    weak var host: (any AgentsHost)?
    let notifier: any ApprovalNotifier
    let defaults: UserDefaults
    @ObservationIgnored var feed: Task<Void, Never>?
    @ObservationIgnored var ticker: Task<Void, Never>?
    @ObservationIgnored var primed = false
    @ObservationIgnored var announced: Set<String> = []
    @ObservationIgnored var registered: Set<String> = []
    @ObservationIgnored var launcherIDs: Set<String> = []
    #if DEBUG
    @ObservationIgnored var held: [AgentSessionInfo] = []
    #endif

    public init(
        shell: ShellModel, notifier: any ApprovalNotifier, defaults: UserDefaults = .standard,
        host: (any AgentsHost)? = nil
    ) {
        self.shell = shell
        self.notifier = notifier
        self.defaults = defaults
        self.host = host
        registerBase()
        notifier.onOpen = { [weak self] id in self?.openSession(id) }
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
        Task { await reloadAll() }
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
        guard let api, let id = e.session else { return }
        switch e.kind {
        case "agent.created", "agent.state", "agent.ended", "agent.message":
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
