import Foundation

/// What was opened from the launcher, how often, when last, and at which hours: the ranking ⌘K's empty state and its search ties
/// lean on. Kept on this Mac across launches.
struct LauncherUsage: Codable, Equatable {
    struct Stat: Codable, Equatable {
        var count = 0
        var last = Date.distantPast
        var hours = [Int](repeating: 0, count: 24)
    }

    var stats: [String: Stat] = [:]
    /// Past this many entries the least useful are forgotten, so the file never grows without end.
    static let limit = 300

    mutating func record(_ id: String, at date: Date = Date(), calendar: Calendar = .current) {
        var s = stats[id] ?? Stat()
        s.count += 1
        s.last = date
        s.hours[calendar.component(.hour, from: date)] += 1
        stats[id] = s
        if stats.count > Self.limit {
            let keep = stats.keys.sorted {
                score($0, at: date, calendar: calendar) > score($1, at: date, calendar: calendar)
            }
            .prefix(Self.limit)
            stats = stats.filter { keep.contains($0.key) }
        }
    }

    /// How much the person is likely to want `id` now: use count (log, so one habit does not bury the rest), how recent, and how
    /// often it was opened around this hour of the day. Zero when never opened.
    func score(_ id: String, at now: Date = Date(), calendar: Calendar = .current) -> Double {
        guard let s = stats[id], s.count > 0 else { return 0 }
        let days = max(0, now.timeIntervalSince(s.last)) / 86_400
        return log2(Double(s.count) + 1) + 2 * exp(-days / 7) + 2 * hourAffinity(s, at: now, calendar: calendar)
    }

    /// Share of the opens that fell within an hour of this one (0...1.5).
    func hourAffinity(_ s: Stat, at now: Date, calendar: Calendar) -> Double {
        guard s.count > 0 else { return 0 }
        let h = calendar.component(.hour, from: now)
        let near = Double(s.hours[h]) + Double(s.hours[(h + 23) % 24] + s.hours[(h + 1) % 24]) / 2
        return near / Double(s.count)
    }

    /// One plain line saying why this one is suggested.
    func reason(_ id: String, at now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let s = stats[id], s.count > 0 else { return nil }
        let mins = Int(now.timeIntervalSince(s.last) / 60)
        if mins < 90 { return mins < 2 ? "Opened just now" : "Opened \(mins) min ago" }
        if s.count >= 3, hourAffinity(s, at: now, calendar: calendar) >= 0.5 { return "Usually at this hour" }
        return s.count >= 3 ? "Your most used" : "Opened before"
    }
}
