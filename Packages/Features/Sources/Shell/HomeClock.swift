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

/// How the analog clock's second hand moves (home-clocks, Settings → Clocks).
public enum SecondHand: String, CaseIterable, Sendable {
    case smooth, ticking, off
    public var title: String {
        switch self {
        case .smooth: "Smooth"
        case .ticking: "Ticking"
        case .off: "Off"
        }
    }
    /// What the dial draws: Reduce Motion (or a hidden Home, where nothing should run every frame) turns Smooth into
    /// Ticking. Off stays off.
    public func shown(reduceMotion: Bool, live: Bool = true) -> SecondHand {
        self == .smooth && (reduceMotion || !live) ? .ticking : self
    }
}

/// The two clock settings, kept on this Mac.
@MainActor @Observable public final class ClockPrefs {
    public static let shared = ClockPrefs()
    public var secondHand: SecondHand {
        didSet { defaults.set(secondHand.rawValue, forKey: Self.handKey) }
    }
    /// The digital clock shows seconds after the minutes.
    public var showsSeconds: Bool {
        didSet { defaults.set(showsSeconds, forKey: Self.secondsKey) }
    }
    @ObservationIgnored private let defaults: UserDefaults
    static let handKey = "ainkrad.core.home.clock.secondHand"
    static let secondsKey = "ainkrad.core.home.clock.showsSeconds"

    public init(defaults: UserDefaults = .coreStore()) {
        self.defaults = defaults
        secondHand = defaults.string(forKey: Self.handKey).flatMap(SecondHand.init) ?? .smooth
        showsSeconds = defaults.bool(forKey: Self.secondsKey)
    }
}

/// The words and angles the clocks show, as pure functions of a date (tested without a view).
enum ClockFace {
    /// Hour, minute and second hand angles in degrees, clockwise from 12. With the second hand off the minute hand moves
    /// once a minute; otherwise it creeps with the seconds. Ticking seconds are whole; Smooth gets the fraction.
    static func angles(_ date: Date, calendar: Calendar = .current, hand: SecondHand) -> (
        hour: Double, minute: Double, second: Double
    ) {
        let c = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let h = Double((c.hour ?? 0) % 12)
        let m = Double(c.minute ?? 0)
        let whole = Double(c.second ?? 0)
        let s = hand == .smooth ? whole + Double(c.nanosecond ?? 0) / 1e9 : whole
        return ((h + m / 60) * 30, hand == .off ? m * 6 : (m + s / 60) * 6, s * 6)
    }

    /// "10:09" (and "37" when seconds are on), in 24-hour or 12-hour time as the Mac is set. Hours keep two digits in
    /// 24-hour time, as the mockup's "09:09".
    static func time(_ date: Date, calendar: Calendar = .current, h24: Bool = uses24Hours) -> (
        hours: String, minutes: String, seconds: String
    ) {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let h = c.hour ?? 0
        let hours = h24 ? two(h) : String(h % 12 == 0 ? 12 : h % 12)
        return (hours, two(c.minute ?? 0), two(c.second ?? 0))
    }

    /// The last part of a time zone's name, readable: "Africa/Cairo" is Cairo, "America/New_York" is New York.
    static func city(_ zone: TimeZone) -> String {
        (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    /// The Large digital clock's places: home first, then UTC (left out when home is UTC).
    static func places(home: TimeZone) -> [(name: String, note: String?, zone: TimeZone)] {
        let utc = TimeZone(identifier: "UTC")!
        var out: [(String, String?, TimeZone)] = [(city(home), "home", home)]
        if !["UTC", "GMT"].contains(home.identifier) { out.append(("UTC", nil, utc)) }
        return out
    }

    static func calendar(in zone: TimeZone) -> Calendar {
        var c = Calendar.current
        c.timeZone = zone
        return c
    }

    static var uses24Hours: Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    private static func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}
