import Foundation

/// A room's written overview on a real Core (API minor 74, `/rooms/{room}/overview…`).
extension BrainRoutes {
    func overview(room: String) async throws -> RoomOverview {
        try await call("GET", "/rooms/\(Self.seg(room))/overview")
    }

    /// 202 when queued, 200 when nothing was (`cloud_off`, `needs_account`): both answer the view.
    func writeOverview(room: String) async throws -> RoomOverview {
        try await call("POST", "/rooms/\(Self.seg(room))/overview/write")
    }

    func setInstructions(room: String, text: String?, approved: Bool) async throws -> RoomOverview {
        try await call(
            "PATCH", "/rooms/\(Self.seg(room))/overview/instructions", InstructionsBody(text: text, approved: approved))
    }
}

struct InstructionsBody: Encodable {
    let text: String?
    let approved: Bool
}

/// The Core's overview routes behind `RoomOverviewService`. Failures are worded like every other Brain call.
struct CoreRoomOverview: RoomOverviewService {
    let routes: BrainRoutes

    func roomOverview(room: String) async throws -> RoomOverview {
        try await wrap { try await routes.overview(room: room) }
    }

    func writeOverview(room: String) async throws {
        do { _ = try await routes.writeOverview(room: room) } catch let e as BrainHTTPError
            where e.code == "overview_open"
        {
            // Already being written: the poll shows it.
        } catch let e as BrainHTTPError { throw Self.failure(e) }
    }

    func setInstructions(room: String, text: String?, approved: Bool) async throws {
        _ = try await wrap { try await routes.setInstructions(room: room, text: text, approved: approved) }
    }

    private func wrap<T>(_ op: () async throws -> T) async throws -> T {
        do { return try await op() } catch let e as BrainHTTPError { throw Self.failure(e) }
    }

    static func failure(_ e: BrainHTTPError) -> BrainFailure {
        switch e.code {
        case "not_written": BrainFailure("There is no overview to change yet. Write it first.", code: e.code)
        case "instructions_too_long":
            BrainFailure("The instructions are too long. Keep them under 8,000 characters.", code: e.code)
        case "overview_open": BrainFailure("This overview is being written already.", code: e.code)
        default: CoreBrainService.failure(e)
        }
    }
}

extension CoreBrainService {
    public var overviewService: (any RoomOverviewService)? { CoreRoomOverview(routes: routes) }
}
