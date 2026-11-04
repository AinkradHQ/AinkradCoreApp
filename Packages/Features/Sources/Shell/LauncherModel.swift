import Observation
import SwiftUI

/// One launcher entry. Modules register theirs once: `shell.launcher.register(...)`, mirroring `Mac.launcher.add`.
public struct LauncherEntry: Identifiable {
    public enum Group: Int, Sendable, CaseIterable {
        case recent, topHit, actions, goTo
        var title: String {
            switch self {
            case .recent: "Recent"
            case .topHit: "Top hit"
            case .actions: "Actions"
            case .goTo: "Go to"
            }
        }
    }
    public let id: String
    public let title: String
    public let sub: String?
    public let symbol: String
    public let keywords: [String]
    public let isAction: Bool
    /// The tile behind the glyph: blue for apps and actions, slate for the Mac's own places (Settings, shortcuts).
    public let tile: Tile
    public let run: @MainActor () -> Void

    public enum Tile: Sendable { case blue, slate }

    public init(
        id: String, title: String, sub: String? = nil, symbol: String = "square", keywords: [String] = [],
        isAction: Bool = false, tile: Tile = .blue, run: @escaping @MainActor () -> Void
    ) {
        self.tile = tile
        self.id = id
        self.title = title
        self.sub = sub
        self.symbol = symbol
        self.keywords = keywords
        self.isAction = isAction
        self.run = run
    }
}

@MainActor @Observable
public final class LauncherRegistry {
    public private(set) var entries: [LauncherEntry] = []
    public var recents: [String] = []
    public init() {}

    public func register(_ entry: LauncherEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
    }

    public func unregister(_ id: String) { entries.removeAll { $0.id == id } }
    public func entry(_ id: String) -> LauncherEntry? { entries.first { $0.id == id } }

    func remember(_ id: String) { recents = Array(([id] + recents.filter { $0 != id }).prefix(3)) }
}

struct LauncherRow: Identifiable {
    let entry: LauncherEntry
    let group: LauncherEntry.Group
    let matched: [Int]
    var id: String { entry.id }
}

/// Fuzzy ranking from the prototype (`shell-glance.js`): word starts beat prefixes beat substrings beat scattered letters.
/// "trm" finds Terminals, "ns" finds New session, "cit bo" finds Citadel Board.
enum Fuzzy {
    static func score(_ text: String, _ query: String) -> (score: Double, at: [Int])? {
        let t = Array(text.lowercased())
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return (0, []) }
        func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        let starts = t.indices.filter { k in isWordChar(t[k]) && (k == 0 || !isWordChar(t[k - 1])) }
        if q.count > 1 && q.count <= starts.count {
            for o in 0...(starts.count - q.count) where q.indices.allSatisfy({ t[starts[o + $0]] == q[$0] }) {
                return (75 - Double(o) * 2, (0..<q.count).map { starts[o + $0] })
            }
            var pick: [Int] = []
            var si = 0
            for ch in q {
                while si < starts.count && t[starts[si]] != ch { si += 1 }
                if si == starts.count { break }
                pick.append(starts[si])
                si += 1
            }
            if pick.count == q.count { return (65 - ((pick[0] > 0) ? 4 : 0), pick) }
        }
        if let sub = find(q, in: t) {
            let base: Double = sub == 0 ? 70 : (isWordChar(t[sub - 1]) ? 25 : 60)
            return (base - Double(sub) * 0.2, Array(sub..<(sub + q.count)))
        }
        var pos = 0
        var s: Double = 0
        var at: [Int] = []
        for ch in q {
            var f = -1
            var k = pos
            while k < t.count {
                if t[k] == ch && (k == 0 || !isWordChar(t[k - 1])) {
                    f = k
                    break
                }
                k += 1
            }
            if f == -1 { f = t[pos...].firstIndex(of: ch) ?? -1 }
            if f == -1 { return nil }
            s += (f == 0 || !isWordChar(t[f - 1])) ? 8 : (f == pos ? 4 : 1)
            at.append(f)
            pos = f + 1
        }
        return (s, at)
    }

    private static func find(_ q: [Character], in t: [Character]) -> Int? {
        guard q.count <= t.count else { return nil }
        return (0...(t.count - q.count)).first { Array(t[$0..<($0 + q.count)]) == q }
    }

    /// Empty query: recents first, then actions, then places. Otherwise the best hit leads, the rest by group then score.
    @MainActor static func rank(_ entries: [LauncherEntry], query: String, recents: [String]) -> [LauncherRow] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        func group(_ e: LauncherEntry) -> LauncherEntry.Group { e.isAction ? .actions : .goTo }
        if words.isEmpty {
            let rec = recents.compactMap { id in entries.first { $0.id == id } }
            let rest = entries.filter { e in !rec.contains { $0.id == e.id } }
                .sorted { group($0).rawValue < group($1).rawValue }
            return rec.map { LauncherRow(entry: $0, group: .recent, matched: []) }
                + rest.map { LauncherRow(entry: $0, group: group($0), matched: []) }
        }
        var hits: [(row: LauncherRow, score: Double)] = []
        for e in entries {
            var total = 0.0
            var at: [Int] = []
            var ok = true
            for w in words {
                if let m = score(e.title, w) {
                    total += m.score
                    at += m.at
                } else if let m = score("\(e.sub ?? "") \(e.keywords.joined(separator: " "))", w) {
                    total += m.score * 0.5
                } else {
                    ok = false
                    break
                }
            }
            if ok {
                hits.append(
                    (LauncherRow(entry: e, group: group(e), matched: at), total + (recents.contains(e.id) ? 6 : 0)))
            }
        }
        hits.sort { $0.score > $1.score }
        guard let top = hits.first else { return [] }
        let tail = hits.dropFirst().sorted {
            $0.row.group.rawValue != $1.row.group.rawValue
                ? $0.row.group.rawValue < $1.row.group.rawValue : $0.score > $1.score
        }
        return [LauncherRow(entry: top.row.entry, group: .topHit, matched: top.row.matched)] + tail.map(\.row)
    }
}
