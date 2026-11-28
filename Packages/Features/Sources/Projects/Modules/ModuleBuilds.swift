import CoreUI
import SwiftUI

/// The Builds focused page (details v2): the runs of an app project grouped by day, All or Failed, and the picked build's steps,
/// files and tests. Files and tests are the Core's to report; until it does, the page says so quietly and shows nothing made up.
struct ModuleBuilds: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var runs: RunConfigsModel
    @State private var failedOnly = false
    @State private var selected: String?

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _runs = State(initialValue: RunConfigsModel(model: model, projectID: project.id))
    }

    private var days: [BuildDay] { BuildWords.days(runs.history, failedOnly: failedOnly, now: model.now()) }
    private var all: [RunRecord] { days.flatMap(\.runs) }
    private var current: RunRecord? { all.first { $0.id == selected } ?? all.first }
    private var newest: RunRecord? { BuildWords.days(runs.history, failedOnly: false, now: model.now()).first?.runs.first }
    private var can: Bool { model.canControl(project) && project.startBlock == nil }

    var body: some View {
        ModulePage(
            title: "Builds",
            tools: {
                CoreSegmented(
                    "Builds shown",
                    segments: [CoreSegment(false, "All"), CoreSegment(true, "Failed")],
                    selection: Binding(get: { failedOnly }, set: { failedOnly = $0 }))
                buildAndRun(prominent: true)
            }
        ) {
            content
        }
        .task(id: project.id) { await runs.load() }
        .task(id: model.tick(project.id)) { if runs.loaded { await runs.refreshHistory() } }
        .accessibilityIdentifier("project-page-Builds")
    }

    @ViewBuilder private func buildAndRun(prominent: Bool) -> some View {
        Button {
            if model.configsService != nil {
                Task { await runs.startDefault(project) }
            } else {
                model.control(.start, project)
            }
        } label: {
            Label("Build and Run", systemImage: "play")
        }
        .buttonStyle(CoreButtonStyle(prominent ? .prominent : .secondary, size: .small, busy: runs.busy))
        .disabled(!can || runs.busy)
        .help(can ? "Build \(project.name) and run it" : project.startBlock ?? ProjectSpaceCopy.cannot)
    }

    @ViewBuilder private var content: some View {
        if let e = runs.loadError {
            LoadFailed(what: "the builds", why: e) { Task { await runs.load() } }.padding(.horizontal, Space.s5)
        } else if runs.history.isEmpty {
            ModuleQuiet(symbol: "hammer", title: "No builds yet", line: "Build and Run makes the first one.") {
                Button("Build and Run") { model.control(.start, project) }.buttonStyle(CoreButtonStyle(.prominent))
                    .disabled(!can).help(can ? "Build \(project.name) and run it" : project.startBlock ?? ProjectSpaceCopy.cannot)
            }
        } else if all.isEmpty {
            PgQuiet("No build failed. Every build in the list passed.").padding(.horizontal, Space.s5)
        } else {
            PgSplit(key: current?.id ?? "") {
                ForEach(days, id: \.title) { day in
                    PgGroup(day.title)
                    ForEach(day.runs) { r in
                        CoreRow(
                            title(r), subtitle: subtitle(r), symbol: symbol(r), selected: current?.id == r.id,
                            action: { selected = r.id }
                        ) {
                            if r.live { StateBadge("Running", tone: .run, symbol: "bolt") }
                        }
                    }
                }
            } detail: {
                if let r = current { detail(r) }
            }
            .animation(Motion.out(Motion.ui), value: all.map(\.id))
        }
    }

    private func title(_ r: RunRecord) -> String { runs.name(of: r.configID) }

    private func symbol(_ r: RunRecord) -> String {
        r.state == "failed" ? "xmark.square" : r.live ? "square.dotted" : "checkmark.square"
    }

    private func took(_ r: RunRecord) -> String? {
        guard let a = r.startedAt, let b = r.stoppedAt else { return nil }
        return BuildWords.duration(b.timeIntervalSince(a))
    }

    private func subtitle(_ r: RunRecord) -> String {
        var bits = [runs.runnerName(r.runner)]
        if r.state == "failed" { bits.append("failed") } else if let t = took(r) { bits.append(t) }
        let ago = runsAgo(r.startedAt, now: model.now())
        if !ago.isEmpty { bits.append(ago) }
        return bits.joined(separator: " · ")
    }

    @ViewBuilder private func detail(_ r: RunRecord) -> some View {
        PgHead(kicker: "Built \(runsAgo(r.startedAt, now: model.now())) on \(runs.runnerName(r.runner))" + (took(r).map { " · \($0)" } ?? ""), title: title(r)) {
            if r.state == "failed" {
                Button {
                    model.newSession(
                        in: project,
                        prompt: ProjectsModel.fixPrompt(
                            project: project.name, what: "The build of \(title(r))",
                            details: [
                                r.error, r.environment.map { "Environment: \($0)" }, "Ran on \(runs.runnerName(r.runner)).",
                                r.stopReason.map { "Stopped because: \(ProjectsModel.reason($0))" },
                            ]))
                } label: {
                    Label("Ask AI to Fix", systemImage: "sparkles")
                }
                .buttonStyle(CoreButtonStyle(.secondary, busy: model.startingSession.contains(project.id)))
                .disabled(!model.canStartSession(project))
                .help("Start an AI session that begins with this failure")
            }
            Button {
                Task {
                    if let c = runs.configs.first(where: { $0.id == r.configID }) {
                        await runs.start(c, project: project, environment: r.environment)
                    } else {
                        await runs.startDefault(project)
                    }
                }
            } label: {
                Label("Build Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(CoreButtonStyle(.prominent, busy: runs.busy)).disabled(!can || runs.busy)
            .help(can ? "Build it again with the same setup" : project.startBlock ?? ProjectSpaceCopy.cannot)
        }
        if let e = r.error {
            Text(e).font(.system(size: MacTextSize.meta, design: .monospaced)).foregroundStyle(GlassInk.red)
                .textSelection(.enabled).padding(.bottom, Space.s2)
        }
        if r.id == newest?.id, let steps = project.live?.steps, !steps.isEmpty {
            StartStepsList(steps: steps)
        } else {
            PgQuiet("Steps are shown for the latest build.")
        }
        PgBlock("Files") { PgQuiet("Files appear once the Core keeps them.") }
        PgBlock("Tests") { PgQuiet("Test results appear once the Core keeps them.") }
    }
}
