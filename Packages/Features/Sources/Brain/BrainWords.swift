import Foundation

/// Every sentence the Brain says outside a view, so the wording is one thing and a test can read it. None of it can carry
/// content: names, counts and plain verbs only (BM-00 I-8).
public enum BrainWords {
    static func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

    /// The one Paused sentence every surface uses (Overview, bell). `names` are mounted rooms only.
    public static func pausedLine(names: [String]) -> String {
        switch names.count {
        case 0: "Search is stopped for some rooms. Other rooms keep working, each one alone."
        case 1: "Search is stopped for \(names[0]). Other rooms keep working, each one alone."
        default:
            "Search is stopped for \(names.dropLast().joined(separator: ", ")) and \(names.last ?? ""). "
                + "Other rooms keep working, each one alone."
        }
    }

    public static let pausedWhy = "A check found a leak, so search across these rooms is stopped until you clear it."

    /// The Mac bell (Q3): room name and count.
    public static func bell(kind: NeedKind, n: Int, room: String?, pausedRooms: Int = 0) -> String {
        let in_ = room.map { " in \($0)" } ?? ""
        switch kind {
        case .waiting: return "\(plural(n, "memory waits", "memories wait"))\(in_)"
        case .conflict: return "\(plural(n, "conflict", "conflicts")) to settle\(in_)"
        case .blocked: return "\(plural(n, "note was", "notes were")) blocked\(in_)"
        case .check: return "\(plural(n, "check is", "checks are")) due"
        case .unclassified: return "\(plural(n, "capture has", "captures have")) no room yet"
        case .paused: return "Search is paused for \(plural(max(pausedRooms, n), "room", "rooms"))"
        }
    }

    /// iPhone push (Q3): never a name, only "a room" and a count. The full name appears after unlock.
    public static func push(kind: NeedKind, n: Int) -> String {
        bell(kind: kind, n: n, room: kind == .check || kind == .unclassified ? nil : "a room")
    }

    public static func failure(_ error: Error) -> String {
        (error as? BrainFailure)?.sentence ?? "Something went wrong. Nothing was changed."
    }

    public static let unavailableTitle = "Core does not serve the Brain yet"
    public static let unavailableText =
        "Rooms and memory appear here once Core serves them. Nothing on this screen is live."
    public static let sampleLabel = "Sample data. Core does not serve the Brain yet."

    // MARK: plain words. The technical term stays in the hover help.

    /// "19 h" with a no-break space, so a number never leaves its unit on another line.
    static func unit(_ s: String) -> String { s.replacingOccurrences(of: " ", with: "\u{00A0}") }
    static func keyRenews(_ left: String) -> String { "Key renews in \(unit(left))" }
    public static let leaseHelp =
        "Lease: the room's key is lent for a while. Without renewal the saved copy on a device cannot be read."

    /// A plain name and a hover line for a health tile; an unknown id keeps the service's own name.
    static func tile(_ id: String, _ name: String) -> (name: String, help: String) {
        switch id {
        case "isolation":
            (
                "Rooms kept apart",
                "Isolation: no room ever answers with another room's memories. Tested with 1,000 queries."
            )
        case "restore": ("Backup test", "Restore drill: rebuilds a room on a clean Mac from its backup.")
        case "index": ("Search index", "The index that makes search fast. It rebuilds itself when needed.")
        case "keys": ("Key rotation", "Rotation: the room keys are replaced on a schedule.")
        case "providers":
            ("Provider rules", "Which cloud models may see which room. Each approval has a review date.")
        default: (name, name)
        }
    }

    static let facts: [(key: String, title: String, help: String)] = [
        ("stale", "Memories past their review date", "Each memory has a date to be looked at again."),
        ("recall", "Search depth", "Recall mode: how much of a room a search reads. Full reads everything it may."),
        (
            "secrets", "Notes stopped for a secret",
            "Blocked for holding a secret: a note with a key or a password is stopped, not saved."
        ),
        (
            "flagged", "Sources that look like instructions",
            "Flagged as instruction-like: text that tries to give orders to an agent. It is shown as written, never run."
        ),
    ]

    /// A number and its unit never split across lines: "212 ms", "8 min", "19 h", "41 days".
    static func glue(_ s: String) -> String {
        s.replacing(/(\d) (ms|s|h|min|days?|KB|MB|%)\b/) { "\($0.1)\u{00A0}\($0.2)" }
    }

    private static func typeWord(_ t: String, _ n: Int) -> String {
        guard n != 1 else { return t }
        return t.hasSuffix("y") ? String(t.dropLast()) + "ies" : t + "s"
    }
    /// "820 facts, 410 rules, 90 tasks": every type of a room, biggest first.
    static func breakdown(_ shares: [TypeShare]) -> String {
        shares.filter { $0.count > 0 }.sorted { $0.count > $1.count }
            .map { "\($0.count.formatted()) \(typeWord($0.type, $0.count))" }.joined(separator: ", ")
    }
    /// The inline label of a room's bar: its biggest type and that type's share.
    static func mostly(_ shares: [TypeShare]) -> String {
        let total = shares.reduce(0) { $0 + $1.count }
        guard total > 0, let top = shares.max(by: { $0.count < $1.count }) else { return "" }
        return "\(Int((Double(top.count) / Double(total) * 100).rounded()))% \(typeWord(top.type, 2))"
    }
}
