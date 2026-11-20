import CoreKit
import Foundation
import Observation

// What the rail tabs show beyond the project itself (Core 0.10, E11-3): per-repo code facts, AI usage, who changed what, what the
// Brain knows of the project's place, the AI documents and the fetch tuning. Every call is gated by `serverSupports(minor: 95)` in
// `ProjectsModel.insightsService`. Security model: only counts, names, short summaries and costs are read; nothing here is a
// secret, and a Brain record's text is shown as plain text.

struct CommitInfo: Equatable, Sendable {
    let sha: String
    let author: String
    let message: String
    let at: Date?
}

struct CodeInfo: Equatable, Identifiable, Sendable {
    let repo: String
    let files: Int
    let branch: String
    let ahead: Int
    let behind: Int
    let last: CommitInfo?
    var id: String { repo }
}

struct UsageSession: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let state: String
    let cost: Double
    let spark: [Double]
    var running: Bool { state == "running" || state == "starting" }
}

struct UsageInfo: Equatable, Sendable {
    var weekCost = 0.0
    var prevWeekCost = 0.0
    var sessionsWeek = 0
    var byDay: [Double] = []
    var sessions: [UsageSession] = []

    /// "Up 12% on last week", "Down 5% on last week", or a plain line when last week had none.
    var trend: String {
        guard prevWeekCost > 0 else { return weekCost > 0 ? "First week with usage" : "No usage yet" }
        let pct = Int(((weekCost - prevWeekCost) / prevWeekCost * 100).rounded())
        return pct == 0 ? "Same as last week" : "\(pct > 0 ? "Up" : "Down") \(abs(pct))% on last week"
    }
    var running: Int { sessions.filter(\.running).count }
}

struct ChangeLine: Equatable, Identifiable, Sendable {
    let who: String
    /// `commit` or `session`.
    let kind: String
    let summary: String
    let at: Date?
    var id: String { "\(who)\(kind)\(summary)\(at?.timeIntervalSince1970 ?? 0)" }
}

struct ChangesInfo: Equatable, Sendable {
    var byAuthor: [(who: String, count: Int)] = []
    var recent: [ChangeLine] = []
    static func == (a: ChangesInfo, b: ChangesInfo) -> Bool {
        a.recent == b.recent && a.byAuthor.map(\.who) == b.byAuthor.map(\.who)
            && a.byAuthor.map(\.count) == b.byAuthor.map(\.count)
    }
}

/// A Brain record of an area (`/areas/{area}`), cut to what a card shows.
struct KnownRecord: Equatable, Identifiable, Sendable {
    let id: String
    /// The Brain room (place) id the record lives in; matched against the project's linked room, never by name.
    let room: String
    let roomName: String
    let kind: String
    let body: String
}

struct SessionDocItem: Equatable, Identifiable, Sendable {
    let note: String
    let session: String
    let path: String
    let title: String
    let sessionTitle: String?
    let project: String?
    let updatedAt: Date?
    var id: String { note }
}

/// The per-project knobs the Core keeps: how often it fetches the repos (minutes; 0 = only when asked) and the default environment.
struct ProjectTuning: Equatable, Sendable {
    var fetchInterval = 15
    var defaultEnvironment: String?
    /// The project's Brain room (`brain_project_rooms`), nil when the Brain is off or none is linked.
    var roomID: String?
}

protocol ProjectInsightsService: Sendable {
    func code(project: Int64) async throws -> [CodeInfo]
    func usage(project: Int64) async throws -> UsageInfo
    func changes(project: Int64) async throws -> ChangesInfo
    /// The records of a Brain area (`me`, `rules`, `knowledge`, `timeline`) across the open rooms.
    func area(_ area: String, room: String?) async throws -> [KnownRecord]
    func sessionDocs() async throws -> [SessionDocItem]
    func tuning(project: Int64) async throws -> ProjectTuning
    func setTuning(project: Int64, fetchInterval: Int?, defaultEnvironment: String?) async throws
    /// Undoes an archive (`POST /projects/{id}/unarchive`, admin, step-up): the project is active again.
    func unarchive(project: Int64) async throws
}

struct LiveProjectInsightsService: ProjectInsightsService {
    let connection: CoreConnection

