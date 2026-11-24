import CoreUI
import SwiftUI

/// The three steps of a write and where each stands, mapped from the Core's `stage`.
struct OverviewSteps: Equatable {
    enum Mark { case done, active, pending }
    var pick: Mark
    var write: Mark
    var check: Mark
    /// Why it waits or retries, in one line; nil while it simply works.
    var wait: String?
    /// Queued or waiting for a runner: nothing is being written yet, so no clock.
    var waiting: Bool { stageWaits }
    private var stageWaits = false

    /// Nil when the Core sent no stage (an older Core): the caller keeps the plain "Writing…" line.
    init?(_ stage: OverviewStage?, picked: Int? = nil) {
        switch stage {
        case nil: return nil
        case .queued:
            self.init(.active, .pending, .pending, "Waiting for its turn (one room at a time)")
            stageWaits = true
        case .waitingRunner:
            let text = "Waiting for a runner with a sandbox to come online"
            // A runner is needed once the items are chosen, so a known count means the choosing is behind us.
            if picked != nil {
                self.init(.done, .active, .pending, text)
            } else {
                self.init(.active, .pending, .pending, text)
            }
            stageWaits = true
        case .picking: self.init(.active, .pending, .pending, nil)
        case .reading: self.init(.done, .done, .active, nil)
        case .retrying: self.init(.done, .active, .pending, "The first answer could not be used. Trying once more.")
        case .starting, .writing, .other: self.init(.done, .active, .pending, nil)
        }
    }

    private init(_ a: Mark, _ b: Mark, _ c: Mark, _ wait: String?) {
        pick = a
        write = b
        check = c
        self.wait = wait
    }

    /// "1:05" for 65 seconds; minutes are not capped, a negative span reads 0:00.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
