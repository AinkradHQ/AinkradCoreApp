// LoreOutline — what the right sidebar reads from the open note's Markdown: headings, words, whether it has a table;
// and what the left sidebar reads from the note list: the tree. Pure functions, so tests need no Core.
import CoreKit
import CoreUI
import Foundation

struct LoreHeading: Equatable, Identifiable {
    var level: Int
    var title: String
    /// Which appearance of this exact title it is (0 = first), so a click lands on the right one.
    var occurrence: Int
    var id: String { "\(level)-\(occurrence)-\(title)" }
}

enum LoreOutline {
    /// `#`, `##` and `###` headings outside fenced code, in order. A heading is at most 120 characters of its line.
    static func headings(_ markdown: String) -> [LoreHeading] {
        var out: [LoreHeading] = []
        var seen: [String: Int] = [:]
        var fenced = false
        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                fenced.toggle()
                continue
            }
            guard !fenced, line.hasPrefix("#") else { continue }
            let hashes = line.prefix(while: { $0 == "#" }).count
            let rest = line.dropFirst(hashes)
            guard (1...3).contains(hashes), rest.first == " " else { continue }
            let title = String(rest.trimmingCharacters(in: .whitespaces).prefix(120))
            guard !title.isEmpty else { continue }
            let n = seen[title, default: 0]
            seen[title] = n + 1
            out.append(LoreHeading(level: hashes, title: title, occurrence: n))
        }
        return out
    }

    static func hasTable(_ markdown: String) -> Bool {
        let lines = markdown.components(separatedBy: "\n")
        return lines.indices.contains { GFMTable.extent(lines, at: $0) != nil }
    }

    static func words(_ markdown: String) -> Int {
        markdown.split(whereSeparator: { $0.isWhitespace }).count
    }
}

/// One folder of the notes tree: Personal, a project, or Journal (the daily notes).
struct LoreGroup: Equatable, Identifiable {
    var id: String
    var name: String
    var notes: [LoreNote]
}

enum LoreTree {
    /// Personal first, then projects by name, then Journal (days, newest first). Empty groups are left out. Notes in
    /// a group keep the order they came in (newest change first).
    static func groups(_ notes: [LoreNote], projects: [String: String]) -> [LoreGroup] {
        let live = notes.filter { !$0.trashed }
        var out: [LoreGroup] = []
        let personal = live.filter { $0.kind == "note" && $0.project == nil }
        if !personal.isEmpty { out.append(LoreGroup(id: "personal", name: "Personal", notes: personal)) }
        for (id, name) in projects.sorted(by: { $0.value.localizedStandardCompare($1.value) == .orderedAscending }) {
            let mine = live.filter { $0.kind == "note" && $0.project == id }
            if !mine.isEmpty { out.append(LoreGroup(id: "project-\(id)", name: name, notes: mine)) }
        }
        let days = live.filter { $0.kind == "daily" }.sorted { ($0.day ?? "") > ($1.day ?? "") }
        if !days.isEmpty { out.append(LoreGroup(id: "journal", name: "Journal", notes: days)) }
        return out
    }
}
