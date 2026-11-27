import CoreUI
import SwiftUI

/// The AI Sessions page: this project's sessions as a table, filtered All / Needs you / Running / Done.
///
/// The sessions come from the Core's list, kept where `project_id` is this project (`ProjectsModel.refreshLive`); a server
/// filter (lane Q) replaces that read without a change here.
struct SessionsPage: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var filter = Filter.all
    @State private var settled = false
    @State private var insights: ProjectInsightsModel

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _insights = State(initialValue: ProjectInsightsModel(model: model, project: project))
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case needsYou = "Needs you"
        case running = "Running"
        case done = "Done"
        var id: String { rawValue }
        func keeps(_ s: ProjectLive.Session.State) -> Bool {
            switch self {
            case .all: true
            case .needsYou: s == .needsYou
            case .running: s == .running
            case .done: s == .done
            }
        }
    }

    private var all: [ProjectLive.Session] { project.live?.sessions ?? [] }
    private var shown: [ProjectLive.Session] { all.filter { filter.keeps($0.state) } }

    private var usage: UsageInfo? { insights.usage }

    var body: some View {
        VStack(spacing: Space.s2) {
            if let u = usage {
                HStack(spacing: Space.s2) {
                    InsightTile(
                        title: "Running now", value: "\(u.running)", line: "Working on your code", spark: u.byDay)
                    InsightTile(
                        title: "Sessions this week", value: "\(u.sessionsWeek)", line: "Started in the last 7 days")
                    InsightTile(title: "Cost this week", value: CostWords.money(u.weekCost), line: u.trend)
                }
                .fixedSize(horizontal: false, vertical: true).coreRise(settled, 0)
            }
            sessionsIsland
        }
        .task(id: project.id) {
            await model.refreshLive(project.id)
            await insights.loadUsage()
        }
    }

    private var sessionsIsland: some View {
        Island(
            title: "AI Sessions", sub: all.isEmpty ? nil : "\(all.count) in this project",
            accessory: {
                if !all.isEmpty {
                    CoreSegmented(
                        "Show", segments: Filter.allCases.map { CoreSegment($0, $0.rawValue) },
                        selection: $filter)
                }
                Button {
                    model.newSession(in: project)
                } label: {
                    Label("New AI Session", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(.secondary)).disabled(!model.canStartSession(project))
                .help(model.sessionBlock(project))
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if all.isEmpty, let rows = usage?.sessions, !rows.isEmpty {
                    VStack(spacing: Space.s1) {
                        ForEach(rows) { r in
                            CoreRow(
                                r.title, subtitle: r.running ? "Working now" : r.state.capitalized, symbol: "sparkles"
                            ) {
                                CoreSpark(r.spark, tone: r.running ? .run : .queue).frame(
                                    width: Space.s8 * 2, height: Space.s4)
                                StateBadge(CostWords.money(r.cost), tone: .queue, symbol: "circle")
                            }
                        }
                    }
                } else if all.isEmpty {
                    CoreStateCard(
                        symbol: "sparkles", title: "No AI sessions yet",
                        line: "A session works in its own copy of this project's repos, with the project's Brain room.",
                        primary: model.canStartSession(project)
                            ? CoreAction("New AI Session") { model.newSession(in: project) } : nil
                    )
                    .frame(maxWidth: .infinity, minHeight: Space.s8 * 12)
                } else if shown.isEmpty {
                    Text("No \(filter.rawValue.lowercased()) sessions.").foregroundStyle(GlassInk.secondary)
                } else {
                    table
                }
                Text(
                    "New sessions start in their own clone of this project’s repos, with the \(project.name) room’s approved instructions."
                )
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .coreRise(settled, 0)
        .onAppear { settled = true }
        .accessibilityIdentifier("project-page-AI Sessions")
    }

    private var table: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s4, verticalSpacing: Space.s3) {
            GridRow {
                ForEach(["Session", "Harness", "Runner", "Branch", "Time", "Cost"], id: \.self) {
                    Text($0).foregroundStyle(GlassInk.secondary).frame(
                        maxWidth: $0 == "Session" ? .infinity : nil, alignment: .leading)
                }
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, s in
                GridRow {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        if let id = s.id {
                            Button(s.title) { model.sessionOpener?(id) }.buttonStyle(.plain).lineLimit(1)
                                .help("Open this session in AI Sessions")
                        } else {
                            Text(s.title).lineLimit(1)
                        }
                        badge(s.state)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(s.harness)
                    Text(s.runner)
                    Text(s.branch).font(.system(size: MacTextSize.body, design: .monospaced))
                    Text(s.when)
                    Text(s.cost).font(.system(size: MacTextSize.body, design: .monospaced))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badge(_ s: ProjectLive.Session.State) -> StateBadge {
        switch s {
        case .needsYou: StateBadge("Needs you", tone: .warn, symbol: "hand.raised")
        case .running: StateBadge("Running", tone: .run, symbol: "play.circle")
        case .done: StateBadge("Done", tone: .queue, symbol: "checkmark.circle")
        }
    }
}
