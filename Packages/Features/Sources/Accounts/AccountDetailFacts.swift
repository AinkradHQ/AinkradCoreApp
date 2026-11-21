import CoreUI
import Foundation

/// The account page's one state (approved mockup `Designs/core/0-10/review/account-details`, 2026-11-21).
enum DetailState: Equatable, Sendable {
    case ready, full, signedOut, off, problem
}

/// What the verdict at the top of the page says, and the header's state word.
struct DetailWords: Equatable {
    let title: String
    let line: String
    let tone: Tone
    let symbol: String
    let chip: String
}

/// Where the page's plan window meter stands: how much is used and how much of the window's time is gone.
struct WindowFacts: Equatable {
    let name: String
    let used: Double
    let gone: Double?
    let resetsAt: Date?
}

/// Pure words and numbers of the account page; the view only draws them.
enum DetailFacts {
    static let fiveHours: TimeInterval = 18_000
    static let week: TimeInterval = 604_800

    static func ordinal(_ n: Int) -> String {
        let ends =
            switch (n % 100, n % 10) {
            case (11...13, _): "th"
            case (_, 1): "st"
            case (_, 2): "nd"
            case (_, 3): "rd"
            default: "th"
            }
        return "\(n)\(ends)"
    }

    /// 0...1 of the window's time gone, from when it resets and its length; nil without a reset time.
    static func gone(resetsAt: Date?, length: TimeInterval, now: Date) -> Double? {
        guard let resetsAt else { return nil }
        return min(1, max(0, 1 - resetsAt.timeIntervalSince(now) / length))
    }

    /// The 5-hour window's pace line: full ahead of its reset, well inside, or on pace.
    static func pace(used: Double, gone: Double?, resetsAt: Date?, length: TimeInterval, now: Date, short: Bool)
        -> String
    {
        guard used < 1, let gone, gone > 0, let resetsAt else { return used >= 1 ? "" : "On pace" }
        if used > gone * 1.05 {
            if !short { return "Ahead of the clock" }
            let elapsed = gone * length
            let full = now.addingTimeInterval((1 - used) / (used / elapsed))
            return full < resetsAt ? "Faster than the clock: full around \(clock(full))" : "On pace"
        }
        return short && used < gone * 0.5 ? "Well inside" : "On pace"
    }

    /// "18:40, in 2 h 14 min" within a day, "Thursday 09:00" further out.
    static func reset(_ d: Date, now: Date) -> String {
        let left = d.timeIntervalSince(now)
        if left < 86_400 { return left > 60 ? "\(clock(d)), in \(AccountsWords.duration(left))" : clock(d) }
        return d.formatted(.dateTime.weekday(.wide).hour(.twoDigits(amPM: .omitted)).minute())
    }

    /// "$80", "$52.80": whole dollars without cents.
    static func dollars(_ micros: Int64) -> String {
        let d = Double(micros) / 1_000_000
        return d.formatted(.currency(code: "USD").precision(.fractionLength(d == d.rounded() ? 0 : 2)))
    }

    /// "4.1M", "182k", "640": token counts as the page shows them.
    static func compact(_ n: Int64) -> String {
        if n >= 1_000_000 { return (Double(n) / 1e6).formatted(.number.precision(.fractionLength(1))) + "M" }
        if n >= 1_000 { return "\((Double(n) / 1e3).rounded().formatted(.number.grouping(.never)))k" }
        return "\(n)"
    }

    static func clock(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    /// 0...1 of this calendar month gone, and its last day.
    static func month(_ now: Date, calendar: Calendar = .current) -> (gone: Double, last: Date) {
        let start = calendar.dateInterval(of: .month, for: now)!
        return (now.timeIntervalSince(start.start) / start.duration, start.end.addingTimeInterval(-1))
    }

    /// The month's spend carried on at today's rate, in millionths of a dollar.
    static func projected(spend: Int64, gone: Double) -> Int64 {
        gone > 0.02 ? Int64(Double(spend) / gone) : spend
    }

    /// Who is used before an account that waits: "both plans", "Studio plan", "the 3 accounts above it".
    static func above(_ names: [(name: String, plan: Bool)]) -> String {
        if names.count == 1 { return "\(names[0].name) is" }
        if names.count == 2, names.allSatisfy(\.plan) { return "both plans are" }
        return "the \(names.count) accounts above it are"
    }
}

extension AccountsModel {
    /// The rows of the AI order (or, on an older Core, the accounts in their list order) with their chips.
    /// The order's chips say what the page says: a signed-out plan, a full one and a turned-off one are passed over.
    var laneRows: [OrderRow] {
        var seen = false
        return (aiOrderOn ? orderRows : orderRows(accountsInOrder.map(\.id))).map { r in
            var chip = r.chip
            switch detailState(r.account) {
            case .signedOut: chip = .needsLook("Signed out")
            case .full: chip = .limitHit
            case .off: chip = .off
            default: break
            }
            if OrderChips.usable(chip) {
                chip = seen ? .ready : .inUse
                seen = true
            }
            return OrderRow(
                account: r.account, number: r.number, title: r.title, kind: r.kind, chip: chip, sentence: r.sentence,
                meter: r.meter, model: r.model)
        }
    }

