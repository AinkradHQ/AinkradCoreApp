import Foundation

/// `GET /activity` (E9-2): what the Brain is doing, in counts. It needs a Core with API minor 95.
public struct BrainActivityWire: Codable, Sendable, Equatable {
    public struct Need: Codable, Sendable, Equatable {
        public var kind: String
        public var rooms: Int
    }
    /// `locked`, `needs_you`, `working` or `idle`.
    public var state: String
    /// `ok` or `attention`.
    public var health: String
    public var rooms: Int
    public var distilling: Int
    public var queued: Int
    public var overviews: Int
    public var failed: Int
    public var needs: [Need]
    public var lastDoneAt: String?

    enum CodingKeys: String, CodingKey {
        case state, health, rooms, distilling, queued, overviews, failed, needs
        case lastDoneAt = "last_done_at"
    }
}

extension BrainRoutes {
    public func activity() async throws -> BrainActivityWire { try await call("GET", "/activity") }
}
