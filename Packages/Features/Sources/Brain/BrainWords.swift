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
}
