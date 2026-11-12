import Admin
import BrainImport
import Foundation
import Observation

/// Rooms page, sync half: Sync now, the sources list, the rules and the hourly timer (E4-6, E7-2 App half).
///
/// A Mac collector reads its cursor from `GET /sources`, takes only files newer than it, uploads them as an incremental
/// run, waits until the Core has the run, and only then puts the new cursor back. A failure before that leaves the
/// cursor where it was, so the next sync takes the same files again (the Core drops duplicates by hash).
@MainActor @Observable
public final class SyncModel {
    let host: any AdminHost
    let service: any BrainService
    let sourceList: @Sendable () -> [any ImportSource]
    let poll: Duration
    let pause: @Sendable (Int) async -> Void
    let now: @Sendable () -> Date

    public private(set) var status: SyncStatusWire?
    public private(set) var sources: [SourceWire] = []
    public private(set) var rules: [RuleWire] = []
    /// The last sync's answer, shown under Sync now.
    public private(set) var outcome: SyncResultWire?
    public private(set) var syncing = false
    /// While syncing: which source is being read, as "n of total".
    public private(set) var syncAt = 0
    public private(set) var syncTotal = 0
    public private(set) var syncSource: String?
    public internal(set) var notice: String?
    @ObservationIgnored private var timer: Task<Void, Never>?

    public init(
        host: any AdminHost, service: any BrainService, sources: @escaping @Sendable () -> [any ImportSource],
        poll: Duration = .seconds(1), now: @escaping @Sendable () -> Date = { Date() },
        pause: @escaping @Sendable (Int) async -> Void = { try? await Task.sleep(for: .seconds(Double(1 << $0))) }
    ) {
        self.host = host
        self.service = service
        self.sourceList = sources
        self.poll = poll
        self.now = now
        self.pause = pause
    }

    /// The id a Mac collector has on the Core.
    public static func sourceID(_ id: String) -> String { "mac_\(id)" }
    static var deviceName: String { Host.current().localizedName ?? "Mac" }

    public var review: [String] { status?.review ?? [] }

    public func reload() async {
        do {
            async let st = service.syncStatus()
            async let src = service.sources()
            async let r = service.rules()
            (status, sources, rules) = try await (st, src, r)
        } catch { notice = BrainWords.failure(error) }
    }

    // MARK: switches

    public func toggle(_ source: SourceWire, on: Bool) async {
        do {
            let saved = try await service.putSource(source, enabled: on, cursor: nil)
            if let i = sources.firstIndex(where: { $0.id == saved.id }) { sources[i] = saved }
        } catch { notice = BrainWords.failure(error) }
    }

    /// Touch ID first: switching a rule changes what the Brain refuses.
    public func toggleRule(_ rule: RuleWire, on: Bool) async {
        guard !rule.locked else { return }
        do {
            let saved = try await host.elevated(
                on ? "Turn this rule on." : "Turn this rule off.", done: "changed", keepsEdit: false
            ) { try await self.service.setRule(rule.id, enabled: on) }
            if let i = rules.firstIndex(where: { $0.id == saved.id }) { rules[i] = saved }
        } catch is AdminDeclined {
        } catch { notice = BrainWords.failure(error) }
    }

    // MARK: sync

    /// Sync now: the Mac collectors, then the Core's own. Returns the Core's answer.
    @discardableResult
    public func syncNow() async -> SyncResultWire? {
        guard !syncing else { return nil }
        syncing = true
        notice = nil
        outcome = nil
        defer {
            syncing = false
            syncSource = nil
        }
        do {
            try await collectLocal()
            syncSource = SyncWords.coreSource
            syncAt = max(syncTotal - 1, 0)
            let r = try await service.syncNow()
            outcome = r
            await reload()
            return r
        } catch {
            notice = BrainWords.failure(error)
            await reload()
            return nil
        }
    }

