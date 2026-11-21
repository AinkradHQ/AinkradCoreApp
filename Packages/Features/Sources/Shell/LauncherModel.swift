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

    public enum Tile: Sendable { case blue, slate, danger, view }

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
    public private(set) var fallbacks: [LauncherFallback] = []
    public func registerFallback(_ f: LauncherFallback) {
        fallbacks.removeAll { $0.id == f.id }
        fallbacks.append(f)
    }
    /// The few suggestions the empty launcher opens with, ranked by use. Computed when the launcher opens and when something is
    /// opened from it, never while drawing.
    private(set) var picks: [LauncherPick] = []
    /// What usage adds to a search hit's score, by entry id (same moments as `picks`).
    private(set) var bonus: [String: Double] = [:]
    /// Bumps when entries come or go, so an open launcher knows to rebuild its list.
    private(set) var version = 0
    private(set) var usage = LauncherUsage()
    @ObservationIgnored private var defaults: UserDefaults?
    static let usageKey = "ainkrad.core.launcher.usage"
    static let pickCount = 6
    public init() {}

    /// Keeps the usage on this Mac across launches.
    func attach(_ defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.usageKey),
            let saved = try? JSONDecoder().decode(LauncherUsage.self, from: data)
        {
            usage = saved
        }
        refreshPicks()
    }

    public func register(_ entry: LauncherEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        version += 1
    }

    public func unregister(_ id: String) {
        entries.removeAll { $0.id == id }
        version += 1
    }
    /// Old entry ids that now open another entry (`"runners"` opens Machines), so links and buttons naming them keep working.
    public var aliases: [String: String] = [:]
    public func entry(_ id: String) -> LauncherEntry? {
        let id = aliases[id] ?? id
        return entries.first { $0.id == id }
    }

    func remember(_ id: String, at date: Date = Date()) {
        recents = Array(([id] + recents.filter { $0 != id }).prefix(3))
        usage.record(id, at: date)
        if let data = try? JSONEncoder().encode(usage) { defaults?.set(data, forKey: Self.usageKey) }
        refreshPicks(at: date)
    }

    /// The most wanted entries now: used ones by their score, then the apps in the order they were registered until there are six.
    func refreshPicks(at now: Date = Date()) {
        let scored = entries.map { ($0, usage.score($0.id, at: now)) }
        bonus = Dictionary(uniqueKeysWithValues: scored.map { ($0.0.id, min($0.1 * 1.5, 8)) })
        var out: [LauncherPick] = scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(Self.pickCount).map {
            LauncherPick(entry: $0.0, reason: usage.reason($0.0.id, at: now) ?? $0.0.sub ?? "")
        }
        if out.count < Self.pickCount {
            let have = Set(out.map(\.id))
            let fill = entries.filter {
                !have.contains($0.id) && LauncherSection.of($0) == .apps && $0.tile == .blue
            }
            out += fill.prefix(Self.pickCount - out.count).map { LauncherPick(entry: $0, reason: $0.sub ?? "") }
        }
        picks = out
    }
}

struct LauncherRow: Identifiable {
    let entry: LauncherEntry
    let group: LauncherEntry.Group
    let matched: [Int]
    var score: Double = 0
    var id: String { entry.id }
}

/// What a search offers when nothing matches: modules register theirs ("Ask AI about …"), each takes the typed words.
public struct LauncherFallback: Identifiable {
    public let id: String
    public let title: @MainActor (String) -> String
    public let symbol: String
    public let run: @MainActor (String) -> Void
    public init(
        id: String, symbol: String, title: @escaping @MainActor (String) -> String,
        run: @escaping @MainActor (String) -> Void
    ) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.run = run
    }
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
    @MainActor static func rank(
        _ entries: [LauncherEntry], query: String, recents: [String], usage: [String: Double] = [:]
    ) -> [LauncherRow] {
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
                    (
                        LauncherRow(entry: e, group: group(e), matched: at),
                        total + (recents.contains(e.id) ? 6 : 0) + (usage[e.id] ?? 0)
                    ))
            }
        }
        hits.sort { $0.score > $1.score }
        hits = hits.map { h in
            var row = h.row
            row.score = h.score
            return (row: row, score: h.score)
        }
        guard let top = hits.first else { return [] }
        let tail = hits.dropFirst().sorted {
            $0.row.group.rawValue != $1.row.group.rawValue
                ? $0.row.group.rawValue < $1.row.group.rawValue : $0.score > $1.score
        }
        return [LauncherRow(entry: top.row.entry, group: .topHit, matched: top.row.matched)] + tail.map(\.row)
    }
}
