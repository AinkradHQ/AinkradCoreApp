#if DEBUG
import Foundation

/// Debug only: the prototype's sample world (brain-data.js) behind `BrainService`. EVERYTHING here is invented; no real
/// material, no credentials. Core does not serve the Brain yet, and Release has no service at all.
public actor SampleBrainService: BrainService {
    public struct Scenario: Sendable {
        public var paused = false
        public var offline = false
        public var rebuilding = false
        public var embeddingDown = false
        public var empty = false
        public var error = false
        public var healthy = false
        public init(
            paused: Bool = false, offline: Bool = false, rebuilding: Bool = false, embeddingDown: Bool = false,
            empty: Bool = false, error: Bool = false, healthy: Bool = false
        ) {
            self.paused = paused
            self.offline = offline
            self.rebuilding = rebuilding
            self.embeddingDown = embeddingDown
            self.empty = empty
            self.error = error
            self.healthy = healthy
        }
    }

    public nonisolated let isSample = true
    private var scenario: Scenario
    private var list: [RoomSummary]
    private var pausedRooms = ["automotive-ai", "optimus"]

    public init(_ scenario: Scenario = Scenario()) {
        self.scenario = scenario
        self.list = scenario.empty ? [] : Self.world()
    }

    public func rooms() async throws -> [RoomSummary] {
        if scenario.error {
            throw BrainFailure("Core did not answer. Nothing was changed.", code: "sample_unreachable")
        }
        return list
    }

    public func overview() async throws -> BrainOverview {
        if scenario.error {
            throw BrainFailure("Core did not answer. Nothing was changed.", code: "sample_unreachable")
        }
        let s = scenario
        var tiles = Self.tiles
        var needs = s.healthy || s.empty ? [] : Self.needs
        if s.paused {
            tiles[0] = HealthTile(
                "isolation", "Isolation", .bad, meter: 0, "A test found a leak. Search is stopped for 2 rooms.")
            needs.insert(NeedItem(.paused, n: 1, "check failed: search is stopped for 2 rooms"), at: 0)
        }
        if s.healthy {
            tiles = tiles.map { HealthTile($0.id, $0.name, .ok, meter: max($0.meter, 90), $0.text) }
        }
        let health: BrainHealth = s.paused ? .paused : needs.isEmpty ? .healthy : .needsYou
        return BrainOverview(
            health: health, tiles: tiles, needs: needs, pausedRooms: s.paused ? pausedRooms : [],
            speed: [188, 204, 176, 231, 212, 245, 198, 168, 277, 214, 190, 226, 205, 212],
            facts: BrainFacts(staleShare: 9, recall: "Full", secretBlocks: 2, flaggedSources: 1),
            flags: BrainFlags(
                offlineQueued: s.offline ? 3 : nil, indexRebuilding: s.rebuilding, embeddingDown: s.embeddingDown))
    }

    public func room(_ id: String) async throws -> RoomDetail {
        guard let r = list.first(where: { $0.id == id }), r.mounted else {
            throw BrainFailure("This room is sealed. Open it to see its memories.", code: "sealed")
        }
        let c = r.counts
        let n = c?.records ?? 0
        let status = StatusCounts(
            candidate: c?.waiting ?? 0, active: Int(Double(n) * 0.93), superseded: Int(Double(n) * 0.04),
            archived: Int(Double(n) * 0.03), tombstoned: n > 100 ? 2 : 0)
        var rows = [SyncRow(device: "Mac Studio (sample)", at: "now")]
        if r.mode != .localOnly {
            rows.append(SyncRow(device: "MacBook (sample)", at: "1 min ago"))
            rows.append(SyncRow(device: "iPhone (sample)", at: "4 min ago"))
        }
        if r.id == "workan-space" {
            rows[1] = SyncRow(device: "MacBook (sample)", at: "3 h ago", state: .lag, lag: "3 h")
        }
        let cost: RoomCost? =
            r.provider == .approvedCloud
            ? RoomCost(
                month: r.id == "workan-space" ? 31.8 : 14.2, cap: 30,
                series: [1, 1.2, 0.8, 1.4, 1, 0.9, 1.3, 1.1, 0.7, 1.2, 1, 1.4, 0.9, 1.1]) : nil
        return RoomDetail(
            room: r, status: status, sync: rows, backup: r.mode == .localOnly ? nil : "3 h ago", cost: cost)
    }

    public func openRoom(_ id: String) async throws {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let r = list[i]
        list[i] = RoomSummary(
            id: r.id, name: r.name, kind: r.kind, mode: r.mode, provider: r.provider, mounted: true,
            lease: Lease(left: "24 h", fraction: 1), counts: RoomCounts(records: 320, byType: Self.types(320)))
    }

    public func sealRoom(_ id: String) async throws {
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let r = list[i]
        list[i] = RoomSummary(
            id: r.id, name: r.name, kind: r.kind, mode: r.mode, provider: r.provider, mounted: false, lease: r.lease)
    }

    public func createRoom(_ draft: NewRoomDraft) async throws -> RoomSummary {
        let slug = draft.name.lowercased().replacingOccurrences(of: " ", with: "-")
        let r = RoomSummary(
            id: slug, name: draft.name, kind: draft.kind, mode: draft.mode, provider: draft.provider, mounted: true,
            lease: Lease(left: "24 h", fraction: 1), counts: RoomCounts(records: 0))
        list.append(r)
        return r
    }

    public func clearPaused() async throws { scenario.paused = false }

    // MARK: sample world

    private static func types(_ n: Int) -> [TypeShare] {
        let w: [(String, Double)] = [
            ("rule", 0.2), ("decision", 0.16), ("fact", 0.34), ("state", 0.1), ("task", 0.1), ("summary", 0.05),
            ("preference", 0.04), ("identity", 0.01),
        ]
        return w.map { TypeShare($0.0, Int(Double(n) * $0.1)) }
    }

    private static func room(
        _ id: String, _ name: String, _ kind: RoomKind, _ mode: StorageMode, _ provider: ProviderClass,
        records: Int, waiting: Int = 0, conflicts: Int = 0, models: Int = 1, sync: String = "2 s ago",
        lease: Lease = Lease(left: "19 h", fraction: 0.8)
    ) -> RoomSummary {
        RoomSummary(
            id: id, name: name, kind: kind, mode: mode, provider: provider, mounted: true, lease: lease,
            counts: RoomCounts(
                records: records, waiting: waiting, conflicts: conflicts, models: models, lastSync: sync,
                byType: types(records)))
    }

    private static func world() -> [RoomSummary] {
        [
            room(
                "ainkrad", "Ainkrad", .product, .synced, .approvedCloud, records: 1900, waiting: 3, models: 2),
            room("global-safe", "Global safe", .shared, .synced, .local, records: 14),
            room("personal", "Personal", .personal, .localOnly, .local, records: 240, sync: "now"),
            room(
                "workan-space", "Workan space", .product, .synced, .approvedCloud, records: 820, conflicts: 1,
                models: 2, lease: Lease(left: "5 h", fraction: 0.21, state: .expiring)),
            room("voutra", "Voutra", .product, .synced, .local, records: 410),
            room(
                "automotive-ai", "AutomotiveAi", .employer, .localBackup, .local, records: 1130, waiting: 1,
                sync: "now"),
            room("optimus", "Optimus", .employer, .localOnly, .local, records: 640, sync: "now"),
            RoomSummary(
                id: "althaqeel", name: "Althaqeel", kind: .employer, mode: .localOnly, provider: .local,
                mounted: false, lease: Lease(left: "expired", fraction: 0, state: .expired)),
            room("ulynk", "Ulynk", .client, .localBackup, .local, records: 188, sync: "now"),
        ]
    }

    private static let tiles: [HealthTile] = [
        HealthTile("isolation", "Isolation", .ok, meter: 100, "0 leaks in 1,000 test queries"),
        HealthTile("speed", "Speed", .ok, meter: 78, "Local search 212 ms, target 300 ms"),
        HealthTile("sync", "Sync", .ok, meter: 92, "Two devices agree, last 2 s ago"),
        HealthTile("freshness", "Freshness", .warn, meter: 64, "9% of memories are past their review date"),
        HealthTile("index", "Search index", .ok, meter: 100, "Up to date, 8 min ago"),
        HealthTile("restore", "Restore drill", .warn, meter: 55, "Last drill 41 days ago, due now"),
        HealthTile("keys", "Key rotation", .ok, meter: 88, "Rotated 12 days ago"),
        HealthTile("providers", "Provider rules", .ok, meter: 100, "All cloud approvals in date"),
    ]

    private static let needs: [NeedItem] = [
        NeedItem(.waiting, room: "ainkrad", n: 3, "memories wait for you"),
        NeedItem(.waiting, room: "automotive-ai", n: 1, "memories wait for you"),
        NeedItem(.conflict, room: "workan-space", n: 1, "conflict to settle"),
        NeedItem(.blocked, room: "automotive-ai", n: 1, "note blocked: a secret was found"),
        NeedItem(.check, n: 1, "check is due: restore drill"),
        NeedItem(.unclassified, n: 4, "captures have no room yet"),
    ]
}
#endif