    func detailState(_ a: AccountItem) -> DetailState {
        if a.phase == .disabled { return .off }
        let check = planChecks[a.id]?.check.result
        if a.isPlan, (a.health?.authStreak ?? 0) > 0 || a.lastTest?.result == "auth_failed" || check == "token_expired"
        {
            return .signedOut
        }
        let v = verdict(a)
        if a.meter?.limitHit == true || [.limited, .cooling].contains(a.phase)
            || (a.health?.windows.contains { $0.utilization >= 1 } ?? false)
            || [.limitReached, .budgetStopped].contains(v.kind)
        {
            return .full
        }
        return v.isReady || [.budgetNear, .limitNear, .budgetOver].contains(v.kind) ? .ready : .problem
    }

    /// When a full account takes work again.
    func fullUntil(_ a: AccountItem) -> Date? {
        a.meter?.stateUntil ?? a.stateUntil
            ?? a.health?.windows.filter { $0.utilization >= 1 }.compactMap(\.resetsAt).min()
    }

    /// "Claude plan", "Anthropic API key".
    func kindName(_ a: AccountItem) -> String {
        let p = providerName(a.provider)
        if a.provider.hasSuffix("-sub") {
            return p.replacingOccurrences(of: " subscription", with: "") + " plan"
        }
        return p.hasSuffix(" key") ? p : "\(p) key"
    }

    func detailWords(_ a: AccountItem) -> DetailWords {
        let rows = laneRows
        let i = rows.firstIndex { $0.account.id == a.id } ?? 0
        let me = rows.indices.contains(i) ? rows[i] : nil
        let worker = rows.first { $0.chip == .inUse && $0.account.id != a.id }.map(\.title)
        let after = rows.dropFirst(i + 1).first { OrderChips.usable($0.chip) }.map(\.title)
        let ord = DetailFacts.ordinal(i + 1)
        let pays: String = {
            guard !a.isPlan else {
                return after.map { " When its plan is full, \($0) takes the work." } ?? ""
            }
            let brand = providerName(a.provider).replacingOccurrences(of: " API", with: "")
            let budget = a.monthLimitUSDMicros.map { ", inside a \(DetailFacts.dollars($0)) monthly budget" } ?? ""
            return " It pays per use from your \(brand) key\(budget)."
        }()
        let v = verdict(a)
        switch detailState(a) {
        case .off:
            return DetailWords(
                title: "Turned off",
                line: "AI sessions skip it until you turn it on. It keeps its place in the AI order.",
                tone: .queue, symbol: "power", chip: "Turned off")
        case .signedOut:
            let since = a.lastTest.map { "Since \(DetailFacts.clock($0.at)). " } ?? ""
            let has = worker.map { " and \($0) has its work" } ?? ""
            return DetailWords(
                title: "Claude signed this plan out",
                line: "\(since)AI sessions skip it\(has). Sign in again and it takes its place back.", tone: .fail,
                symbol: "lock", chip: "Signed out")
        case .full:
            let until = fullUntil(a)
            let at = until.map { " until \(DetailFacts.clock($0))" } ?? ""
            let window = a.health?.windows.first { $0.utilization >= 1 }?.name
            let title =
                window == "five_hour"
                ? "The 5-hour window is full"
                : window == "seven_day" ? "The weekly window is full" : "It reached its limit"
            let line =
                worker.map { "\($0) takes new work\(at). Sessions here move over by themselves; nothing is lost." }
                ?? "New work waits\(at). Nothing is lost."
            return DetailWords(title: title, line: line, tone: .warn, symbol: "clock", chip: "Full\(at)")
        case .ready:
            let title: String
            if me?.chip == .inUse {
                title = i == 0 ? "AI sessions use it first" : "AI sessions use it now"
            } else {
                let names = rows.prefix(i).map { ($0.title, $0.account.isPlan) }
                title = names.isEmpty ? "AI sessions can use it" : "Used when \(DetailFacts.above(names)) full"
            }
            return DetailWords(
                title: title, line: "\(i == 0 ? "First" : ord) in the AI order.\(pays)", tone: .run,
                symbol: "checkmark",
                chip: "Ready")
        case .problem:
            return DetailWords(
                title: v.label, line: v.line(a, limits: limits(of: a), budgets: budgets, now: now()), tone: v.tone,
                symbol: "exclamationmark.triangle", chip: v.label)
        }
    }

    /// The plan windows the harness last reported: the 5-hour and the weekly one.
    func windowFacts(_ a: AccountItem) -> [WindowFacts] {
        let w = a.health?.windows ?? []
        return [("five_hour", DetailFacts.fiveHours), ("seven_day", DetailFacts.week)].compactMap { name, length in
            w.first { $0.name == name }.map {
                WindowFacts(
                    name: name, used: $0.utilization,
                    gone: DetailFacts.gone(resetsAt: $0.resetsAt, length: length, now: now()),
                    resetsAt: $0.resetsAt)
            }
        }
    }
}
