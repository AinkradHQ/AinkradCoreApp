import Foundation

/// What the AI Sessions sidebar can show (N42, variant B). Pure, so the grouping is tested without a Core.
enum SessionSection: Hashable, CaseIterable {
    case pinned, needsYou, running, waiting, today, yesterday, thisWeek, earlier, archive

    var title: String {
        switch self {
        case .pinned: "Pinned"
        case .needsYou: "Needs you"
        case .running: "Running"
        case .waiting: "Waiting for you"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This week"
        case .earlier: "Earlier"
        case .archive: "Archive"
        }
    }

    var symbol: String {
        switch self {
        case .pinned: "pin"
        case .needsYou: "hand.raised"
        case .running: "waveform"
        case .waiting: "text.cursor"
        case .today, .yesterday, .thisWeek, .earlier: "clock"
        case .archive: "archivebox"
        }
    }
}

/// One entry of the sidebar: Active (the three live sections), a time window, the Archive, a project or a runner.
enum SessionScope: Hashable {
    case active, needsYou, running, waiting, pinned, today, yesterday, thisWeek, earlier, archive
    case project(String)
    case runner(String)
}

struct SessionFilters: Equatable {
    var search = ""
    var tool: String?
    var runner: String?
    var project: String?
    var state: Facet?
    enum Facet: String, CaseIterable { case needsYou, running, waiting, ended }
    var isEmpty: Bool { self == SessionFilters() }
}

struct SessionGroup: Identifiable, Equatable {
    let section: SessionSection
    let rows: [AgentSessionInfo]
    var id: SessionSection { section }
    var costMicros: Int64 { rows.reduce(0) { $0 + ($1.usage?.costMicros ?? 0) } }
}

/// Everything the list needs, computed in one pass over the loaded sessions.
struct SessionIndex {
    /// Ended sessions older than this many days move to the Archive (still searchable). Ahmed, 2026-11-12.
    static let archiveDays = 14

    struct Inputs {
        var items: [AgentSessionInfo]
        var needsYou: Set<String>
        var pinned: Set<String>
        var archived: Set<String>
        var now: Date = Date()
        var calendar: Calendar = .current
        var title: (AgentSessionInfo) -> String
        var runnerName: (String) -> String
        var project: (AgentSessionInfo) -> String?
    }

    private(set) var counts: [SessionScope: Int] = [:]
    /// Each session's sections: a live one is in its state section, and every one is in its time window.
    private var placed: [(s: AgentSessionInfo, state: SessionSection?, when: SessionSection)] = []
    private let inputs: Inputs
    private(set) var projects: [(name: String, count: Int)] = []
    private(set) var runners: [(id: String, count: Int)] = []