    func code(project: Int64) async throws -> [CodeInfo] {
        try InsightsWire.code(try await call("GET", "/api/v1/projects/\(project)/code"))
    }
    func usage(project: Int64) async throws -> UsageInfo {
        try InsightsWire.usage(try await call("GET", "/api/v1/projects/\(project)/usage"))
    }
    func changes(project: Int64) async throws -> ChangesInfo {
        try InsightsWire.changes(try await call("GET", "/api/v1/projects/\(project)/changes"))
    }
    func area(_ area: String, room: String?) async throws -> [KnownRecord] {
        // The room filter keeps the project's own records out of the Core's 200-record cap.
        let only = room.map { "&room=\(LiveProjectRunService.seg($0))" } ?? ""
        return try InsightsWire.records(
            try await call("GET", "/modules/brain/v1/areas/\(LiveProjectRunService.seg(area))?limit=200\(only)"))
    }
    func sessionDocs() async throws -> [SessionDocItem] {
        try InsightsWire.docs(try await call("GET", "/modules/lore/v1/session-docs"))
    }
    func tuning(project: Int64) async throws -> ProjectTuning {
        try InsightsWire.tuning(try await call("GET", "/api/v1/projects/\(project)"))
    }
    func setTuning(project: Int64, fetchInterval: Int?, defaultEnvironment: String?) async throws {
        var o: [String: Any] = [:]
        if let fetchInterval { o["fetch_interval_minutes"] = fetchInterval }
        if let defaultEnvironment { o["default_environment"] = defaultEnvironment }
        _ = try await call("PATCH", "/api/v1/projects/\(project)", try JSONSerialization.data(withJSONObject: o))
    }

    func unarchive(project: Int64) async throws {
        _ = try await call("POST", "/api/v1/projects/\(project)/unarchive")
    }

    private func call(_ method: String, _ path: String, _ body: Data = Data()) async throws -> Data {
        do {
            return try await connection.signedRequest(method: method, target: path, body: body)
        } catch CoreError.http(let status, let code, let message) {
            throw LiveProjectRunService.failure(status: status, code: code, message: message)
        } catch CoreError.badRequest(let message) {
            throw LiveProjectRunService.failure(status: 400, code: "bad_request", message: message)
        }
    }
}

enum InsightsWire {
    private static func list(_ d: Data) throws -> [[String: Any]] {
        guard let l = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { throw RunWire.bad }
        return l
    }
    private static func object(_ d: Data) throws -> [String: Any] {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw RunWire.bad }
        return o
    }
    private static func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }
    private static func dbl(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
    private static func nums(_ v: Any?) -> [Double] { (v as? [NSNumber])?.map(\.doubleValue) ?? [] }

    static func code(_ d: Data) throws -> [CodeInfo] {
        try list(d).map {
            guard let repo = $0["repo"] as? String else { throw RunWire.bad }
            let c = ($0["last_commit"] as? [String: Any]).flatMap { c -> CommitInfo? in
                guard let sha = c["sha"] as? String else { return nil }
                return CommitInfo(
                    sha: sha, author: c["author"] as? String ?? "", message: c["message"] as? String ?? "",
                    at: RunWire.date(c["at"] as? String))
            }
            return CodeInfo(
                repo: repo, files: int($0["files"]), branch: $0["branch"] as? String ?? "", ahead: int($0["ahead"]),
                behind: int($0["behind"]), last: c)
        }
    }

    static func usage(_ d: Data) throws -> UsageInfo {
        let o = try object(d)
        let rows = (o["sessions"] as? [[String: Any]]) ?? []
        return UsageInfo(
            weekCost: dbl(o["week_cost"]), prevWeekCost: dbl(o["prev_week_cost"]),
            sessionsWeek: int(o["sessions_week"]),
            byDay: nums(o["by_day"]),
            sessions: rows.compactMap {
                guard let id = $0["id"] as? String else { return nil }
                return UsageSession(
                    id: id, title: $0["title"] as? String ?? "Session", state: $0["state"] as? String ?? "",
                    cost: dbl($0["cost"]), spark: nums($0["spark"]))
            })
    }

    static func changes(_ d: Data) throws -> ChangesInfo {
        let o = try object(d)
        let by = ((o["by_author"] as? [[String: Any]]) ?? []).compactMap { a -> (who: String, count: Int)? in
            guard let w = a["who"] as? String else { return nil }
            return (w, int(a["count"]))
        }
        let recent = ((o["recent"] as? [[String: Any]]) ?? []).compactMap { r -> ChangeLine? in
            guard let w = r["who"] as? String, let s = r["summary"] as? String else { return nil }
            return ChangeLine(
                who: w, kind: r["kind"] as? String ?? "commit", summary: s, at: RunWire.date(r["at"] as? String))
        }
        return ChangesInfo(byAuthor: by, recent: recent)
    }

    static func records(_ d: Data) throws -> [KnownRecord] {
        let rows = (try object(d)["records"] as? [[String: Any]]) ?? []
        return rows.compactMap {
            guard let id = $0["id"] as? String, let body = $0["body"] as? String else { return nil }
            return KnownRecord(
                id: id, room: $0["room"] as? String ?? "", roomName: $0["room_name"] as? String ?? "",
                kind: $0["type"] as? String ?? "", body: body)
        }
    }

    static func docs(_ d: Data) throws -> [SessionDocItem] {
        try list(d).compactMap {
            guard let note = $0["note"] as? String, let session = $0["session"] as? String else { return nil }
            return SessionDocItem(
                note: note, session: session, path: $0["path"] as? String ?? "", title: $0["title"] as? String ?? "",
                sessionTitle: $0["session_title"] as? String, project: $0["project"] as? String,
                updatedAt: RunWire.date($0["updated_at"] as? String))
        }
    }

    static func tuning(_ d: Data) throws -> ProjectTuning {
        let o = try object(d)
        return ProjectTuning(
            fetchInterval: (o["fetch_interval_minutes"] as? NSNumber)?.intValue ?? 15,
            defaultEnvironment: o["default_environment"] as? String,
            roomID: (o["room"] as? [String: Any])?["room_id"] as? String)
    }
}

