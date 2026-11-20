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
    }
}

struct GlanceLearned: Decodable, Equatable {
    var id: String
    var room: String
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
        ("me", "Me"), ("rules", "Rules"), ("knowledge", "Knowledge"), ("timeline", "Timeline"),
    ]

    static func status(_ a: GlanceActivity) -> String {
        switch a.state {
        case "locked": "Locked. Unlock your Core to let it learn"
        case "needs_you": a.needs.first.map(need) ?? "Paused until it has what it needs"
        case "working": "Learning quietly in the background"
        default: "Learning quietly in the background"
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
        if a.distilling > 0 { return (1, "Tidying \(places(a.distilling)) into Knowledge", done) }
        if a.overviews > 0 { return (2, "Writing an overview of your places", done) }
        if a.queued > 0 { return (0, "Collecting from \(places(a.queued))", done) }
        return nil
    }

    static func glance(_ d: GlanceData) -> BrainGlance {
        let doing = doing(d.activity)
        let counts = Dictionary(d.areas.areas.map { ($0.area, $0.count) }, uniquingKeysWith: +)
        let stats =
            areaOrder.map { BrainGlance.Stat($0.label, counts[$0.key] ?? 0, area: $0.key) }
            + [BrainGlance.Stat("Places", d.areas.places, area: "places")]
        return BrainGlance(
            status: status(d.activity), healthy: d.activity.health == "ok", doing: doing?.line,
            progress: doing?.progress, stats: stats, flowStep: doing?.step, learned: d.learned.count)
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

    /// Archives what was learned today (kept, never deleted) and says so.
    func undoLearned() {
        guard let routes = service?.importRoutes, let d = glanceData, !d.learned.isEmpty else { return }
        let shell = host.shell
        Task { @MainActor in
            var undone = 0
            for l in d.learned where (try? await routes.glanceArchive(room: l.room, id: l.id)) != nil { undone += 1 }
            glanceData?.learned.removeAll()
            shell.showToast(
                undone == d.learned.count
                    ? "Took back \(undone) \(undone == 1 ? "thing" : "things") it learned today."
                    : "Took back \(undone) of \(d.learned.count). The rest could not be reached.",
                kind: undone == d.learned.count ? .ok : .warn)
            await refreshGlance()
        }
    }
}