    init(_ i: Inputs) {
        inputs = i
        var projects: [String: Int] = [:]
        var runners: [String: Int] = [:]
        for s in i.items {
            let state = Self.stateSection(s, needsYou: i.needsYou.contains(s.id))
            let when = Self.window(s, i)
            placed.append((s, state, when))
            if when == .archive {
                counts[.archive, default: 0] += 1
            } else {
                counts[Self.scope(when), default: 0] += 1
                if let state { counts[Self.scope(state), default: 0] += 1 }
                if state != nil { counts[.active, default: 0] += 1 }
                if i.pinned.contains(s.id) { counts[.pinned, default: 0] += 1 }
            }
            if let p = i.project(s) { projects[p, default: 0] += 1 }
            runners[s.runner, default: 0] += 1
        }
        self.projects = projects.map { ($0.key, $0.value) }.sorted {
            $0.name.localizedCompare($1.name) == .orderedAscending
        }
        self.runners = runners.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    static func scope(_ s: SessionSection) -> SessionScope {
        switch s {
        case .pinned: .pinned
        case .needsYou: .needsYou
        case .running: .running
        case .waiting: .waiting
        case .today: .today
        case .yesterday: .yesterday
        case .thisWeek: .thisWeek
        case .earlier: .earlier
        case .archive: .archive
        }
    }

    /// Needs you (an approval waits) beats Running beats Waiting for you. Ended and lost sessions have no state section.
    static func stateSection(_ s: AgentSessionInfo, needsYou: Bool) -> SessionSection? {
        guard s.live else { return nil }
        if needsYou { return .needsYou }
        return s.idle ? .waiting : .running
    }

    /// Today, Yesterday, This week (2 to 7 days), Earlier (8 to 14), then Archive. A live session is never archived, and a
    /// session the person archived by hand always is.
    static func window(_ s: AgentSessionInfo, _ i: Inputs) -> SessionSection {
        if i.archived.contains(s.id) { return .archive }
        let last = s.updatedAt
        let cal = i.calendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: i.now)).day ?? 0
        if !s.live && days > archiveDays { return .archive }
        switch days {
        case ...0: return .today
        case 1: return .yesterday
        case 2...7: return .thisWeek
        default: return .earlier
        }
    }

    private func matches(_ r: (s: AgentSessionInfo, state: SessionSection?, when: SessionSection), _ f: SessionFilters)
        -> Bool
    {
        let s = r.s
        if let t = f.tool, AgentWords.harnessName(s.harness) != AgentWords.harnessName(t) { return false }
        if let x = f.runner, s.runner != x { return false }
        if let p = f.project, inputs.project(s) != p { return false }
        if let facet = f.state {
            switch facet {
            case .needsYou: if r.state != .needsYou { return false }
            case .running: if r.state != .running { return false }
            case .waiting: if r.state != .waiting { return false }
            case .ended: if s.live { return false }
            }
        }
        let q = f.search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let hay = [
                inputs.title(s), inputs.project(s) ?? "", AgentWords.harnessName(s.harness),
                inputs.runnerName(s.runner),
            ]
            .joined(separator: " ")
            if hay.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) == nil { return false }
        }
        return true
    }

    private func inScope(
        _ r: (s: AgentSessionInfo, state: SessionSection?, when: SessionSection), _ scope: SessionScope
    )
        -> Bool
    {
        let archived = r.when == .archive
        switch scope {
        case .archive: return archived
        case .active: return !archived && r.state != nil
        case .needsYou: return !archived && r.state == .needsYou
        case .running: return !archived && r.state == .running
        case .waiting: return !archived && r.state == .waiting
        case .pinned: return !archived && inputs.pinned.contains(r.s.id)
        case .today: return r.when == .today
        case .yesterday: return r.when == .yesterday
        case .thisWeek: return r.when == .thisWeek
        case .earlier: return r.when == .earlier
        case .project(let p): return inputs.project(r.s) == p
        case .runner(let id): return r.s.runner == id
        }
    }

    /// The groups the list shows for a sidebar entry. A search reaches the Archive too; without one it stays out of the rest.
    func groups(scope: SessionScope, filters: SessionFilters) -> [SessionGroup] {
        let searching = !filters.search.trimmingCharacters(in: .whitespaces).isEmpty
        let rows = placed.filter { r in
            matches(r, filters) && (inScope(r, scope) || (searching && scope == .active && r.state == nil))
                && (scope == .archive || searching || r.when != .archive)
        }
        let pinned = rows.filter { inputs.pinned.contains($0.s.id) && $0.when != .archive }
        var out: [SessionGroup] = []
        if !pinned.isEmpty && scope != .pinned { out.append(SessionGroup(section: .pinned, rows: sorted(pinned))) }
        let rest = rows.filter { !(inputs.pinned.contains($0.s.id) && $0.when != .archive && scope != .pinned) }
        switch scope {
        case .active:
            for sec in [SessionSection.needsYou, .running, .waiting] {
                let g = rest.filter { $0.state == sec }
                if !g.isEmpty { out.append(SessionGroup(section: sec, rows: sorted(g))) }
            }
            if searching {
                let other = rest.filter { $0.state == nil }
                if !other.isEmpty { out.append(SessionGroup(section: .earlier, rows: sorted(other))) }
            }
        case .pinned:
            if !rows.isEmpty { out.append(SessionGroup(section: .pinned, rows: sorted(rows))) }
        case .project, .runner:
            for sec in [SessionSection.today, .yesterday, .thisWeek, .earlier, .archive] {
                let g = rest.filter { $0.when == sec }
                if !g.isEmpty { out.append(SessionGroup(section: sec, rows: sorted(g))) }
            }
        default:
            let sec = Self.single(scope)
            if !rest.isEmpty { out.append(SessionGroup(section: sec, rows: sorted(rest))) }
        }
        return out
    }

    /// The section a flat view is titled with.
    static func single(_ scope: SessionScope) -> SessionSection {
        switch scope {
        case .needsYou: .needsYou
        case .running: .running
        case .waiting: .waiting
        case .today: .today
        case .yesterday: .yesterday
        case .thisWeek: .thisWeek
        case .earlier: .earlier
        case .archive: .archive
        default: .today
        }
    }

    /// Needs you first, then the most recent activity.
    private func sorted(_ r: [(s: AgentSessionInfo, state: SessionSection?, when: SessionSection)])
        -> [AgentSessionInfo]
    {
        r.sorted { $0.s.updatedAt > $1.s.updatedAt }.map(\.s)
    }

    /// The rows in the order they show, for the keyboard.
    func flat(scope: SessionScope, filters: SessionFilters) -> [AgentSessionInfo] {
        groups(scope: scope, filters: filters).flatMap(\.rows)
    }
}
