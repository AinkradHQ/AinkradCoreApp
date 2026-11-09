import Foundation
import Observation

public enum AgentsLoad: Equatable, Sendable {
    case idle, loading, ready
    case failed(String)
}

/// One session's transcript: append-only, held as a window of the tail with earlier pages loaded on demand. The view reads
/// `entries` (visible ones, by seq) so an appended entry adds one row and leaves the others alone.
@MainActor @Observable
public final class TranscriptStore {
    public let sessionID: String
    public private(set) var entries: [TranscriptEntry] = []
    /// The newest seq seen, visible or not: the cursor a refresh continues from.
    public private(set) var lastSeq: Int64 = 0
    /// Entries with seq above this are held. Zero means the start of the transcript is held.
    public private(set) var heldAfter: Int64 = 0
    public private(set) var load: AgentsLoad = .idle
    public private(set) var loadingEarlier = false
    public private(set) var approvals: [String: ApprovalRequest] = [:]
    /// Decisions seen before their request was (an earlier page loads later).
    private var earlyDecisions: [String: Bool] = [:]
    /// Tool calls still waiting for their result, by tool id.
    private var toolSeq: [String: Int64] = [:]
    @ObservationIgnored private var inflight: Task<Void, Never>?
    @ObservationIgnored private var dirty = false
    static let tail: Int64 = 200
    static let page = 500
    /// How many entries are held at once; the oldest fall out of the window and `loadEarlier` pages them back.
    static let window = 2000

    public init(sessionID: String) { self.sessionID = sessionID }

    public var hasEarlier: Bool { heldAfter > 0 }

    /// Pending (or lately decided) approvals, oldest first.
    public var approvalList: [ApprovalRequest] { approvals.values.sorted { $0.requestedAt < $1.requestedAt } }

    // MARK: pure updates (tested without a Core)

    /// Adds entries after `lastSeq`, once each and in order: a resend or an out-of-order entry is dropped. Returns how many were
    /// new. A hole in the numbers is the runner's own `gap` entry or the Core's trimming: it is shown, never filled in.
    @discardableResult
    func append(_ page: [TranscriptEntry]) -> Int {
        var added = 0
        for e in page.sorted(by: { $0.seq < $1.seq }) where e.seq > lastSeq {
            lastSeq = e.seq
            added += 1
            absorb(e)
            if foldResult(e) { continue }
            if case .toolUse(let id, _, _) = e.kind { toolSeq[id] = e.seq }
            if e.visible { entries.append(e) }
        }
        trim()
        return added
    }

    /// Keeps the newest `window` entries; what falls off is paged back in by `loadEarlier`.
    func trim() {
        guard entries.count > Self.window else { return }
        let drop = entries.count - Self.window
        heldAfter = entries[drop - 1].seq
        entries.removeFirst(drop)
    }

    /// A tool's result joins its call's row (one row for the pair, the way the prototype shows it).
    private func foldResult(_ e: TranscriptEntry) -> Bool {
        guard case .toolResult(let id, let name, let ok, let code, let out, let ms) = e.kind, let seq = toolSeq[id],
            let i = entries.lastIndex(where: { $0.seq == seq }), case .toolUse(_, let n, let summary) = entries[i].kind
        else { return false }
        entries[i] = TranscriptEntry(
            seq: seq, at: entries[i].at,
            kind: .toolDone(
                id: id, name: name ?? n, summary: summary, ok: ok, exitCode: code, output: out, durationMs: ms))
        toolSeq[id] = nil
        return true
    }

    /// Entries from before the first one held.
    func prepend(_ page: [TranscriptEntry], after: Int64) {
        let first = entries.first?.seq ?? lastSeq + 1
        let older = page.filter { $0.seq < first }.sorted { $0.seq < $1.seq }
        for e in older { absorb(e) }
        entries.insert(contentsOf: older.filter(\.visible), at: 0)
        heldAfter = min(heldAfter, after)
    }

    func start(after: Int64) {
        heldAfter = after
        lastSeq = max(lastSeq, after)
    }

    private func absorb(_ e: TranscriptEntry) {
        switch e.kind {
        case .approvalRequest(let id, let tool, let input, let timeout):
            var r = ApprovalRequest(
                id: id, session: sessionID, tool: tool, input: input, requestedAt: e.at, timeoutSecs: timeout)
            r.decision = approvals[id]?.decision ?? earlyDecisions[id]
            approvals[id] = r
        case .approvalDecided(let id, let approved):
            if approvals[id] != nil { approvals[id]?.decision = approved } else { earlyDecisions[id] = approved }
        default: break
        }
    }

    /// The person's choice shown at once; `unmark` takes it back when the Core refuses.
    func mark(_ id: String, approved: Bool) { approvals[id]?.decision = approved }
    func unmark(_ id: String) { approvals[id]?.decision = nil }

