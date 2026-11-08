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
    /// One room's Inbox: waiting memories, conflicts and blocked notes. Only for a mounted room.
    func inbox(room: String) async throws -> RoomInbox
    /// The unclassified inbox. It is not a room, so it needs no mounted room.
    func captures() async throws -> [Capture]
    /// Applies one Inbox change (the caller has already asked for Touch ID where it is needed).
    func perform(_ action: InboxAction) async throws
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
