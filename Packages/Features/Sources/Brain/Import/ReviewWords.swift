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

    /// "0.93": the closeness of an item to a room.
    public static func score(_ v: Double) -> String { String(format: "%.2f", v) }

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

    /// "Project · 1,412 items", with the date range when there is one.
    public static func line(_ card: ProposalCard) -> String {
        if card.isUnsorted {
            return "No room yet · \(BrainWords.plural(card.itemCount, "item", "items")) that fit no project"
        }
        var s = "\(kind(card.kind)) · \(BrainWords.plural(card.itemCount, "item", "items"))"
        let r = range(card.first, card.last)
        if !r.isEmpty { s += " · \(r)" }
        return s
    }

    /// "3 accepted · 1 refused · 1 held": only the counts that are not zero.
    public static func tally(_ cards: [ProposalCard]) -> String {
        let live = cards.filter { $0.state != "merged" && !$0.isUnsorted }
        let parts: [(Int, String)] = [
            (live.filter { $0.state == "accepted" }.count, "accepted"),
            (live.filter { $0.state == "refused" }.count, "refused"),
            (live.filter(\.isHeld).count, "held"),
        ]
        return parts.filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
    }

    /// "Looks like Optimus. Merge?"
    public static func suggestion(_ s: MergeSuggestion) -> String { "Looks like \(s.name). Merge?" }

    /// "Local AI: 1,240 of 2,980 items", or a plain line on a Core that does not count.
    public static func reading(_ p: SemanticProgress?) -> String {
        guard let p else { return "Local AI: reading the items…" }
        return "Local AI: \(p.done.formatted()) of \(p.total.formatted()) \(p.total == 1 ? "item" : "items")"
    }

    /// "Local AI tidied this: merged 52 duplicates, folded 14 rooms (35 → 21 rooms)". Rooms merged and rooms folded
    /// count together: both are a room that went into another.
    public static func tidied(_ t: TidySummary) -> String {
        let dupes = t.duplicatesMerged ?? 0
        let rooms = (t.roomsMerged ?? 0) + (t.roomsFolded ?? 0)
        let moved = t.itemsMoved ?? 0
        let parts = [
            dupes > 0 ? "merged \(BrainWords.plural(dupes, "duplicate", "duplicates"))" : nil,
            rooms > 0 ? "folded \(BrainWords.plural(rooms, "room", "rooms"))" : nil,
            moved > 0 ? "moved \(BrainWords.plural(moved, "item", "items")) into rooms" : nil,
        ].compactMap { $0 }
        var s = "Local AI tidied this: " + (parts.isEmpty ? "small changes" : parts.joined(separator: ", "))
        if let b = t.roomsBefore, let a = t.roomsAfter { s += " (\(b) → \(BrainWords.plural(a, "room", "rooms")))" }
        return s
    }

    /// The changes by kind, in a fixed order, with the group's title and symbol.
    public static func tidyGroups(_ all: [TidyChange]) -> [(title: String, symbol: String, changes: [TidyChange])] {
        [
            ("Duplicates merged", "doc.on.doc", "duplicate"), ("Rooms joined", "arrow.triangle.merge", "merge"),
            ("Small rooms folded", "arrow.turn.down.right", "fold"),
            ("Items moved into rooms", "tray.and.arrow.down", "move"),
        ].compactMap { title, symbol, kind in
            let c = all.filter { $0.kind == kind }
            return c.isEmpty ? nil : (title, symbol, c)
        }
    }

    /// The name of one change: the kept copy or the moved item by its title, else the room.
    public static func changeTitle(_ c: TidyChange, titles: [String: String]) -> String {
        switch c.kind {
        case "duplicate", "move":
            let id = c.kind == "duplicate" ? c.to : c.itemIds.first ?? ""
            return c.sentTitle ?? titles[id].flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled item"
        default: return c.fromName ?? c.from ?? "A room"
        }
    }

    /// The quiet line under one change: "3 copies merged into this one", "Folded into Acme Shop".
    public static func change(_ c: TidyChange) -> String {
        let to = c.toName ?? c.to
        switch c.kind {
        case "duplicate":
            return "\(BrainWords.plural(c.itemIds.count, "copy", "copies")) merged into this one"
        case "merge": return "Joined \(to)"
        case "fold": return c.to == ProposalCard.unsortedID ? "Its items wait in No room yet" : "Folded into \(to)"
        default: return "Moved into \(to)"
        }
    }

    public static func importTitle(_ n: Int) -> String {
        n == 0 ? "Import" : "Import \(BrainWords.plural(n, "room", "rooms"))"
    }
}
