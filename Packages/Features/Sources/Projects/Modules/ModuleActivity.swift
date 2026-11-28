import CoreUI
import SwiftUI

enum ActivityKind: String, CaseIterable, Identifiable {
    case all = "All"
    case runs = "Runs"
    case code = "Code"
    case ai = "AI"
    case brain = "Brain"
    var id: String { rawValue }
}

/// One thing that happened in the project.
struct ActivityEvent: Identifiable, Equatable {
    let id: String
    /// Never `.all`.
    let kind: ActivityKind
    let tone: Tone
    let title: String
    let detail: String
    let at: Date
}

/// The full timeline: what the app knows (runs, repo copies, who changed what), by day, newest first.
/// The Core serves no dated Brain events and no dated session events yet, so those filters show only what the changes route says.
@MainActor enum ActivityFeed {
    static func events(repos: [RepoItem], runs: [RunRecord], names: [Int64: String], changes: ChangesInfo?)
        -> [ActivityEvent]
    {
        var out: [ActivityEvent] = []
        for r in runs {
            let name = r.configID.flatMap { names[$0] }.map { " \($0)" } ?? ""
            if let at = r.startedAt {
                let failed = r.state == "failed"
                out.append(
                    ActivityEvent(
                        id: "run\(r.id)", kind: .runs, tone: failed ? .fail : .run,
                        title: failed ? (name.isEmpty ? "Start failed" : "\(name.dropFirst()) failed to start") : "Started\(name)",
                        detail: failed ? (r.error ?? ProjectsModel.reason(r.stopReason)) : "on \(r.runner)", at: at))
            }
            if let at = r.stoppedAt, r.state == "stopped" {
                out.append(
                    ActivityEvent(
                        id: "stop\(r.id)", kind: .runs, tone: .queue, title: "Stopped\(name)",
                        detail: r.stopReason.map { ProjectsModel.reason($0) } ?? "", at: at))
            }
        }
        for r in repos {
            guard let at = r.fetchedAt else { continue }
            let failed = RepoWords.broken(r)
            out.append(
                ActivityEvent(
                    id: "repo\(r.id)", kind: .code, tone: failed ? .fail : .run,
                    title: failed ? "\(r.name) could not be fetched" : "\(r.name) fetched",
                    detail: r.head.map { String($0.prefix(7)) } ?? "", at: at))
        }
        for c in changes?.recent ?? [] {
            guard let at = c.at else { continue }
            let session = c.kind == "session"
            out.append(
                ActivityEvent(
                    id: "chg\(c.id)", kind: session ? .ai : .code, tone: session ? .done : .run, title: c.summary,
                    detail: "by \(c.who)", at: at))
        }
        return out.sorted { $0.at > $1.at }
    }

    static func filter(_ events: [ActivityEvent], _ kind: ActivityKind) -> [ActivityEvent] {
        kind == .all ? events : events.filter { $0.kind == kind }
    }

    /// Today, Yesterday, then the date, newest first.
    static func days(_ events: [ActivityEvent], now: Date, calendar: Calendar = .current) -> [ModuleGroupData<
        ActivityEvent
    >] {
        var order: [Date] = []
        var byDay: [Date: [ActivityEvent]] = [:]
        for e in events.sorted(by: { $0.at > $1.at }) {
            let d = calendar.startOfDay(for: e.at)
            if byDay[d] == nil { order.append(d) }
            byDay[d, default: []].append(e)
        }
        let today = calendar.startOfDay(for: now)
        let f = DateFormatter()
        f.calendar = calendar
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return order.map {
            let name =
                $0 == today
                ? "Today"
                : calendar.date(byAdding: .day, value: -1, to: today) == $0 ? "Yesterday" : f.string(from: $0)
            return ModuleGroupData(title: name, items: byDay[$0] ?? [])
        }
    }
}

/// The Activity focused page (details v2): one timeline, filtered by what kind of thing happened.
struct ModuleActivity: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var kind = ActivityKind.all
    @State private var runs: [RunRecord] = []
    @State private var names: [Int64: String] = [:]
    @State private var runsFailure: String?
    @State private var insights: ProjectInsightsModel

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _insights = State(initialValue: ProjectInsightsModel(model: model, project: project))
    }

    private var all: [ActivityEvent] {
        ActivityFeed.events(repos: project.repos, runs: runs, names: names, changes: insights.changes)
    }

    var body: some View {
        let shown = ActivityFeed.filter(all, kind)
        ModulePage(title: "Activity") {
            CoreSegmented(
                "Show", segments: ActivityKind.allCases.map { CoreSegment($0, $0.rawValue) }, selection: $kind)
        } content: {
            ModuleWell {
                if let why = insights.failures["changes"] ?? runsFailure {
                    LoadFailed(what: "the activity", why: why) { Task { await load() } }.padding(Space.s4)
                } else if shown.isEmpty {
                    ModuleQuiet(
                        symbol: "waveform.path.ecg",
                        title: kind == .all ? "Nothing has happened yet" : "No \(kind.rawValue) activity",
                        line: kind == .all
                            ? "Starts, repo copies and AI sessions show here as they happen."
                            : "Nothing from \(kind.rawValue) in this project yet.")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.s2) {
                            ForEach(ActivityFeed.days(shown, now: model.now()), id: \.title) { day in
                                ModuleGroup(day.title).padding(.leading, 0)
                                ForEach(day.items) { event($0) }
                            }
                        }
                        .frame(maxWidth: Space.s8 * 22, alignment: .leading).padding(.horizontal, Space.s5).padding(
                            .vertical, Space.s3
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(Motion.out(Motion.ui), value: shown)
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(Motion.out(Motion.ui), value: kind)
        .task(id: project.id) { await load() }
    }

    private func load() async {
        await insights.loadChanges()
        guard let svc = model.configsService else { return }
        do {
            runs = try await svc.history(project: project.id)
            names = Dictionary(
                uniqueKeysWithValues: ((try? await svc.configs(project: project.id)) ?? []).map { ($0.id, $0.name) })
            runsFailure = nil
        } catch { runsFailure = model.words(error) }
    }

    private func event(_ e: ActivityEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            ModuleDot(tone: e.tone)
            VStack(alignment: .leading, spacing: 0) {
                Text(e.title).coreFont(size: MacTextSize.body, weight: .medium)
                Text(
                    e.detail.isEmpty
                        ? runsAgo(e.at, now: model.now()) : "\(e.detail) · \(runsAgo(e.at, now: model.now()))"
                )
                .coreFont(size: MacTextSize.meta).foregroundStyle(GlassInk.secondary)
            }
        }
        .padding(.vertical, Space.s1).padding(.horizontal, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading).transition(.opacity)
    }
}
