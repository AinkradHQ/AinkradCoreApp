import CoreUI
import SwiftUI

/// The AI Sessions page: this project's sessions as a table, filtered All / Needs you / Running / Done.
///
/// TODO(P3-02): the Core's sessions list has no project filter and a session carries no project, so a real project has no
/// sessions here yet (`ProjectItem.live` is nil); only the Debug demo fills the table. When P3-02 lands, read them in
/// `ProjectsModel.reload` and set `live.sessions`; this page needs no change.
struct SessionsPage: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var filter = Filter.all
    @State private var settled = false

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

    var body: some View {
        Island(
            title: "AI Sessions", sub: all.isEmpty ? nil : "\(all.count) in this project",
            accessory: {
                if !all.isEmpty {
                    CoreSegmented(
                        "Show", segments: Filter.allCases.map { CoreSegment($0, $0.rawValue) },
                        selection: $filter)
                }
                Soon(prominent: false, help: "AI sessions in a project arrive with the next update") {
                    Label("New AI Session", systemImage: "plus")
                }
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if all.isEmpty {
                    Text("No AI sessions yet. Start one from the top bar.").foregroundStyle(GlassInk.secondary)
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
                        Text(s.title).lineLimit(1)
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
