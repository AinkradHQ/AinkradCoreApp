import CoreUI
import Foundation

/// One window of a subscription's plan limit: how much of it is used and when it resets.
struct PlanWindowItem: Equatable, Sendable {
    let name: String
    let utilization: Double
    let resetsAt: Date?
}

/// What the scheduler keeps of an account's health. Only admins are given it, so a device that is not one has `nil` and
/// the card shows none of this.
struct AccountHealthItem: Equatable, Sendable {
    var failStreak: Int64 = 0
    var authStreak: Int64 = 0
    var lastSuccessAt: Date?
    var upstreamClass: String?
    /// The harness's own word: `allowed`, `allowed_warning`, `rejected`.
    var planStatus: String?
    var windows: [PlanWindowItem] = []
}

/// An account's health and load in plain sentences. The codes the Core uses stay in the hover help.
enum AccountHealthWords {
    struct Line: Equatable {
        let text: String
        let tone: Tone
        let symbol: String
        let help: String
    }

    static func live(_ n: Int64?) -> String? {
        guard let n else { return nil }
        return n == 0 ? "No sessions now" : n == 1 ? "1 session now" : "\(n) sessions now"
    }

    static func window(_ name: String) -> String {
        switch name {
        case "five_hour": "5-hour"
        case "seven_day": "7-day"
        default: name.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func line(_ h: AccountHealthItem, now: Date, calendar: Calendar = .current) -> Line {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        func clock(_ d: Date) -> String {
            f.dateFormat = calendar.isDate(d, inSameDayAs: now) ? "HH:mm" : "MMM d, HH:mm"
            return f.string(from: d)
        }
        let codes = [
            "fail_streak \(h.failStreak)", "auth_streak \(h.authStreak)", h.planStatus.map { "plan \($0)" },
            h.upstreamClass.map { "upstream \($0)" },
        ].compactMap { $0 }.joined(separator: ", ")
        func out(_ t: String, _ tone: Tone, _ s: String) -> Line { Line(text: t, tone: tone, symbol: s, help: codes) }

        if h.authStreak > 0 {
            return out("Sign-in failing, \(h.authStreak) in a row", .fail, "person.crop.circle.badge.exclamationmark")
        }
        if h.planStatus == "rejected" {
            let full = h.windows.filter { $0.utilization >= 1 }.compactMap(\.resetsAt).min()
            let until = full ?? h.windows.compactMap(\.resetsAt).filter { $0 > now }.min()
            return out(
                until.map { "Waiting for a limit to reset until \(clock($0))" } ?? "Waiting for a limit to reset",
                .warn, "clock")
        }
        if h.failStreak > 0 { return out("Failing, \(h.failStreak) in a row", .fail, "exclamationmark.triangle") }
        if h.planStatus == "allowed_warning", let w = h.windows.max(by: { $0.utilization < $1.utilization }) {
            return out(
                "Close to its \(window(w.name)) limit, \(Int((w.utilization * 100).rounded()))% used", .warn,
                "gauge.with.dots.needle.67percent")
        }
        if let u = h.upstreamClass, u != "ok" {
            let words = u == "rate_limited" ? "The provider is limiting it" : "The provider reported a problem"
            return out(words, .warn, "exclamationmark.triangle")
        }
        guard let ok = h.lastSuccessAt else { return out("Not used yet", .queue, "moon.zzz") }
        return Line(
            text: "Working", tone: .run, symbol: "checkmark.circle",
            help: "Last went well \(AccountsWords.duration(now.timeIntervalSince(ok))) ago")
    }
}
