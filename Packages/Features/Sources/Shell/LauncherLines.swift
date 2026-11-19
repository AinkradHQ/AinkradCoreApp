import SwiftUI

/// The launcher's groups. Sessions and terminals come in numbers, so the empty state keeps every group collapsed under its header.
enum LauncherSection: Int, CaseIterable, Sendable {
    case apps, sessions, terminals, projects, actions

    var title: String {
        switch self {
        case .apps: "Apps"
        case .sessions: "Sessions"
        case .terminals: "Terminals"
        case .projects: "Projects"
        case .actions: "Actions"
        }
    }

    var symbol: String {
        switch self {
        case .apps: "square.grid.2x2"
        case .sessions: "sparkles"
        case .terminals: "terminal"
        case .projects: "folder"
        case .actions: "bolt"
        }
    }

    static func of(_ e: LauncherEntry) -> LauncherSection {
        if e.id.hasPrefix("agents.s-") { return .sessions }
        if e.id.hasPrefix("terminal-") { return .terminals }
        if e.id.hasPrefix("project-") { return .projects }
        return e.isAction ? .actions : .apps
    }
}

/// One of the few suggestions the empty launcher opens with, and why.
struct LauncherPick: Identifiable {
    let entry: LauncherEntry
    let reason: String
    var id: String { entry.id }
}

/// One selectable line. The launcher keeps a single flat list of these, so the arrows, ⇥ and ⌘1–9 work the same everywhere.
enum LauncherLine: Identifiable {
    case pick(LauncherPick)
    case group(LauncherSection, count: Int, open: Bool)
    /// `heading` is the title to draw above it when it differs from the line before.
    case item(LauncherRow, heading: String?, nested: Bool)

    var id: String {
        switch self {
        case .pick(let p): "pick-\(p.id)"
        case .group(let s, _, _): "group-\(s.rawValue)"
        case .item(let r, _, let nested): (nested ? "in-" : "") + r.id
        }
    }

    var heading: String? {
        if case .item(_, let h, _) = self { return h }
        return nil
    }

    var entry: LauncherEntry? {
        switch self {
        case .pick(let p): p.entry
        case .item(let r, _, _): r.entry
        case .group: nil
        }
    }

    var isGroup: Bool {
        if case .group = self { return true }
        return false
    }
}

enum LauncherLines {
    static let maxResults = 40

    /// Empty query: the suggestions, then a collapsed header per group, with the open group's entries under it.
    @MainActor static func browse(entries: [LauncherEntry], picks: [LauncherPick], open: LauncherSection?) -> [LauncherLine] {
        var out = picks.map { LauncherLine.pick($0) }
        let by = Dictionary(grouping: entries, by: LauncherSection.of)
        for s in LauncherSection.allCases {
            guard let list = by[s], !list.isEmpty else { continue }
            out.append(.group(s, count: list.count, open: open == s))
            if open == s {
                out += list.map { .item(LauncherRow(entry: $0, group: .goTo, matched: []), heading: nil, nested: true) }
            }
        }
        return out
    }

    /// A query: hits grouped by section, the section with the best hit first.
    @MainActor static func results(_ rows: [LauncherRow]) -> [LauncherLine] {
        let by = Dictionary(grouping: rows.prefix(maxResults), by: { LauncherSection.of($0.entry) })
        let best = by.mapValues { $0.map(\.score).max() ?? 0 }
        return by.keys.sorted { (best[$0] ?? 0, -$0.rawValue) > (best[$1] ?? 0, -$1.rawValue) }.flatMap { s in
            (by[s] ?? []).sorted { $0.score > $1.score }.map { LauncherLine.item($0, heading: s.title, nested: false) }
        }
    }

    /// ⇧⌘A: the pane's actions in the old groups.
    @MainActor static func actions(_ rows: [LauncherRow]) -> [LauncherLine] {
        rows.map { .item($0, heading: $0.group.title, nested: false) }
    }

    /// ⇥ / ⇧⇥: the first line of the next (or previous) group, round the ring. Nil when there is only one group.
    static func nextGroup(_ lines: [LauncherLine], from i: Int, step: Int) -> Int? {
        let starts = lines.indices.filter { j in
            j == 0 || lines[j].isGroup || (lines[j].heading != nil && lines[j - 1].heading != lines[j].heading)
        }
        guard starts.count > 1 else { return nil }
        let here = starts.lastIndex { $0 <= i } ?? 0
        return starts[(here + step + starts.count) % starts.count]
    }
}
