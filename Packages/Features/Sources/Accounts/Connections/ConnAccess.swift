import Foundation

/// The words on a connection's row: what AI may do, and how much it reaches. Pure, so each sentence is a test.
enum ConnAccess {
    /// "Read only", "Can post messages", "Can make changes", or "Not allowed yet" for a connection with no grant.
    static func lead(_ kind: ConnKind?, allowed: Set<String>) -> String {
        let caps = kind?.capabilities ?? []
        let on = caps.filter { allowed.contains($0.id) }
        if on.isEmpty { return "Not allowed yet" }
        let writes = on.filter(\.writes)
        if writes.isEmpty { return "Read only" }
        return writes.allSatisfy { $0.id == "post_messages" } ? "Can post messages" : "Can make changes"
    }

    /// "3 repositories", "1 project", "All channels", "No teams". `only` nil is every one of them.
    static func scope(_ kind: ConnKind?, only: [String]?) -> String {
        let word = kind?.resource ?? "places"
        guard let only else { return "All \(word)" }
        return only.isEmpty ? "No \(word)" : "\(only.count) \(noun(word, count: only.count))"
    }

    /// "repositories" for 3, "repository" for 1.
    static func noun(_ plural: String, count: Int) -> String {
        guard count == 1 else { return plural }
        if plural.hasSuffix("ies") { return String(plural.dropLast(3)) + "y" }
        return plural.hasSuffix("s") ? String(plural.dropLast()) : plural
    }

    /// The second line of a pick row for something that changed `then`: "Updated today", "3 days ago", "Last month".
    static func updated(_ then: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: then), to: calendar.startOfDay(for: now))
            .day ?? 0
        switch days {
        case ..<1: return "Updated today"
        case 1: return "Updated yesterday"
        case 2..<7: return "\(days) days ago"
        case 7..<14: return "Last week"
        case 14..<60: return "Last month"
        default: return "\(days / 30) months ago"
        }
    }

    /// The line under a pick's name: when it changed, else what the Core said about it.
    static func line(_ p: ConnPick, now: Date = Date()) -> String? {
        p.updatedAt.map { updated($0, now: now) } ?? p.detail
    }

    /// "Just now", "12 min ago", "3 h ago", "Yesterday", "4 days ago": when a connection was last used.
    static func used(_ then: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let secs = max(0, Int(now.timeIntervalSince(then)))
        if secs < 60 { return "Just now" }
        if secs < 3600 { return "\(secs / 60) min ago" }
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: then), to: calendar.startOfDay(for: now))
            .day ?? 0
        if days < 1 { return "\(secs / 3600) h ago" }
        if days == 1 { return "Yesterday" }
        if days < 60 { return "\(days) days ago" }
        return "\(days / 30) months ago"
    }
}
