import Foundation

/// Room care on a real Core: the retention count, the clean-up run and the room card. Person-only routes that need the
/// room open. Starting the real clean-up is a step-up route: the caller asks for Touch ID around it.
extension CoreBrainService {
    public var servesCare: Bool { true }

    public func retentionPreview(room: String, days: Int) async throws -> RetentionPreview {
        let w = try await care { try await routes.retentionPreview(room: room, days: days) }
        return RetentionPreview(days: w.days, wouldCompact: w.wouldCompact, chars: w.chars)
    }

    public func startRedistil(room: String, dryRun: Bool) async throws -> RedistilRun {
        Self.run(try await care { try await routes.redistil(room: room, dryRun: dryRun) })
    }

    public func redistilStatus(room: String) async throws -> RedistilRun? {
        try await care { try await routes.redistils(room: room) }.first.map(Self.run)
    }

    public func cancelRedistil(room: String) async throws -> RedistilRun {
        Self.run(try await care { try await routes.cancelRedistil(room: room) })
    }

    /// nil when the Core has no card route (404), so the Overview shows no card instead of an error.
    public func roomCard(room: String) async throws -> RoomCard? {
        do {
            let w = try await routes.card(room: room)
            return RoomCard(text: w.text, records: w.ids.count, complete: w.complete)
        } catch let e as BrainHTTPError {
            if e.status == 404 { return nil }
            throw Self.failure(e)
        }
    }

    static func run(_ w: RedistilWire) -> RedistilRun {
        RedistilRun(
            id: w.id, dryRun: w.dryRun, state: RedistilState(w.state), total: w.total, read: w.read,
            kept: w.kept.map { $0 + (w.newFacts ?? 0) }, archived: w.archived, summary: w.summary, change: w.change,
            detail: w.detail ?? "")
    }

    /// The clean-up's own refusals in words; every other failure is worded like any Brain call.
    private func care<T>(_ op: () async throws -> T) async throws -> T {
        do { return try await op() } catch let e as BrainHTTPError {
            switch e.code {
            case "nothing_to_redistil":
                throw BrainFailure("There is nothing to clean up in this room yet.", code: e.code)
            case "redistil_busy":
                throw BrainFailure("Another room is being cleaned up. Try again when it finishes.", code: e.code)
            case "redistil_open":
                throw BrainFailure("This room is being cleaned up already.", code: e.code)
            case "redistil_committing":
                throw BrainFailure("It is saving its result and can no longer be cancelled.", code: e.code)
            default: throw Self.failure(e)
            }
        }
    }
}
