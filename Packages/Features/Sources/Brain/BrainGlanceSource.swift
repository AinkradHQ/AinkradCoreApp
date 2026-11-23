import CoreKit
import CoreUI
import Foundation
import Shell

// What the top bar's Brain dropdown reads from a Core with API minor 95 (E2 round 2): the Brain module's `GET /activity`,
// `/areas` and `/learned`, and `POST /rooms/{room}/records/{id}/archive` for the Undo. These wire types are private to the
// dropdown on purpose; the Brain screens of E9 own the full ones.

struct GlanceActivity: Decodable, Equatable {
    var state: String
    var health: String
    var rooms: Int
    var distilling: Int
    var queued: Int
    var overviews: Int
    var needs: [Need]
    struct Need: Decodable, Equatable { var kind: String }
}

struct GlanceAreas: Decodable, Equatable {
    var areas: [Summary]
    var places: Int
    struct Summary: Decodable, Equatable {
        var area: String
        var count: Int
        var today: Int?
        /// API minor 101: the last 14 days, oldest first.
        var series: [Int]?
    }
}

struct GlanceLearned: Decodable, Equatable {
    var id: String
    var room: String
    var body: String?
    var createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, room, body
        case createdAt = "created_at"
    }
}

/// One read of the three routes.
struct GlanceData: Equatable {
    var activity: GlanceActivity
    var areas: GlanceAreas
    var learned: [GlanceLearned]
}

extension BrainRoutes {
    func glanceData() async throws -> GlanceData {
        async let a: GlanceActivity = call("GET", "/activity")
        async let b: GlanceAreas = call("GET", "/areas")
        async let c: [GlanceLearned] = call("GET", "/learned")
        return try await GlanceData(activity: a, areas: b, learned: c)
    }

    /// Takes one record out of memory (archived and kept, never deleted).
    func glanceArchive(room: String, id: String) async throws {
        struct Done: Decodable { var archived: Bool }
        _ = try await call("POST", "/rooms/\(Self.seg(room))/records/\(Self.seg(id))/archive", as: Done.self)
    }
}

enum BrainGlanceMaker {
    static let areaOrder: [(key: String, label: String)] = [
        ("me", "About you"), ("rules", "Rules"), ("knowledge", "Knowledge"), ("timeline", "Timeline"),
    ]
    /// The dropdown's tiles, in the redesign's order.
    static let tileOrder: [(key: String, label: String, symbol: String)] = [
        ("knowledge", "Knowledge", "sparkles"), ("rules", "Rules", "checkmark"), ("timeline", "Timeline", "clock"),
        ("me", "About you", "person"),
    ]

    static func status(_ a: GlanceActivity) -> String {
        switch a.state {
        case "locked": "Locked. Unlock your Core to let it learn"
        case "needs_you": a.needs.first.map(need) ?? "Paused until it has what it needs"
        case "working": "Learning"
        default: "Up to date"
        }
    }

    static func need(_ n: GlanceActivity.Need) -> String {
        switch n.kind {
        case "ai_account": "Needs an AI account"
        case "runner": "Needs a runner that is online"
        case "local_model": "Needs a local model"
        default: "Unlock your Core"
        }
    }

    /// The step it is on (Collect 0, Distill 1, Remember 2) and the line under the flow; nil when it is idle.
    static func doing(_ a: GlanceActivity) -> (step: Int, line: String, progress: Double?)? {
        guard a.state == "working" else { return nil }
        let waiting = a.distilling + a.queued
        let done = a.rooms > 0 ? Double(max(a.rooms - waiting, 0)) / Double(a.rooms) : nil
        func places(_ n: Int) -> String { "\(n) \(n == 1 ? "place" : "places")" }
        if a.distilling > 0 { return (1, "Understanding \(places(a.distilling))", done) }
        if a.overviews > 0 { return (2, "Writing an overview of your places", done) }
        if a.queued > 0 { return (0, "Reading \(places(a.queued))", done) }
        return nil
    }

    static func glance(_ d: GlanceData) -> BrainGlance {
        let doing = doing(d.activity)
        let counts = Dictionary(d.areas.areas.map { ($0.area, $0.count) }, uniquingKeysWith: +)
        let stats =
            areaOrder.map { BrainGlance.Stat($0.label, counts[$0.key] ?? 0, area: $0.key) }
            + [BrainGlance.Stat("Places", d.areas.places, area: "places")]
        var g = BrainGlance(
            status: status(d.activity), healthy: d.activity.health == "ok", doing: doing?.line,
            progress: doing?.progress, stats: stats, flowStep: doing?.step, learned: d.learned.count)
        let by = Dictionary(d.areas.areas.map { ($0.area, $0) }, uniquingKeysWith: { a, _ in a })
        g.tiles = tileOrder.map { t in
            let s = by[t.key]
            return .init(
                area: t.key, label: t.label, symbol: t.symbol, count: s?.count ?? 0, today: s?.today ?? 0,
                series: s?.series)
        }
        g.known = d.areas.areas.reduce(0) { $0 + $1.count }
        g.places = d.areas.places
        let newest = d.learned.max { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
        g.latest = newest?.body
        g.lastLearned = SyncWords.date(newest?.createdAt).map { SyncWords.agoInLine($0) }
        return g
    }
}

extension BrainModel {
    /// A Core with API minor 95 and real routes; the sample and an older Core keep the Rooms and Records counts.
    var servesGlance: Bool { !isSample && (apiMinor ?? 0) >= Int(coreMinorV010) && service?.importRoutes != nil }

    /// Reads the dropdown's numbers; a failure keeps the last ones.
    func refreshGlance() async {
        guard servesGlance, let routes = service?.importRoutes else { return }
        if let d = try? await routes.glanceData() { glanceData = d }
    }

