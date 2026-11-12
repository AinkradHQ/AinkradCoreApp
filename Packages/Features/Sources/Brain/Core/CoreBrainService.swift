import BrainImport
import Foundation

/// The real Brain service: rooms and the open step on a Core that has the `brain` module (M1). Overview is thin and
/// Activity, Checks and the Inbox are not served yet (M3), so they answer empty and the pane says "Coming later".
public final class CoreBrainService: BrainService, @unchecked Sendable {
    public let routes: BrainRoutes
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    /// When each room this Mac opened ends its lease (the room list only says open or not).
    private var leases: [String: Date] = [:]

    public init(transport: any BrainTransport, now: @escaping @Sendable () -> Date = { Date() }) {
        routes = BrainRoutes(transport: transport)
        self.now = now
    }

    public var isSample: Bool { false }
    public var importRoutes: BrainRoutes? { routes }

    // MARK: status

    public func setup() async throws -> BrainSetup {
        let s: BrainStatusWire
        do { s = try await routes.status() } catch let e as BrainHTTPError where e.status == 404 || e.status == 501 {
            return .absent
        }
        guard s.present else { return .absent }
        switch s.key {
        case "ok": break
        case "locked_mode0": return .locked("Keys and secrets are off on this Core, so the Brain is locked.")
        case "missing": return .locked("The Brain has no key yet.")
        default: return .locked("The Brain is not available right now.")
        }
        return s.rooms == 0 ? .notSetUp : .ready
    }

    // MARK: rooms

    public func rooms() async throws -> [RoomSummary] {
        try await wrap { try await routes.rooms().map(summary) }
    }

    func summary(_ r: RoomViewWire) -> RoomSummary {
        RoomSummary(
            id: r.id, name: r.name, kind: Self.kind(r.kind), mode: .synced, provider: .approvedCloud, mounted: r.open,
            lease: r.open ? lease(for: r.id) : Lease(left: "0 min", fraction: 0, state: .expired),
            counts: RoomCounts(records: r.sources))
    }

    static func kind(_ wire: String) -> RoomKind {
        switch wire {
        case "personal": .personal
        case "product": .product
        case "employer": .employer
        case "client": .client
        default: .shared
        }
    }

    func lease(for id: String) -> Lease {
        guard let until = lock.withLock({ leases[id] }) else { return Lease(left: "a while", fraction: 1) }
        let secs = until.timeIntervalSince(now())
        if secs <= 0 { return Lease(left: "0 min", fraction: 0, state: .expired) }
        let left = secs >= 3600 ? "\(Int((secs / 3600).rounded())) h" : "\(max(1, Int((secs / 60).rounded(.up)))) min"
        return Lease(left: left, fraction: min(1, secs / 3600), state: secs < 600 ? .expiring : .ok)
    }

    public func room(_ id: String) async throws -> RoomDetail {
        let all = try await rooms()
        guard let r = all.first(where: { $0.id == id }) else {
            throw BrainFailure("This room is gone.", code: "no_room")
        }
        return RoomDetail(room: r, status: StatusCounts())
    }

    public func openRoom(_ id: String) async throws {
        let opened = try await wrap { try await routes.openRoom(id) }
        if let until = Self.parse(opened.openUntil) { lock.withLock { leases[id] = until } }
    }

    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    public func sealRoom(_ id: String) async throws {
        throw BrainFailure("A room closes by itself when its key ends.", code: "no_route")
    }
    public func createRoom(_ draft: NewRoomDraft) async throws -> RoomSummary {
        throw BrainFailure("Rooms are made by an import.", code: "no_route")
    }
    public func clearPaused() async throws {}

    // MARK: overview and the later tabs

    public func overview() async throws -> BrainOverview {
        BrainOverview(
            health: .healthy, tiles: [], needs: [], speed: [],
            facts: BrainFacts(staleShare: 0, recall: "", secretBlocks: 0, flaggedSources: 0))
    }
    public func activity(limit: Int) async throws -> ActivityPage { ActivityPage(events: []) }
    public func liveActivity() async -> AsyncStream<ActivityEvent> { AsyncStream { $0.finish() } }
    public func egress(room: String) async throws -> [EgressCall] { [] }
    public func checks() async throws -> ChecksReport { ChecksReport(items: [], pilot: []) }
    public func runCheck(
        _ id: String, options: CheckRunOptions, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CheckItem {
        throw BrainFailure("Checks come later.", code: "not_served")
    }
    public func inbox(room: String) async throws -> RoomInbox { RoomInbox(room: room) }
    public func captures() async throws -> [Capture] { [] }
    public func perform(_ action: InboxAction) async throws {
        throw BrainFailure("The Inbox comes later.", code: "not_served")
    }

    // MARK: sync, sources, search, rules

    public func syncStatus() async throws -> SyncStatusWire { try await wrap { try await routes.syncStatus() } }
    public func sources() async throws -> [SourceWire] { try await wrap { try await routes.sources() } }
    public func putSource(_ s: SourceWire, enabled: Bool?, cursor: SourceCursor?) async throws -> SourceWire {
        try await wrap { try await routes.putSource(s, enabled: enabled, cursor: cursor) }
    }
    public func syncNow() async throws -> SyncResultWire { try await wrap { try await routes.sync() } }
    public func search(room: String, query: String) async throws -> [SearchHit] {
        try await wrap { try await routes.search(room: room, query: query) }
    }
    public func rules() async throws -> [RuleWire] { try await wrap { try await routes.rules() } }
    public func setRule(_ id: Int, enabled: Bool) async throws -> RuleWire {
        try await wrap { try await routes.setRule(id, enabled: enabled) }
    }

    // MARK: errors

    /// A Core refusal in words; anything else (offline, Touch ID cancelled, auth) passes through for the host.
    func wrap<T>(_ op: () async throws -> T) async throws -> T {
        do { return try await op() } catch let e as BrainHTTPError { throw Self.failure(e) }
    }

    static func failure(_ e: BrainHTTPError) -> BrainFailure {
        let sentence =
            switch e.code {
            case "mixed_employers": "Two employers are in one room. Split it first."
            case "unsorted_not_a_room": "Unsorted is not a room. Move its items to one."
            case "batch_too_large": "That was too much to send at once."
            case "room_unavailable": "The room could not be opened."
            case "room_closed": "Open this room first, then search it."
            default:
                e.status == 409
                    ? "That cannot be done right now. \(e.message)".trimmingCharacters(in: .whitespaces)
                    : e.status == 404 ? "That is not there any more." : "The Core refused this. Nothing was changed."
            }
        return BrainFailure(sentence, code: e.code)
    }
}
