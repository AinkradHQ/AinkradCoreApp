import Foundation

// The Brain's shapes, in the words the screens use. They mirror the prototype's sample world (brain-data.js) and the
// BM-89 health fields; when Core serves the Brain, the generated client maps onto these in one file (`BrainService`).
// Nothing here ever holds a record title, snippet or query: counts, names and codes only (BM-00 I-8).

/// Where a room's memories live. Plain words first; the id is hover help.
public enum StorageMode: String, Sendable, CaseIterable, Hashable {
    case localOnly = "local-only"
    case localBackup = "local-backup"
    case synced

    public var label: String {
        switch self {
        case .localOnly: "This Mac only"
        case .localBackup: "Backed up"
        case .synced: "Synced"
        }
    }
    /// One sentence for the New room sheet and the room view.
    public var plain: String {
        switch self {
        case .localOnly: "Never leaves this Mac. No backup."
        case .localBackup: "Server keeps a copy it cannot read."
        case .synced: "Your Macs share it."
        }
    }
    /// What the room view says about who can read what.
    public var story: String {
        switch self {
        case .localOnly: "Not visible to cloud agents, not backed up. It stays on this Mac."
        case .localBackup: "A backup copy is kept on the server. The server cannot read it."
        case .synced:
            "The remote Core holds the canonical copy. An approved cloud model may read what a search returns."
        }
    }
    /// Leaving this Mac widens who could reach the room, so it asks for Touch ID.
    var widens: Bool { self != .localOnly }
}

public enum ProviderClass: String, Sendable, CaseIterable, Hashable {
    case local
    case approvedCloud = "approved-cloud"
    case unapproved

    /// Hover help: the technical term and what it means.
    public var help: String {
        switch self {
        case .local: "Local models only: nothing from this room is ever sent to a cloud model."
        case .approvedCloud: "Approved cloud: you approved named cloud models to read this room. Each call is logged."
        case .unapproved: "Not approved: no cloud model may read this room."
        }
    }

    public var label: String {
        switch self {
        case .local: "Local models only"
        case .approvedCloud: "Cloud allowed"
        case .unapproved: "Not approved"
        }
    }
}

public enum RoomKind: String, Sendable, CaseIterable, Hashable {
    case product, personal, shared, employer, client, test

    public var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    /// Employer and client rooms carry a persistent chip on every screen.
    public var chipLabel: String? {
        switch self {
        case .employer: "Employer"
        case .client: "Client"
        default: nil
        }
    }
}

/// How a key lease stands. Without a lease a device cannot read the saved copy.
public struct Lease: Sendable, Hashable {
    public enum State: String, Sendable { case ok, expiring, expired }
    public var left: String
    public var fraction: Double
    public var state: State
    public init(left: String, fraction: Double, state: State = .ok) {
        self.left = left
        self.fraction = fraction
        self.state = state
    }
}

public struct StatusCounts: Sendable, Hashable {
    public var candidate = 0
    public var active = 0
    public var superseded = 0
    public var archived = 0
    public var tombstoned = 0
    public init(candidate: Int = 0, active: Int = 0, superseded: Int = 0, archived: Int = 0, tombstoned: Int = 0) {
        self.candidate = candidate
        self.active = active
        self.superseded = superseded
        self.archived = archived
        self.tombstoned = tombstoned
    }
    var total: Int { candidate + active + superseded + archived + tombstoned }
}

/// How many memories of each type, for the segmented bar. Counts only.
public struct TypeShare: Sendable, Hashable, Identifiable {
    public var id: String { type }
    public let type: String
    public let count: Int
    public init(_ type: String, _ count: Int) {
        self.type = type
        self.count = count
    }
}

/// The numbers a mounted room shows. A sealed room has none (Q2): `RoomSummary.counts` is nil for it.
public struct RoomCounts: Sendable, Hashable {
    public var records: Int
    public var waiting: Int
    public var conflicts: Int
    public var models: Int
    public var lastSync: String
    public var byType: [TypeShare]
    public init(
        records: Int, waiting: Int = 0, conflicts: Int = 0, models: Int = 1, lastSync: String = "now",
        byType: [TypeShare] = []
    ) {
        self.records = records
        self.waiting = waiting
        self.conflicts = conflicts
        self.models = models
        self.lastSync = lastSync
        self.byType = byType
    }
}

/// One room as the cross-room Rooms overview sees it: names, mode, counts, health. No titles, no snippets.
public struct RoomSummary: Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var kind: RoomKind
    public var mode: StorageMode
    public var provider: ProviderClass
    public var mounted: Bool
    public var lease: Lease
    /// nil unless the room is mounted on this Mac (Q2). The initialiser enforces it.
    public private(set) var counts: RoomCounts?

    public init(
        id: String, name: String, kind: RoomKind, mode: StorageMode, provider: ProviderClass, mounted: Bool,
        lease: Lease, counts: RoomCounts? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.mode = mode
        self.provider = provider
        self.mounted = mounted
        self.lease = lease
        self.counts = mounted ? counts : nil
    }

    /// Why nothing of this room may be on screen, or nil when it may be.
    public var lock: RoomLock? {
        if !mounted { return .sealed }
        if lease.state == .expired { return .expired }
        return nil
    }
    /// What the hover help says: the id is for hover only.
    public var help: String { "Room id: \(id)" }
}

public enum RoomLock: Sendable, Hashable {
    case sealed, expired
    public var sentence: String {
        switch self {
        case .sealed: "This room is sealed. Open it to see its memories."
        case .expired: "The key lease for this room ended. Renew it to see its memories."
        }
    }
}

