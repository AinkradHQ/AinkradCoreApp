import BrainImport
import Foundation

/// What the Brain screens ask for. Method names mirror the screens, so swapping the sample service for the generated Core
/// client (BM-89 and the route stories) is one new file that conforms to this. Until Core serves memory routes nothing
/// here is a route: the only conformer is `SampleBrainService` (Debug), and Release has none.
public protocol BrainService: Sendable {
    /// True for stand-in data. The pane then says so on every screen.
    var isSample: Bool { get }
    /// Every room this Mac knows: mounted ones with counts, sealed ones with name and mode only.
    func rooms() async throws -> [RoomSummary]
    /// The Overview: health, what needs you, speed.
    func overview() async throws -> BrainOverview
    /// One room's view. Only for a mounted room.
    func room(_ id: String) async throws -> RoomDetail
    /// Mounts a sealed room (the caller has already asked for Touch ID).
    func openRoom(_ id: String) async throws
    func sealRoom(_ id: String) async throws
    func createRoom(_ draft: NewRoomDraft) async throws -> RoomSummary
    /// Clears a failed leakage check so cross-room search resumes (the caller has already asked for Touch ID).
    func clearPaused() async throws

    // MARK: Activity and Checks

    /// The newest `limit` events across every mounted room, newest first. Ids and codes only.
    func activity(limit: Int) async throws -> ActivityPage
    /// Events as they happen. Ends when the caller stops reading.
    func liveActivity() async -> AsyncStream<ActivityEvent>
    /// Every model call from one mounted room, allowed or blocked, newest first.
    func egress(room: String) async throws -> [EgressCall]
    func checks() async throws -> ChecksReport
    /// Runs one check and reports progress from 0 to 1. The service decides the result, Paused included.
    func runCheck(
        _ id: String, options: CheckRunOptions, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CheckItem
    /// One room's Inbox: waiting memories, conflicts and blocked notes. Only for a mounted room.
    func inbox(room: String) async throws -> RoomInbox
    /// The unclassified inbox. It is not a room, so it needs no mounted room.
    func captures() async throws -> [Capture]
    /// Applies one Inbox change (the caller has already asked for Touch ID where it is needed).
    func perform(_ action: InboxAction) async throws
    /// What this Core has of the Brain (`GET /status`).
    func setup() async throws -> BrainSetup
    /// The import routes, or nil when the service cannot import (the sample).
    var importRoutes: BrainRoutes? { get }

    // MARK: sync, sources, search, rules (M2)

    func syncStatus() async throws -> SyncStatusWire
    /// Every collector with its switch and cursor.
    func sources() async throws -> [SourceWire]
    /// Switches a collector, or moves its cursor (nil keeps the Core's value).
    func putSource(_ s: SourceWire, enabled: Bool?, cursor: SourceCursor?) async throws -> SourceWire
    /// The Core's own sync (`POST /sync`); the Mac collectors are run by `SyncModel` first.
    func syncNow() async throws -> SyncResultWire
    func search(room: String, query: String) async throws -> [SearchHit]
    /// A room's newest items, newest first. The Core has no route for it yet, so a real Core shows none.
    func latest(room: String) async throws -> [LatestItem]
    func rules() async throws -> [RuleWire]
    /// The caller has already asked for Touch ID.
    func setRule(_ id: Int, enabled: Bool) async throws -> RuleWire

    // MARK: candidates, policy, runner history (M3)

    /// True when this service has the M3 Inbox, policy and history routes; the Inbox tab shows then.
    var servesCandidates: Bool { get }
    /// Every candidate waiting in the open rooms, and what waits for a local model.
    func candidates() async throws -> CandidateInbox
    /// Accepts, edits (then accepts) or rejects one candidate. Returns the candidate as filed, nil for a rejection.
    func decide(_ id: String, room: String, _ decision: CandidateDecision) async throws
    func policy(room: String) async throws -> RoomPolicy
    /// The caller has already asked for Touch ID.
    func setPolicy(room: String, _ change: PolicyChange) async throws -> RoomPolicy
    func runners() async throws -> [RunnerHistory]
    /// Turns a runner's history collection on or off. The caller has already asked for Touch ID when turning it on.
    func setRunnerHistory(_ id: String, enabled: Bool) async throws -> RunnerHistory
}

/// Whether the Brain exists on this Core and whether it has anything yet.
public enum BrainSetup: Sendable, Equatable {
    /// The Core has no Brain module.
    case absent
    /// The module is there but its key is not usable (the text says why, in plain words).
    case locked(String)
    /// The module is there and has no rooms yet.
    case notSetUp
    case ready
}

extension BrainService {
    /// Stand-in services are always set up. The Core service asks `GET /status`.
    public func setup() async throws -> BrainSetup { .ready }
    /// The import routes of a real Core; nil for a stand-in.
    public var importRoutes: BrainRoutes? { nil }
    public func syncStatus() async throws -> SyncStatusWire { SyncStatusWire() }
    public func sources() async throws -> [SourceWire] { [] }
    public func putSource(_ s: SourceWire, enabled: Bool?, cursor: SourceCursor?) async throws -> SourceWire { s }
    public func syncNow() async throws -> SyncResultWire { SyncResultWire() }
    public func search(room: String, query: String) async throws -> [SearchHit] { [] }
    public func latest(room: String) async throws -> [LatestItem] { [] }
    public func rules() async throws -> [RuleWire] { [] }
    public func setRule(_ id: Int, enabled: Bool) async throws -> RuleWire {
        throw BrainFailure("Rules come later.", code: "not_served")
    }
    public var servesCandidates: Bool { false }
    public func candidates() async throws -> CandidateInbox { CandidateInbox() }
    public func decide(_ id: String, room: String, _ decision: CandidateDecision) async throws {
        throw BrainFailure("The Inbox comes later.", code: "not_served")
    }
    public func policy(room: String) async throws -> RoomPolicy { RoomPolicy() }
    public func setPolicy(room: String, _ change: PolicyChange) async throws -> RoomPolicy {
        throw BrainFailure("Room policy comes later.", code: "not_served")
    }
    public func runners() async throws -> [RunnerHistory] { [] }
    public func setRunnerHistory(_ id: String, enabled: Bool) async throws -> RunnerHistory {
        throw BrainFailure("Runner history comes later.", code: "not_served")
    }
}

/// A failure the screens can word.
public struct BrainFailure: Error, Sendable, Equatable {
    public let sentence: String
    /// Code for hover help only.
    public let code: String
    public init(_ sentence: String, code: String) {
        self.sentence = sentence
        self.code = code
    }
}
