import CoreUI
import SwiftUI

/// The Overview: the live app, then AI Sessions, Brain, Services, Repos and Logs as islands. They settle in one after another
/// (`coreRise`; Reduce Motion fades only). What the Core does not serve yet (run state, services, logs, sessions, the room)
/// comes from `ProjectLive`, which only the Debug demo fills; see its TODOs.
struct Overview: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var settled = false
    @State private var runs: [RunRecord] = []
    @State private var names: [Int64: String] = [:]
    @State private var insights: ProjectInsightsModel
    /// The running project's log, live (Overview's Logs island).
    @State private var logs: RunLogsModel?

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _insights = State(initialValue: ProjectInsightsModel(model: model, project: project))
    }

    private var live: ProjectLive? { project.live }
    private var settingUp: Bool {
        switch project.setup {
        case .copying, .checking: true
        default: false
        }
    }

    var body: some View {
        VStack(spacing: Space.s2) {
            if model.configsService != nil { statRow.coreRise(settled, 0) }
            HStack(alignment: .top, spacing: Space.s2) {
                LiveApp(model: model, project: project).coreRise(settled, 0)
                VStack(spacing: Space.s2) {
                    sessions.coreRise(settled, 1)
                    brain.coreRise(settled, 2)
                    if insights.supported {
                        ChangesCard(insights: insights, now: model.now()).coreRise(settled, 2)
                        notesCard.coreRise(settled, 3)
                    }
                    if let designs = model.designsIsland {
                        designs(ProjectRef(id: String(project.id), name: project.name)).coreRise(settled, 3)
                    }
                }
                .frame(width: Space.s8 * 10)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: Space.s2) {
                servicesIsland.coreRise(settled, 3).frame(width: Space.s8 * 14)
                reposIsland.coreRise(settled, 4).frame(width: Space.s8 * 14)
                logsIsland.coreRise(settled, 5)
            }
            .frame(height: Space.s8 * 10)
        }
        .onAppear { settled = true }
        // The tail of the log while it runs; the Core's stream, else a page every 3 s.
        .task(id: "\(project.id) \(project.tag) \(model.runTick)") {
            guard project.tag == .running || project.tag == .starting, !project.stale,
                let source = model.logSources(project.id, nil)
            else {
                logs = nil
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

    // MARK: Stats and activity (Core 0.10)

    private func loadRuns() async {
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

    // MARK: AI Sessions

    private var sessions: some View {
        let list = live?.sessions ?? []
        return Island(
            title: "AI Sessions", sub: list.isEmpty ? nil : "\(list.count)",
            accessory: {
                if !list.isEmpty {
                    CoreIconButton(symbol: "ellipsis", label: "All AI sessions") { model.section = .sessions }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if list.isEmpty {
                    Text("No AI sessions yet. New ones start in their own clone of this project's repos.")
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        ForEach(Array(list.prefix(4).enumerated()), id: \.offset) { _, s in
                            CoreRow(
                                s.title, subtitle: "\(s.harness) · \(s.when)",
                                action: s.id.map { id in { model.sessionOpener?(id) } }
                            ) { badge(s.state) }
                        }
                    }
                }
                Button {
                    model.newSession(in: project)
                } label: {
                    Label("New AI Session", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(list.isEmpty ? .secondary : .plain, size: .small))
                .disabled(!model.canStartSession(project)).help(model.sessionBlock(project))
            }
        }
    }

    private func badge(_ s: ProjectLive.Session.State) -> StateBadge {
        switch s {
        case .needsYou: StateBadge("Needs you", tone: .warn, symbol: "hand.raised")
        case .running: StateBadge("Running", tone: .run, symbol: "play.circle")
        case .done: StateBadge("Done", tone: .queue, symbol: "checkmark.circle")
        }
    }

    // MARK: Brain

    private var brain: some View {
        Island(
            title: "Brain", sub: "\(project.name) room",
            accessory: {
                Button("Open Brain") { model.section = .brain }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if let room = live?.room {
                    Text(room.summary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    Text("\(room.rules) rules · from \(room.items.formatted()) items").foregroundStyle(
                        GlassInk.secondary)
                } else if let n = insights.knowledge?.count, n > 0 {
                    Text("Core remembers \(ProjectItem.count(n, "thing")) about this project.")
                    ForEach(insights.knowledge?.prefix(2).map { $0 } ?? []) { KnownRow(r: $0) }
                } else {
                    Text(
                        settingUp
                            ? "Creating… It fills from the repos’ instruction files, AI sessions and docs you add."
                            : "Nothing remembered yet. It fills from the repos’ instruction files, AI sessions and docs you add."
                    )
                    .fixedSize(horizontal: false, vertical: true).foregroundStyle(GlassInk.secondary)
                }
            }
        }
    }

    // MARK: Notes

    private var notesCard: some View {
        let notes = insights.notes ?? []
        let docs = insights.docs ?? []
        return Island(
            title: "Notes", sub: notes.isEmpty && docs.isEmpty ? nil : "\(notes.count + docs.count)",
            accessory: {
                Button("Open Notes") { model.section = .docs }.buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        ) {
            VStack(spacing: Space.s1) {
                if notes.isEmpty && docs.isEmpty { Text("No notes yet.").foregroundStyle(GlassInk.secondary) }
                ForEach(notes.prefix(2)) { n in CoreRow(n.title, symbol: "doc.text") { model.openNote?(n.id) } }
                ForEach(docs.prefix(2)) { d in
                    CoreRow(
                        d.title.isEmpty ? d.path : d.title, subtitle: d.sessionTitle.map { "From “\($0)”" },
                        symbol: "sparkles"
                    ) {
                        model.openNote?(d.note)
                    }
                }
            }
        }
    }

    // MARK: Services

    private var servicesIsland: some View {
        Island(
            title: "Services", sub: live?.runner ?? model.coreName,
            accessory: {
                if let l = live, !l.services.isEmpty {
                    Button {
                        model.section = .run
                    } label: {
                        Label("Secrets", systemImage: "key")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                }
            }
        ) { services }
    }

    @ViewBuilder private var services: some View {
        if let l = live, !l.services.isEmpty {
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(Array(l.services.enumerated()), id: \.offset) { _, s in
                    CoreRow(s.name, symbol: Self.symbol(s.state)) {
                        if s.state == .exited {
                            StateBadge("Exited", tone: .fail, symbol: "exclamationmark.triangle")
                        } else {
                            Text(s.state == .up ? s.memory : "–").foregroundStyle(GlassInk.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        } else if let draft = project.draft {
            VStack(alignment: .leading, spacing: Space.s2) {
                ForEach(draft.services, id: \.self) { s in
                    HStack(spacing: Space.s2) {
                        StateBadge(s, tone: .queue, symbol: "circle")
                        Spacer(minLength: 0)
                        Text("–").foregroundStyle(GlassInk.secondary)
                    }
                }
            }
        } else {
            Text(
                project.repos.isEmpty
                    ? "Drafted once you add repos."
                    : project.setup == .needsSetup ? "No setup yet. Set one up in Runs." : "Reading the setup…"
            ).foregroundStyle(GlassInk.secondary)
        }
    }

    private static func symbol(_ s: ProjectLive.Service.State) -> String {
        switch s {
        case .up: "checkmark.circle"
        case .down: "circle"
        case .exited: "exclamationmark.triangle"
        }
    }

    // MARK: Repos

    private var reposIsland: some View {
        Island(
            title: "Repos", sub: project.repos.isEmpty ? nil : "\(project.repos.count)",
            accessory: {
                CoreIconButton(symbol: "plus", label: "Add repos to \(project.name)") {
                    NewProjectDialogs.openAddRepos(model, project)
                }
                .disabled(model.readOnly)
            }
        ) { repos }
    }

    @ViewBuilder private var repos: some View {
        if project.repos.isEmpty {
            Text("No repos yet.").foregroundStyle(GlassInk.secondary)
        } else {
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(project.repos) { r in
                    CoreRow(r.name, subtitle: repoLine(r), symbol: "arrow.triangle.branch") {
                        if r.fetchError != nil {
                            StateBadge("Copy failed", tone: .fail, symbol: "exclamationmark.triangle")
                        }
                    }
                    .help(r.remoteURL)
                }
            }
        }
    }

    private func repoLine(_ r: RepoItem) -> String {
        switch r.copy {
        case .failed(_, let e): return "\(r.branch) · \(e)"
        case .fetching(let since): return "\(r.branch) · \(RepoCopy.elapsed(since: since, now: model.now()))"
        case .ready: return "\(r.branch) · fetched \(PickRepo.ago(r.fetchedAt ?? model.now(), model.now()))"
        case .unknown: return "\(r.branch) · not copied yet"
        }
    }

    // MARK: Logs

    private var logsIsland: some View {
        let real = logs.map { $0.lineCount > 0 } ?? false
        let demo = live?.logs ?? []
        return Island(
            title: "Logs", sub: real || !demo.isEmpty ? "all services" : nil,
            accessory: {
                if real || !demo.isEmpty {
                    CoreIconButton(symbol: "ellipsis", label: "Open the logs in Run") { model.section = .run }
                }
            }
        ) {
            if let logs, real {
                RunLogView(logs: logs, compact: true)
            } else if !demo.isEmpty {
                VStack(alignment: .leading, spacing: Space.s1) {
                    ForEach(Array(demo.enumerated()), id: \.offset) { _, l in
                        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                            Text(l.service).foregroundStyle(GlassInk.secondary).frame(
                                width: Space.s8 * 2, alignment: .leading)
                            Text(l.text).lineLimit(1)
                        }
                        .font(.system(size: MacTextSize.body, design: .monospaced))
                    }
                }
            } else {
                Text(
                    project.tag == .running || project.tag == .starting
                        ? "Waiting for the first line…" : "Logs appear while the project runs."
                )
                .foregroundStyle(GlassInk.secondary)
            }
        }
    }
}
