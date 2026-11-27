import CoreUI
import SwiftUI

/// The Live runs tab: one card per live run, each with its own log, port, Restart and Stop. Several configurations can run at
/// once; "Start another" lists the ones that are not running.
struct LiveRunsTab: View {
    let runs: RunConfigsModel
    let project: ProjectItem

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s2) {
                if runs.liveRuns.isEmpty {
                    idle
                } else {
                    ForEach(runs.liveRuns) { r in
                        LiveRunCard(
                            runs: runs, project: project, run: r, stream: (runs.liveRuns.firstIndex(of: r) ?? 0) < 3)
                    }
                }
                if !runs.liveRuns.isEmpty, !notRunning.isEmpty { others }
            }
        }
    }

    private var notRunning: [RunConfigItem] { runs.configs.filter { !runs.isLive($0) } }

    private var idle: some View {
        Island("Nothing is running") {
            VStack(alignment: .leading, spacing: Space.s3) {
                if runs.crashLoop {
                    CoreNotice(
                        symbol: "exclamationmark.triangle", title: ProjectsModel.crashLoopWords,
                        text: "Read the log of its last run in History, fix what stops it, then start it again.",
                        tone: .fail)
                }
                Text("Start one:").foregroundStyle(GlassInk.secondary)
                starters
            }
        }
        .frame(minHeight: Space.s8 * 4)
    }

    private var others: some View {
        Island("Start another") { starters }
            .frame(height: Space.s8 * 3)
    }

    private var starters: some View {
        HStack(spacing: Space.s2) {
            if runs.defaultRun == nil {
                Button {
                    Task { await runs.startDefault(project) }
                } label: {
                    Label(RunConfigsModel.defaultName, systemImage: "play")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .disabled(runs.busy || !runs.model.canControl(project) || runs.setup.spec == nil)
            }
            ForEach(notRunning) { c in
                Button {
                    Task { await runs.start(c, project: project) }
                } label: {
                    Label(c.name, systemImage: "play")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .disabled(runs.busy || !runs.model.canControl(project))
            }
        }
    }
}

/// One live run: its state, port, Restart and Stop and, in the same header, its log's controls; under it the log. The log is
/// the Core's stream while the device has sockets to spare, else a page every 3 s.
private struct LiveRunCard: View {
    let runs: RunConfigsModel
    let project: ProjectItem
    let run: RunRecord
    let stream: Bool
    @State private var logs: RunLogsModel?

    private var config: RunConfigItem? { runs.configs.first { $0.id == run.configID } }

    var body: some View {
        Island(
            title: runs.name(of: run.configID),
            sub: "\(Self.label(run.state)) on \(runs.runnerName(run.runner)) · started \(runsAgo(run.startedAt))",
            accessory: {
                if let logs {
                    RunLogToolbar(logs: logs, toast: { runs.model.host.shell.showToast($0) })
                        .frame(maxWidth: Space.s8 * 12)
                }
                // The port is on the runner that runs it, not on this Mac.
                if let p = config?.port {
                    StateBadge("\(runs.runnerName(run.runner)) · port \(p)", tone: .queue, symbol: "globe")
                }
                Button {
                    Task {
                        if let config {
                            await runs.start(config, project: project)
                        } else {
                            await runs.startDefault(project)
                        }
                    }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .disabled(runs.busy || !runs.model.canControl(project))
                Button {
                    Task { await runs.stop(run, project: project) }
                } label: {
                    Label("Stop", systemImage: "power")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .disabled(runs.busy || !runs.model.canControl(project))
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s2) {
                if run.state == "failed", let e = run.error {
                    CoreNotice(symbol: "exclamationmark.triangle", title: "It failed to start.", text: e, tone: .fail)
                }
                // Only a configuration has an environment laid over it; the Default runs the setup as saved.
                if let e = run.environment, run.configID != nil {
                    Text("Environment: \(e)").foregroundStyle(GlassInk.secondary)
                }
                Group {
                    if let logs {
                        RunLogView(logs: logs, toolbar: false)
                    } else {
                        Text("No log lines yet.").foregroundStyle(GlassInk.secondary)
                    }
                }
                .frame(height: Space.s8 * 6)
            }
        }
        .frame(minHeight: Space.s8 * 6)
        .task(id: "\(run.id) \(runs.model.runTick)") {
            guard let m = runs.logs(of: run, stream: stream) else { return }
            logs = m
            await m.run()
        }
    }

    static func label(_ state: String) -> String {
        switch state {
        case "starting": "Starting"
        case "running": "Running"
        case "stopping": "Stopping"
        case "failed": "Failed"
        case "stopped": "Stopped"
        default: state.isEmpty ? "In an unknown state" : "\(state.capitalized) (a state this app does not know)"
        }
    }
}

/// The History tab: the project's runs, newest first, each with Run again.
struct HistoryTab: View {
    let runs: RunConfigsModel
    let project: ProjectItem
    @State private var open: String?

    var body: some View {
        Island(title: "History", accessory: { Text("Latest 30").foregroundStyle(GlassInk.secondary) }) {
            ScrollView {
                VStack(spacing: Space.s1) {
                    if runs.history.isEmpty {
                        Text("Nothing has run yet.").foregroundStyle(GlassInk.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(runs.history) { r in
                        CoreRow(
                            "\(runs.name(of: r.configID)) · \(runs.runnerName(r.runner))", subtitle: subtitle(r),
                            symbol: icon(r),
                            selected: open == r.id, action: { open = open == r.id ? nil : r.id }
                        ) {
                            StateBadge(badge(r).0, tone: badge(r).1, symbol: "circle")
                            if r.configID == nil || runs.configs.contains(where: { $0.id == r.configID }) {
                                Button {
                                    Task {
                                        if let c = runs.configs.first(where: { $0.id == r.configID }) {
                                            await runs.start(c, project: project)
                                        } else {
                                            await runs.startDefault(project)
                                        }
                                    }
                                } label: {
                                    Label("Run again", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(CoreButtonStyle(.plain, size: .small))
                                .disabled(runs.busy || !runs.model.canControl(project))
                            }
                        }
                        if open == r.id { detail(r) }
                    }
                }
            }
        }
    }

    private func subtitle(_ r: RunRecord) -> String {
        let when = runsAgo(r.startedAt)
        return [r.environment, when.isEmpty ? nil : when].compactMap { $0 }.joined(separator: " · ")
    }

    private func icon(_ r: RunRecord) -> String {
        r.state == "failed" ? "exclamationmark.triangle" : r.live ? "bolt" : "checkmark"
    }

    private func badge(_ r: RunRecord) -> (String, Tone) { HistoryWords.badge(r) }

    private func ended(_ why: String) -> String {
        switch why {
        case "user": "You stopped it."
        case "idle": "It stopped after a while with no visits."
        case "replaced": "Another run replaced it."
        default: ProjectsModel.reason(why)
        }
    }

    private func detail(_ r: RunRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let e = r.error { Text(e).font(.system(size: MacTextSize.meta, design: .monospaced)) }
            if let why = r.stopReason { Text(ended(why)).foregroundStyle(GlassInk.secondary) }
            Text("Ran on \(runs.runnerName(r.runner))").foregroundStyle(GlassInk.secondary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .coreCard(GlassInk.well, radius: Radius.row)
    }
}

enum HistoryWords {
    /// A run's state as the History badge says it; a state this app does not know is shown as the Core said it, never "Running".
    static func badge(_ r: RunRecord) -> (String, Tone) {
        switch r.state {
        case "failed": ("Failed", .fail)
        case "stopped": ("Stopped", .queue)
        case "stopping": ("Stopping", .warn)
        case "starting": ("Starting", .run)
        case "running": ("Running", .run)
        default: (r.state.isEmpty ? "Unknown" : r.state.capitalized, .queue)
        }
    }
}
