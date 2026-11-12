import Foundation

/// What the Rooms and Sources pages say about a sync, in one place so a test can read it.
public enum SyncBanner: Equatable, Sendable {
    case none
    case syncing(source: String?, at: Int, total: Int)
    case synced(new: Int, went: Int, rooms: Int, review: Int)
    case nothingNew(sources: Int, nextMinutes: Int)
    case waiting(Int)
    case message(String)
}

public enum SyncWords {
    public static let coreSource = "AI sessions on this Core"
    /// Docs and notes; every other source is an AI session history.
    static let noteKinds: Set<String> = ["doc", "vault", "agents_md", "chat"]
    public static let sessionsGroup = "AI sessions"
    public static let notesGroup = "Notes and docs"
    public static let neverRead = "Passwords, keys and contracts are never read."

    public static func group(_ kind: String) -> String { noteKinds.contains(kind) ? notesGroup : sessionsGroup }

    /// "Claude Code" for the source the wizard calls "Claude Code sessions"; the Core's own collector by its name.
    public static func title(_ kind: String, _ sources: [any ImportSource]) -> String {
        if kind == "core_transcript" { return coreSource }
        guard let t = sources.first(where: { $0.id == kind })?.title else { return kind }
        return t.hasSuffix(" sessions") ? String(t.dropLast(" sessions".count)) : t
    }

    public static func date(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso)
    }

    /// "Just now", "4 min ago", "2 hours ago", "Yesterday", or the day.
    public static func ago(_ d: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(d))
        switch s {
        case ..<60: return "Just now"
        case ..<3600: return "\(Int(s / 60)) min ago"
        case ..<86_400: return BrainWords.plural(Int(s / 3600), "hour", "hours") + " ago"
        case ..<172_800: return "Yesterday"
        default: return d.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    public static func banner(_ b: SyncBanner) -> (title: String, text: String) {
        switch b {
        case .none: return ("", "")
        case .syncing(_, _, let total): return ("Syncing \(BrainWords.plural(total, "source", "sources"))", "")
        case .synced(let new, let went, let rooms, let review):
            var t = "\(went) went to \(BrainWords.plural(rooms, "room", "rooms"))"
            if review > 0 { t += ", \(review) need review" }
            return (BrainWords.plural(new, "new item", "new items"), t + ".")
        case .nothingNew(let n, let mins):
            return (
                "Nothing new",
                "All \(BrainWords.plural(n, "source", "sources")) checked just now. Next sync in \(mins) minutes."
            )
        case .waiting(let n):
            return (
                "\(BrainWords.plural(n, "import", "imports")) waiting for review", "Nothing is filed until you look."
            )
        case .message(let s): return (s, "")
        }
    }
}
