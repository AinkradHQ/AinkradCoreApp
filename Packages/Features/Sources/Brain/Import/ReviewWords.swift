import Foundation

/// The words of the Rooms review, in one place so a test can read them.
public enum ReviewWords {
    public static let held = "Held until the room backup exists."
    public static let mixed = "Two employers"
    public static let kinds: [(id: String, title: String)] = [
        ("personal", "Personal"), ("product", "Product"), ("employer", "Employer"), ("client", "Client"),
        ("general", "General"), ("global-safe", "Safe to share"),
    ]

    public static func kind(_ id: String) -> String { kinds.first { $0.id == id }?.title ?? id.capitalized }

    /// "2026-03-04 to 2026-11-02", or one date, or nothing.
    public static func range(_ first: String?, _ last: String?) -> String {
        let a = first.map { String($0.prefix(10)) }
        let b = last.map { String($0.prefix(10)) }
        switch (a, b) {
        case (let a?, let b?): return a == b ? a : "\(a) to \(b)"
        case (let a?, nil): return a
        case (nil, let b?): return b
        default: return ""
        }
    }

    public static func warning(_ code: String) -> String { code == "mixed_employers" ? mixed : code }

    /// What a card says about its state, or nil for a plain proposed one.
    public static func state(_ card: ProposalCard) -> String? {
        switch card.state {
        case "accepted": "Accepted"
        case "held": "Accepted, held"
        case "refused": "Refused"
        case "committed": "Imported"
        default: nil
        }
    }
}