    /// Forgets what was learned today (archived, never deleted); the toast's Undo puts it all back.
    func undoLearned() {
        guard let routes = service?.importRoutes, let d = glanceData, !d.learned.isEmpty else { return }
        let shell = host.shell
        Task { @MainActor in
            var undone: [GlanceLearned] = []
            for l in d.learned where (try? await routes.glanceArchive(room: l.room, id: l.id)) != nil {
                undone.append(l)
            }
            glanceData?.learned.removeAll()
            let n = undone.count
            shell.showToast(
                n == d.learned.count
                    ? "Forgot \(n) \(n == 1 ? "thing" : "things") learned today · kept in the archive"
                    : "Forgot \(n) of \(d.learned.count). The rest could not be reached.",
                kind: n == d.learned.count ? .ok : .warn
            ) {
                Task {
                    for l in undone { try? await routes.restoreRecord(room: l.room, id: l.id) }
                    await self.refreshGlance()
                }
            }
            await refreshGlance()
        }
    }
}

// MARK: an import under way

extension ImportModel {
    /// "Waiting for you to review 7 places": the Brain dropdown's line while the review waits (nothing is filed before).
    static func waiting(places n: Int) -> String {
        n == 0
            ? "Waiting for you to approve the import"
            : "Waiting for you to review \(BrainWords.plural(n, "place", "places"))"
    }

    /// What the top bar, its dropdown and Brain Home say about this import; nil when none runs.
    var glance: BrainGlance.Importing? {
        guard isActive else { return nil }
        let names = autoSort ? ImportWizard.autoSteps : ImportWizard.steps
        let step = names[step.rawValue]
        switch self.step {
        case .collecting:
            if phase == .discovering { return .init(step: step, line: "Sorting into rooms") }
            let t = itemsDone
            return .init(
                step: step, line: "Reading your sessions",
                detail: t.total == 0 ? nil : "\(t.done.formatted()) of \(t.total.formatted())",
                progress: t.total == 0 ? nil : Double(t.done) / Double(t.total))
        case .review:
            guard autoSort else { return .init(step: step, line: "Waiting for you to review the rooms", progress: 1) }
            if case .sorted(let n) = auto.sort {
                return .init(step: step, line: "Sorted into \(BrainWords.plural(n, "place", "places"))", progress: 1)
            }
            if review.semanticState == "pending" || auto.sort == .checking {
                let p = review.semanticProgress
                return .init(
                    step: step, line: "The local model is reading your work",
                    detail: p.map { SortStep.count($0, left: review.readingLeft) },
                    progress: p.map { Double($0.done) / Double(max($0.total, 1)) })
            }
            return .init(step: step, line: Self.waiting(places: review.places.count), progress: 1)
        case .importing:
            guard autoSort, let l = auto.learning, !l.places.isEmpty else {
                return .init(step: step, line: autoSort ? "Learning from your work" : "Importing the checked rooms")
            }
            let read = l.places.reduce(0) { $0 + $1.read }
            let all = l.places.reduce(0) { $0 + $1.sources }
            return .init(
                step: step, line: "Learning from your work",
                detail: all == 0 ? nil : "\(read.formatted()) of \(all.formatted())",
                progress: all == 0 ? nil : min(1, Double(read) / Double(all)))
        case .sources, .done: return nil
        }
    }
}

extension BrainModel {
    /// The import under way, if any (the Debug demo can stand one in).
    var importGlance: BrainGlance.Importing? {
        #if DEBUG
        if let demoImport { return demoImport }
        #endif
        return importer?.glance
    }

    /// The top-bar icon's state: an import under way counts as working, else the Core's status call.
    var topChip: Shell.BrainChip? {
        guard let i = importGlance else { return status.chip }
        return Shell.BrainChip(
            state: "working", line: "Importing: \(i.line)", needs: [], attention: status.chip?.attention ?? false,
            progress: i.progress)
    }
}

extension BrainModel {
    /// The dropdown's numbers, before the import under way is added.
    var baseGlance: BrainGlance? {
        if self.servesGlance, let d = self.glanceData { return BrainGlanceMaker.glance(d) }
        #if DEBUG
        if demoCalm, let g = demoGlance { return g }
        #endif
        let o = self.overview
        let status =
            switch o?.health {
            case .paused?: "Paused"
            case .needsYou?: "Something needs a look"
            default: "Learning quietly in the background"
            }
        let records = self.rooms.reduce(0) { $0 + ($1.counts?.records ?? 0) }
        return BrainGlance(
            status: status, healthy: (o?.health ?? .healthy) == .healthy,
            stats: [
                .init("Rooms", self.rooms.count), .init("Records", records), .init("To check", o?.needs.count ?? 0),
            ])
    }
}

#if DEBUG
extension BrainModel {
    /// Debug demo only: the dropdown read from the demo's areas and status, as a Core with them would answer.
    var demoGlance: BrainGlance? {
        guard let a = calm.areas, let act = status.activity else { return nil }
        let activity = GlanceActivity(
            state: act.state, health: act.health, rooms: act.rooms, distilling: act.distilling, queued: act.queued,
            overviews: act.overviews, needs: act.needs.map { .init(kind: $0.kind) })
        let areas = GlanceAreas(
            areas: a.areas.map { .init(area: $0.area, count: $0.count, today: $0.today, series: $0.series) },
            places: calm.places?.count ?? a.places)
        let learned = calm.learned.map {
            GlanceLearned(id: $0.id, room: $0.room, body: $0.body, createdAt: $0.createdAt)
        }
        return BrainGlanceMaker.glance(GlanceData(activity: activity, areas: areas, learned: learned))
    }
}
#endif
