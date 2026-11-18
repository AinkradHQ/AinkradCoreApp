import CoreKit
import CoreUI
import Foundation

/// Every sentence the import dialogs say, in one place so the names stay the same everywhere (Import, Review, Undo Import).
enum LoreImportWords {
    static func notes(_ n: Int) -> String { n == 1 ? "1 note" : "\(n) notes" }

    static func place(_ project: String?, _ names: [String: String]) -> String {
        guard let project, !project.isEmpty else { return "Personal" }
        return names[project] ?? "this project"
    }

    /// "Import 42 notes into Garden Club Website": the one line the review is about.
    static func summary(_ run: LoreImportRun, into place: String) -> String {
        "Import \(notes(run.include)) into \(place)"
    }

    /// What the review will do, by kind: new, updated, kept as they are, unchanged.
    static func plan(_ run: LoreImportRun) -> String {
        var parts: [String] = []
        let changed = run.flags["changed"] ?? 0
        let conflict = run.flags["conflict"] ?? 0
        let same = run.flags["duplicate"] ?? 0
        if run.fresh > 0 { parts.append("\(run.fresh) new") }
        if changed > 0 { parts.append("\(changed) updated") }
        if conflict > 0 { parts.append("\(conflict) kept as you edited them") }
        if same > 0 { parts.append("\(same) unchanged") }
        let big = (run.flags["tooLarge"] ?? 0) + (run.flags["skipped"] ?? 0)
        if big > 0 { parts.append("\(big) left out") }
        return parts.joined(separator: " · ")
    }

    /// Entries the Core did not take: unsafe ones and unwanted ones, counted only.
    static func notTaken(refused: Int, ignored: Int, onThisMac: Int = 0) -> String? {
        var parts: [String] = []
        if refused > 0 { parts.append(refused == 1 ? "1 refused as unsafe" : "\(refused) refused as unsafe") }
        if ignored > 0 {
            parts.append(
                ignored == 1
                    ? "1 file not Markdown or in a skipped folder"
                    : "\(ignored) files not Markdown or in a skipped folder")
        }
        if onThisMac > 0 {
            parts.append(onThisMac == 1 ? "1 left out on this Mac" : "\(onThisMac) left out on this Mac")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func item(_ i: LoreImportItem) -> String {
        switch i.flag {
        case "changed": "Changed in the source: updates its note"
        case "conflict": "Edited here too: kept as it is, the new text is saved as a version"
        case "duplicate": "Same as its note: nothing to do"
        case "too_large": "Over 1 MB: left out"
        case "skipped": "Left out"
        default: "New note"
        }
    }

    /// After a commit: what it did.
    static func result(_ run: LoreImportRun) -> String {
        let r = run.results
        var parts: [String] = []
        if let n = r["created"], n > 0 { parts.append("\(n) added") }
        if let n = r["updated"], n > 0 { parts.append("\(n) updated") }
        if let n = r["conflict"], n > 0 { parts.append("\(n) kept as you edited them") }
        if let n = r["unchanged"], n > 0 { parts.append("\(n) unchanged") }
        return parts.isEmpty ? "Nothing was added." : parts.joined(separator: " · ")
    }

    static func undone(_ run: LoreImportRun) -> String {
        run.kept == 0
            ? "\(notes(run.undone)) put back as they were."
            : "\(notes(run.undone)) put back. \(notes(run.kept)) you changed after the import \(run.kept == 1 ? "was" : "were") left as \(run.kept == 1 ? "it is" : "they are")."
    }

    /// The state of a run in the history: a word and a tone, never colour alone.
    static func state(_ s: String) -> (label: String, tone: Tone, symbol: String) {
        switch s {
        case "staging": ("Reading", .run, "arrow.down.circle")
        case "review": ("To review", .queue, "list.bullet.clipboard")
        case "committing": ("Importing", .run, "arrow.down.circle")
        case "committed": ("Imported", .done, "checkmark.circle")
        case "undoing": ("Undoing", .run, "arrow.uturn.backward.circle")
        case "undone": ("Undone", .queue, "arrow.uturn.backward.circle")
        case "abandoned": ("Discarded", .queue, "xmark.circle")
        default: (s, .queue, "circle")
        }
    }

    /// What a click on a run in the history does, or nil when there is nothing left to do with it.
    static func resumeHelp(_ s: String) -> String? {
        switch s {
        case "staging": "Finish reading this import and review it"
        case "review": "Review this import"
        case "committing": "Continue importing"
        case "committed": "See this import, or undo it"
        case "undoing": "Continue undoing"
        default: nil
        }
    }

    static func age(_ iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
        return d.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}