public struct SyncRow: Sendable, Hashable, Identifiable {
    public enum State: String, Sendable { case ok, lag }
    public var id: String { device }
    public let device: String
    public let at: String
    public let state: State
    public let lag: String
    public init(device: String, at: String, state: State = .ok, lag: String = "") {
        self.device = device
        self.at = at
        self.state = state
        self.lag = lag
    }
}

public struct RoomCost: Sendable, Hashable {
    public var month: Double
    public var cap: Double
    public var series: [Double]
    public init(month: Double, cap: Double, series: [Double]) {
        self.month = month
        self.cap = cap
        self.series = series
    }
    public var capReached: Bool { cap > 0 && month >= cap }
}

/// What one room view shows: exactly one room. Cleared the moment the viewing room changes.
public struct RoomDetail: Sendable, Hashable {
    public var room: RoomSummary
    public var status: StatusCounts
    public var sync: [SyncRow]
    public var backup: String?
    public var cost: RoomCost?
    public init(
        room: RoomSummary, status: StatusCounts, sync: [SyncRow] = [], backup: String? = nil, cost: RoomCost? = nil
    ) {
        self.room = room
        self.status = status
        self.sync = sync
        self.backup = backup
        self.cost = cost
    }
}

/// Healthy, needs you, or paused. The service decides; the UI never computes health (BM-85, BM-89).
public enum BrainHealth: String, Sendable, Hashable { case healthy, needsYou, paused }

public struct HealthTile: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable { case ok, warn, bad, off }
    public let id: String
    public let name: String
    public let status: Status
    public let meter: Double
    public let text: String
    public init(_ id: String, _ name: String, _ status: Status, meter: Double, _ text: String) {
        self.id = id
        self.name = name
        self.status = status
        self.meter = meter
        self.text = text
    }
}

public enum NeedKind: String, Sendable, Hashable { case waiting, conflict, blocked, check, unclassified, paused }

/// One thing that waits for you. `room` is a room id, or nil for something that belongs to no room.
public struct NeedItem: Sendable, Hashable, Identifiable {
    public var id: String { "\(kind.rawValue)-\(room ?? "none")" }
    public let kind: NeedKind
    public let room: String?
    public let n: Int
    public let text: String
    public init(_ kind: NeedKind, room: String? = nil, n: Int, _ text: String) {
        self.kind = kind
        self.room = room
        self.n = n
        self.text = text
    }
    /// The tab this need opens.
    var tab: BrainTab { kind == .check || kind == .paused ? .checks : .inbox }
}

/// Live conditions that change what the screens say.
public struct BrainFlags: Sendable, Hashable {
    /// nil: online. A number: this Mac is offline and holds that many changes.
    public var offlineQueued: Int?
    public var indexRebuilding = false
    public var embeddingDown = false
    public init(offlineQueued: Int? = nil, indexRebuilding: Bool = false, embeddingDown: Bool = false) {
        self.offlineQueued = offlineQueued
        self.indexRebuilding = indexRebuilding
        self.embeddingDown = embeddingDown
    }
}

public struct BrainFacts: Sendable, Hashable {
    public var staleShare: Int
    public var recall: String
    public var secretBlocks: Int
    public var flaggedSources: Int
    public init(staleShare: Int, recall: String, secretBlocks: Int, flaggedSources: Int) {
        self.staleShare = staleShare
        self.recall = recall
        self.secretBlocks = secretBlocks
        self.flaggedSources = flaggedSources
    }
}

public struct BrainOverview: Sendable, Hashable {
    public var health: BrainHealth
    public var tiles: [HealthTile]
    public var needs: [NeedItem]
    /// Room ids whose search is stopped while paused.
    public var pausedRooms: [String]
    /// Local search p95 in ms, newest last, against `speedTarget`.
    public var speed: [Double]
    public var speedTarget: Double
    public var facts: BrainFacts
    public var flags: BrainFlags
    public init(
        health: BrainHealth, tiles: [HealthTile], needs: [NeedItem], pausedRooms: [String] = [], speed: [Double],
        speedTarget: Double = 300, facts: BrainFacts, flags: BrainFlags = BrainFlags()
    ) {
        self.health = health
        self.tiles = tiles
        self.needs = needs
        self.pausedRooms = pausedRooms
        self.speed = speed
        self.speedTarget = speedTarget
        self.facts = facts
        self.flags = flags
    }
}

/// What a new room is made with. The quick path is `NewRoomDraft.quick`: this Mac only, local models.
public struct NewRoomDraft: Sendable, Hashable {
    public var name: String
    public var kind: RoomKind
    public var mode: StorageMode
    public init(name: String, kind: RoomKind = .product, mode: StorageMode = .localOnly) {
        self.name = name
        self.kind = kind
        self.mode = mode
    }
    public static func quick(name: String) -> NewRoomDraft { NewRoomDraft(name: name) }
    /// Employer and client rooms start with local models until a cloud provider is approved.
    var provider: ProviderClass { .local }
}

public enum BrainTab: String, Sendable, CaseIterable, Hashable {
    case overview, rooms, inbox, activity, checks
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Why the Brain has nothing to show, in plain words.
public enum BrainLoad: Equatable {
    case loading, ready
    /// Core does not serve the Brain. Release says so plainly; nothing pretends to be live.
    case unavailable
    case failed(String)
}
