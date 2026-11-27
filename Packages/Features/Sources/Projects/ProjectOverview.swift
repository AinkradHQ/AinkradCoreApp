import CoreUI
import SwiftUI

/// The Overview: the live app, then AI Sessions, Brain, Services, Repos and Logs as islands. They settle in one after another
/// (`coreRise`; Reduce Motion fades only). What the Core does not serve yet (run state, services, logs, sessions, the room)
/// comes from `ProjectLive`, which only the Debug demo fills; see its TODOs.
struct Overview: View {
    let model: ProjectsModel
    let project: ProjectItem
    @Environment(\.spaceSettled) var settled
    @State var runs: [RunRecord] = []
    @State private var names: [Int64: String] = [:]
    @State var insights: ProjectInsightsModel
    /// The running project's log, live (Overview's Logs island).
    @State var logs: RunLogsModel?

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _insights = State(initialValue: ProjectInsightsModel(model: model, project: project))
    }

    static let columnWidth: CGFloat = 420
    static let cardWidth: CGFloat = 316
    static let bottomHeight: CGFloat = 220

    var live: ProjectLive? { project.live }
    var settingUp: Bool {
        switch project.setup {
        case .copying, .checking: true
        default: false
        }
    }

    var body: some View {
        VStack(spacing: Space.s2) {
            if project.kind == .other {
                docsFirst
            } else {
                if model.configsService != nil { statRow.coreRise(settled, 0) }
                HStack(alignment: .top, spacing: Space.s2) {
                    LiveApp(model: model, project: project).coreRise(settled, 0)
                    rightColumn.frame(width: Self.columnWidth)
                }
                .frame(maxHeight: .infinity)
                // The bottom row: 220 tall whatever the state, Services (or Build history) and Repos 316 wide, Logs the rest.
                // Infrastructure shows its services in the big island, so its bottom row is Repos and Logs.
                HStack(spacing: Space.s2) {
                    switch project.kind {
                    case .web: servicesIsland.coreRise(settled, 3).frame(width: Self.cardWidth)
                    case .app: buildHistoryIsland.coreRise(settled, 3).frame(width: Self.cardWidth)
                    default: EmptyView()
                    }
                    reposIsland.coreRise(settled, 4).frame(width: Self.cardWidth)
                    logsIsland.coreRise(settled, 5)
                }
                .frame(height: Self.bottomHeight)
            }
        }
        // The tail of the log while it runs (the Core's stream, else a page every 3 s), and the last run's log after it ends,
        // so a failed project keeps the lines that say why.
        .task(id: "\(project.id) \(project.tag) \(model.runTick)") {
            guard project.run != nil, !project.stale, let source = model.logSources(project.id, nil) else {
                if project.run == nil { logs = nil }
                return
            }
            let m = RunLogsModel(source: source)
            logs = m
            await m.run()
        }
        .task(id: project.id) {
            await model.refreshSetup(project.id)
            await model.refreshLive(project.id)
            await loadRuns()
            await insights.loadUsage()
            await insights.loadKnowledge()
            await insights.loadDocs()
        }
    }

    /// AI Sessions on top (300 tall), Brain under it taking what is left; anything more (changes, notes, designs) scrolls
    /// below, so nothing is ever pushed off the pane.
    private var rightColumn: some View {
        GeometryReader { g in
            ScrollView {
                VStack(spacing: Space.s2) {
                    sessions.frame(height: Space.s8 * 9 + Space.s3).coreRise(settled, 1)
                    brain.frame(minHeight: max(g.size.height - (Space.s8 * 9 + Space.s3) - Space.s2, 180))
                        .coreRise(settled, 2)
                    if project.kind == .infra { changesPlanIsland.coreRise(settled, 2) }
                    if project.kind == .app { testsIsland.coreRise(settled, 2) }
                    if insights.supported {
                        ChangesCard(insights: insights, now: model.now()).coreRise(settled, 2)
                        notesCard.coreRise(settled, 3)
                    }
                    if let designs = model.designsIsland {
                        designs(ProjectRef(id: String(project.id), name: project.name)).coreRise(settled, 3)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: Stats and activity (Core 0.10)

    func loadRuns() async {
        guard let svc = model.configsService else { return }
        runs = (try? await svc.history(project: project.id)) ?? []
        names = Dictionary(
            uniqueKeysWithValues: ((try? await svc.configs(project: project.id)) ?? []).map { ($0.id, $0.name) })
    }

    private var stats: ProjectStats { ProjectStats(repos: project.repos, runs: runs, now: model.now()) }

    private var statRow: some View {
        let s = stats
        let u = insights.usage
        let known = insights.knowledge?.count
        return HStack(spacing: Space.s2) {
            InsightTile(title: "Health", value: s.health, line: s.healthLine, meter: s.healthFraction)
            InsightTile(
                title: "Runs this week", value: "\(s.runsThisWeek)",
                line: s.runningNow > 0 ? "\(s.runningNow) running now" : "None running")
            if insights.supported {
                InsightTile(
                    title: "AI usage", value: u.map { CostWords.money($0.weekCost) } ?? "–",
                    line: u.map { "This week, \(ProjectItem.count($0.sessionsWeek, "session"))" } ?? "Not available",
                    spark: u?.byDay)
                InsightTile(
                    title: "Things Core knows", value: known.map(String.init) ?? "–",
                    line: known == nil ? "Not available" : "In the \(project.name) room")
            }
            activity
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var activity: some View {
        let lines = ActivityLine.timeline(repos: project.repos, runs: runs, names: names, limit: 3)
        return VStack(alignment: .leading, spacing: Space.s1) {
            Text("Activity").foregroundStyle(GlassInk.secondary)
            if lines.isEmpty { Text("Nothing yet.").foregroundStyle(GlassInk.secondary) }
            ForEach(lines) { l in
                HStack(spacing: Space.s2) {
                    Image(systemName: l.symbol).foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
                    Text(l.title).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(runsAgo(l.at, now: model.now())).foregroundStyle(GlassInk.secondary)
                }
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .topLeading).frame(maxHeight: .infinity)
        .coreCard(GlassInk.well, radius: Radius.cardMac)
    }
}
