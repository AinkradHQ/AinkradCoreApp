import SwiftUI

extension EnvironmentValues {
    /// False while Home is hidden behind the workspace: its clock and widget timelines stop ticking.
    @Entry var homeLive = true
}

/// Ticks every `seconds` while `live`; once, now, while it is not.
struct HomeSchedule: TimelineSchedule {
    let seconds: TimeInterval
    let live: Bool
    func entries(from start: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        live
            ? AnySequence(PeriodicTimelineSchedule(from: start, by: seconds).entries(from: start, mode: mode))
            : AnySequence([start])
    }
}

func homeTicks(_ seconds: TimeInterval, live: Bool) -> HomeSchedule { HomeSchedule(seconds: seconds, live: live) }