    // MARK: fetching

    /// The tail of the transcript the first time, then whatever came after `lastSeq`. Calls that overlap share the run in flight
    /// (which goes once more, so what arrived meanwhile is read) and return when it is done.
    func refresh(_ api: any AgentsAPI, knownLast: Int64) async {
        if let running = inflight {
            dirty = true
            await running.value
            return
        }
        let task = Task { await self.run(api, knownLast: knownLast) }
        inflight = task
        await task.value
        inflight = nil
    }

    private func run(_ api: any AgentsAPI, knownLast: Int64) async {
        if load == .idle { load = .loading }
        repeat {
            dirty = false
            do {
                if lastSeq == 0 && heldAfter == 0 && knownLast > Self.tail { start(after: knownLast - Self.tail) }
                while true {
                    let page = try await api.transcript(sessionID, after: lastSeq, limit: Self.page)
                    let n = append(page.entries)
                    if page.entries.count < Self.page || n == 0 { break }
                }
                load = .ready
            } catch {
                if entries.isEmpty { load = .failed(Self.words(error)) }
                return
            }
        } while dirty
    }

    func loadEarlier(_ api: any AgentsAPI) async {
        guard hasEarlier, !loadingEarlier else { return }
        loadingEarlier = true
        defer { loadingEarlier = false }
        let from = max(0, heldAfter - Self.tail)
        guard let page = try? await api.transcript(sessionID, after: from, limit: Int(heldAfter - from)) else { return }
        prepend(page.entries, after: from)
    }

    /// The events were trimmed: what is held may be stale, so go on from the newest seq (the transcript only grows).
    func resync(_ api: any AgentsAPI, knownLast: Int64) async { await refresh(api, knownLast: knownLast) }

    static func words(_ error: any Error) -> String { error.localizedDescription }
}

/// The list of sessions, newest first, paged by `index`.
@MainActor @Observable
public final class SessionsStore {
    public private(set) var items: [AgentSessionInfo] = []
    public private(set) var load: AgentsLoad = .idle
    public private(set) var hasMore = true
    public private(set) var loadingMore = false
    /// Tokens used per session as this Mac has seen them change, oldest first. The Core reports a total, not a history, so the
    /// burn chart is what this app sampled: it starts empty and fills while the app watches.
    public private(set) var burn: [String: [Double]] = [:]
    static let page = 50
    static let burnKeep = 48

    public init() {}

    public func session(_ id: String) -> AgentSessionInfo? { items.first { $0.id == id } }

    /// A newer view of a session replaces it in place; a new one goes where its creation time puts it.
    public func upsert(_ s: AgentSessionInfo) {
        sample(s)
        if let i = items.firstIndex(where: { $0.id == s.id }) {
            if items[i] != s { items[i] = s }
        } else {
            let at = items.firstIndex { $0.createdAt <= s.createdAt } ?? items.count
            items.insert(s, at: at)
        }
    }

    /// Notes a session's token total when it changed since the last sample.
    func sample(_ s: AgentSessionInfo) {
        guard let t = s.usage?.tokens else { return }
        var list = burn[s.id] ?? []
        guard list.last != Double(t) else { return }
        list.append(Double(t))
        if list.count > Self.burnKeep { list.removeFirst(list.count - Self.burnKeep) }
        burn[s.id] = list
    }

    /// The cost of every loaded session that reported one, and how many did not.
    public var totalCostMicros: Int64 { items.reduce(0) { $0 + ($1.usage?.costMicros ?? 0) } }

    #if DEBUG
    func debugSeedBurn(_ id: String, _ values: [Double]) { burn[id] = values }

    func debugSet(load: AgentsLoad, items: [AgentSessionInfo]? = nil) {
        self.load = load
        if let items { self.items = items }
    }
    #endif

    func reload(_ api: any AgentsAPI) async {
        if items.isEmpty { load = .loading }
        do {
            let page = try await api.sessions(before: nil, limit: Self.page)
            // A session newer than the page (created while it was in flight) stays; the rest is replaced.
            let ids = Set(page.map(\.id))
            let newer = items.filter { !ids.contains($0.id) && $0.createdAt > (page.first?.createdAt ?? .distantPast) }
            items = newer + page
            for s in items { sample(s) }
            hasMore = page.count >= Self.page
            load = .ready
        } catch {
            if items.isEmpty { load = .failed(TranscriptStore.words(error)) }
        }
    }

    func loadMore(_ api: any AgentsAPI) async {
        guard hasMore, !loadingMore, let before = items.last?.index else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let page = try? await api.sessions(before: before, limit: Self.page) else { return }
        for s in page { upsert(s) }
        hasMore = page.count >= Self.page
    }
}