    /// Every enabled, registered Mac collector once. The first failure stops the sync and is shown.
    func collectLocal() async throws {
        syncTotal = 1
        syncAt = 0
        guard let routes = service.importRoutes else { return }
        let rows = try await service.sources()
        let local = sourceList().filter { s in
            s.incremental && rows.contains { $0.id == Self.sourceID(s.id) && $0.enabled }
        }
        syncTotal = local.count + 1
        for (i, src) in local.enumerated() {
            guard let row = rows.first(where: { $0.id == Self.sourceID(src.id) }) else { continue }
            syncAt = i
            syncSource = SyncWords.title(src.id, sourceList())
            let began = now()
            let next = src.cursorAfter(row.cursor, began: began)
            guard await src.newCount(cursor: row.cursor) > 0 else { continue }
            let run = try await routes.startRun(kind: "incremental", sources: [src.id])
            let uploader = Uploader(transport: RoutesImportTransport(routes: routes), pause: pause)
            _ = try await src.streamNew(cursor: row.cursor, run: run, uploader: uploader, uploaded: .init())
            do { _ = try await routes.collected(run: run, source: src.id) } catch let e as BrainHTTPError
                where e.status == 409
            {}
            try await confirmed(run, routes)
            // Only now: the Core has the run. `began` (not now) so a file written while reading is taken next time.
            _ = try await service.putSource(row, enabled: nil, cursor: next)
        }
    }

    /// Waits until the Core has taken the run (it is in review, committing or committed). Anything else throws.
    func confirmed(_ run: String, _ routes: BrainRoutes) async throws {
        for _ in 0..<120 {
            let v = try await routes.run(run)
            if ["review", "committing", "committed"].contains(v.state) { return }
            if v.state == "abandoned" { throw BrainFailure("This sync was abandoned.", code: "abandoned") }
            try await Task.sleep(for: poll)
        }
        throw BrainFailure("The Core has not finished taking the new items yet.", code: "timeout")
    }

    /// Registers the Mac collectors a first import used, each starting from `since`, so later syncs take only what is new.
    public static func register(
        _ ids: [String], from sources: [any ImportSource], since: Date, service: any BrainService
    )
        async
    {
        let existing = (try? await service.sources()) ?? []
        for s in sources where s.incremental && ids.contains(s.id) {
            let id = sourceID(s.id)
            guard !existing.contains(where: { $0.id == id }) else { continue }
            let row = SourceWire(id: id, device: deviceName, kind: s.id)
            _ = try? await service.putSource(row, enabled: true, cursor: SourceCursor(date: since))
        }
    }

    // MARK: what the page shows

    /// Puts the sync result away.
    public func dismissOutcome() { outcome = nil }

    /// The newest run of any source, as the Core reported it.
    public var lastSync: Date? {
        (status?.sources ?? []).compactMap { SyncWords.date($0.lastRun) }.max()
    }

    /// The one line over the room list: a sync running, its result, or imports waiting for review.
    public var banner: SyncBanner {
        if syncing { return .syncing(source: syncSource, at: syncAt, total: syncTotal) }
        if let r = outcome {
            let review = r.unsorted + r.newRooms
            if r.idle == "nothing_new" || (r.idle == nil && r.stored == 0 && review == 0) {
                let n = status?.sources.count ?? sources.count
                return .nothingNew(sources: n, nextMinutes: max((status?.everySecs ?? 3600) / 60, 1))
            }
            if r.idle != nil { return .message(r.summary()) }
            return .synced(
                new: r.stored, went: r.routed.reduce(0) { $0 + $1.sources }, rooms: r.routed.count, review: review)
        }
        return review.isEmpty ? .none : .waiting(review.count)
    }

    // MARK: timer

    /// Hourly while the app runs. The Core says how often; a nil status keeps the hour.
    public func startTimer(every: Duration? = nil) {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                let secs = self?.status?.everySecs ?? 3600
                try? await Task.sleep(for: every ?? .seconds(max(secs, 60)))
                if Task.isCancelled { return }
                await self?.syncNow()
            }
        }
    }

    public func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: search

    /// One room's search. A closed room answers in words, never a half result.
    public func search(room: String, query: String) async -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        do { return try await service.search(room: room, query: q) } catch {
            notice = BrainWords.failure(error)
            return []
        }
    }
}