/// What a project's place in the Brain holds: the records of the project's linked room (`brain_project_rooms`, as the project's
/// `room.room_id`). A project with no linked room has none.
enum ProjectKnowledge {
    static func records(_ all: [KnownRecord], room: String?) -> [KnownRecord] {
        guard let room, !room.isEmpty else { return [] }
        return all.filter { $0.room == room }
    }
}

/// Loads each rail tab's extra data on its own, so one failing route never blanks a page. Values the Core does not give stay nil
/// or empty and the views say so; nothing is guessed.
@MainActor @Observable
final class ProjectInsightsModel {
    let model: ProjectsModel
    let project: ProjectItem
    private(set) var code: [CodeInfo]?
    private(set) var usage: UsageInfo?
    private(set) var changes: ChangesInfo?
    private(set) var knowledge: [KnownRecord]?
    private(set) var rules: [KnownRecord]?
    private(set) var docs: [SessionDocItem]?
    private(set) var notes: [LoreNoteLine]?
    private(set) var tuning = ProjectTuning()
    private(set) var tuningLoaded = false
    private(set) var environments: [String] = []

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
    }

    private var service: (any ProjectInsightsService)? { model.insightsService }
    var supported: Bool { service != nil }

    func loadCode() async { if let s = service { code = try? await s.code(project: project.id) } }
    func loadUsage() async { if let s = service { usage = try? await s.usage(project: project.id) } }
    func loadChanges() async { if let s = service { changes = try? await s.changes(project: project.id) } }

    func loadKnowledge() async {
        guard let s = service else { return }
        let room = (try? await s.tuning(project: project.id))?.roomID
        async let k = try? s.area("knowledge", room: room)
        async let r = try? s.area("rules", room: room)
        let (kk, rr) = await (k, r)
        knowledge = kk.map { ProjectKnowledge.records($0, room: room) }
        rules = rr.map { ProjectKnowledge.records($0, room: room) }
    }

    func loadDocs() async {
        if let s = service, let all = try? await s.sessionDocs() {
            docs = all.filter { $0.project == String(project.id) }
        }
        if let lore = model.lore,
            let l = try? await lore.list(filter: LoreFilter(kind: "note", project: String(project.id)))
        {
            notes = l.prefix(50).map { LoreNoteLine(id: $0.id, title: $0.title.isEmpty ? "Untitled" : $0.title) }
        }
    }

    func loadTuning() async {
        guard let s = service else { return }
        if let t = try? await s.tuning(project: project.id) { tuning = t }
        environments = (try? await model.configsService?.environments(project: project.id)) ?? []
        tuningLoaded = true
    }

    /// Saves one knob; the page shows the change at once and the Core's answer replaces it on the next load.
    func set(fetchInterval: Int? = nil, defaultEnvironment: String? = nil) async {
        guard let s = service, model.mayWrite() else { return }
        let was = tuning
        if let fetchInterval { tuning.fetchInterval = fetchInterval }
        if let defaultEnvironment { tuning.defaultEnvironment = defaultEnvironment }
        do {
            try await s.setTuning(
                project: project.id, fetchInterval: fetchInterval, defaultEnvironment: defaultEnvironment)
        } catch {
            tuning = was
            model.host.shell.showToast("Could not save that. Try again.", kind: .warn)
        }
    }
}

struct LoreNoteLine: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
}

/// The fetch intervals the Core accepts, as the Settings picker words them.
enum FetchInterval {
    static let options: [(minutes: Int, title: String)] = [
        (10, "Every 10 minutes"), (15, "Every 15 minutes"), (60, "Every hour"), (0, "Only when I ask"),
    ]
    /// The Core's real default is 15 minutes: it is the line the Code page shows until the Core says otherwise.
    static func line(_ minutes: Int) -> String {
        options.first { $0.minutes == minutes }.map { $0.title.lowercased() } ?? "every \(minutes) minutes"
    }
}

enum CostWords {
    /// "$4.20", and "<$0.01" for a trace of spend.
    static func money(_ v: Double) -> String {
        v > 0 && v < 0.01 ? "<$0.01" : String(format: "$%.2f", v)
    }
}
