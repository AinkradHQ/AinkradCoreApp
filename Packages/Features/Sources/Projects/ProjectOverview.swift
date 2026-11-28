import CoreUI
import SwiftUI

/// The Overview (details v2): the stage across the full width, then the modules in three columns. The stage shows the
/// project live per kind; each module's header opens its focused page. What the Core does not serve yet (services, logs,
/// sessions, the room) comes from `ProjectLive`, which only the Debug demo fills.
struct Overview: View {
    let model: ProjectsModel
    let project: ProjectItem
    @Binding var stageKind: ProjectKind?
    @Environment(\.spaceSettled) var settled
    @State var runs: [RunRecord] = []
    @State var names: [Int64: String] = [:]
    @State var insights: ProjectInsightsModel
    /// The running project's log, live (the Logs module).
    @State var logs: RunLogsModel?

    init(model: ProjectsModel, project: ProjectItem, stageKind: Binding<ProjectKind?>) {
        self.model = model
        self.project = project
        _stageKind = stageKind
        _insights = State(initialValue: ProjectInsightsModel(model: model, project: project))
    }

    /// For the module stubs that still show the Overview (their lanes replace them).
    init(model: ProjectsModel, project: ProjectItem) {
        self.init(model: model, project: project, stageKind: .constant(nil))
    }

    static let columns = 3
    var live: ProjectLive? { project.live }
    var settingUp: Bool {
        switch project.setup {
        case .copying, .checking: true
        default: false
        }
    }

    /// The modules under the stage, chosen by what the project is.
    var cells: [(module: ProjectModule, view: AnyView)] {
        let k = project.allKinds
        var out: [(ProjectModule, AnyView)] = [(.ai, AnyView(sessions)), (.brain, AnyView(brain))]
        if k.contains(.web) || k.contains(.infra) { out.append((.services, AnyView(servicesCard))) }
        if k.contains(.app) { out.append((.builds, AnyView(buildsCard))) }
        out.append((.repos, AnyView(reposCard)))
        out.append((.activity, AnyView(activityCard)))
        if k.contains(where: \.runs) { out.append((.logs, AnyView(logsCard))) }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s4) {
                OverviewStage(model: model, project: project, kind: $stageKind).frame(height: 440)
                    .coreRise(settled, 0)
                let rows = stride(from: 0, to: cells.count, by: Self.columns).map {
                    Array(cells[$0..<min($0 + Self.columns, cells.count)].enumerated())
                }
                Grid(horizontalSpacing: Space.s4, verticalSpacing: Space.s4) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                        GridRow {
                            ForEach(row, id: \.1.module) { c, cell in
                                cell.view.coreRise(settled, 1 + r * Self.columns + c)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    // A last row of one card spans the grid instead of leaving a hole.
                                    .gridCellColumns(row.count == 1 && rows.count > 1 ? Self.columns : 1)
                            }
                            if !(row.count == 1 && rows.count > 1) {
                                ForEach(0..<(Self.columns - row.count), id: \.self) { _ in Color.clear }
                            }
                        }
                    }
                }
                .frame(minHeight: 0)
            }
            .padding(.bottom, Space.s1)
        }
        .scrollIndicators(.never)
        // The tail of the log while it runs (the Core's stream, else a page every 3 s), and the last run's log after it ends,
        // so a failed project keeps the lines that say why.
        // One reader per run state (not per tick of the Core's events), so the lines already read stay.
        .task(id: "\(project.id) \(project.run?.state == .running || project.run?.state == .starting) \(project.run == nil)") {
            guard project.run != nil, !project.stale, let source = model.logSources(project.id, nil) else {
                if project.run == nil { logs = nil }
                return
            }
            let m = RunLogsModel(source: source)
            let id = project.id
            m.keepReading = { [model] in
                let state = model.project(id)?.run?.state
                return state == .running || state == .starting
            }
            logs = m
            await m.run()
        }
        .task(id: project.id) {
            await model.refreshSetup(project.id)
            await model.refreshLive(project.id)
            await loadRuns()
            await insights.loadKnowledge()
            await insights.loadChanges()
        }
    }

    func loadRuns() async {
        guard let svc = model.configsService else { return }
        runs = (try? await svc.history(project: project.id)) ?? []
        names = Dictionary(
            uniqueKeysWithValues: ((try? await svc.configs(project: project.id)) ?? []).map { ($0.id, $0.name) })
    }
}
