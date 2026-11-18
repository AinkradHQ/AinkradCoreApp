#if DEBUG
import Foundation

/// Debug only: an invented retention count, clean-up run and room card. No real memory text.
extension SampleBrainService {
    public func retentionPreview(room: String, days: Int) async throws -> RetentionPreview {
        if scenario.error { throw BrainFailure("Core did not answer.", code: "sample_unreachable") }
        let n = days <= 30 ? 412 : days <= 90 ? 137 : 0
        return RetentionPreview(days: days, wouldCompact: n, chars: n * 3_000)
    }

    public func startRedistil(room: String, dryRun: Bool) async throws -> RedistilRun {
        if scenario.error { throw BrainFailure("Core did not answer.", code: "sample_unreachable") }
        if scenario.empty { throw BrainFailure("There is nothing to clean up in this room yet.", code: "nothing_to_redistil") }
        let run = RedistilRun(id: "rd-1", dryRun: dryRun, state: .running, total: 12)
        careRun = run
        return run
    }

    public func redistilStatus(room: String) async throws -> RedistilRun? {
        guard var r = careRun else { return nil }
        if r.isOpen {
            r.read = min(r.total, r.read + 6)
            if r.read >= r.total {
                r.state = .done
                r.kept = 84
                r.archived = 1_203
                r.summary = r.dryRun ? "Would keep 84 facts, archive 1,203 items" : "Kept 84 facts, archived 1,203 items"
                // The sample's newest change set stands in for the clean-up's, so Undo works end to end.
                r.change = r.dryRun ? nil : "chg-4"
            }
            careRun = r
        }
        return r
    }

    public func cancelRedistil(room: String) async throws -> RedistilRun {
        guard var r = careRun, r.isOpen else {
            throw BrainFailure("No clean-up is running in this room.", code: "not_found")
        }
        r.state = .cancelled
        careRun = r
        return r
    }

    public func roomCard(room: String) async throws -> RoomCard? {
        if scenario.error { throw BrainFailure("Core did not answer.", code: "sample_unreachable") }
        if scenario.empty { return nil }
        return RoomCard(
            text: """
                Sample room: a shop used to try the Brain.

                Rules
                - Sample: never deploy on Friday.
                - Sample: short commit subjects.

                Decisions
                - Sample: releases ship from the release branch.

                Facts
                - Sample: the build takes 4 minutes.
                """, records: 4)
    }
}
#endif
