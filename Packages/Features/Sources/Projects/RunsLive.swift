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
                if runs.liveRuns.isEmpty { idle } else { ForEach(runs.liveRuns) { live($0) } }
                if !runs.liveRuns.isEmpty, !notRunning.isEmpty { others }
            }
        }
    }

    private var notRunning: [RunConfigItem] { runs.configs.filter { !runs.isLive($0) } }

    private func live(_ r: RunRecord) -> some View {
        let c = runs.configs.first { $0.id == r.configID }
        return Island(
            title: runs.name(of: r.configID),
            sub: "\(label(r.state)) on \(r.runner) · started \(runsAgo(r.startedAt))",
            accessory: {
                if let p = c?.port { StateBadge("localhost:\(p)", tone: .queue, symbol: "globe") }
                if let c {
                    Button {
                        Task { await runs.start(c, project: project) }
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                    .disabled(runs.busy || !runs.model.canControl(project))
                }
                Button {
                    Task { await runs.stop(r, project: project) }
                } label: {
                    Label("Stop", systemImage: "power")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .disabled(runs.busy || !runs.model.canControl(project))
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s2) {
                if r.state == "failed", let e = r.error {
                    CoreNotice(symbol: "exclamationmark.triangle", title: "It failed to start.", text: e, tone: .fail)
                }
                if let e = r.environment { Text("Environment: \(e)").foregroundStyle(GlassInk.secondary) }
                LogBox(lines: runs.logLines[r.id] ?? [])
            }
        }
        .frame(minHeight: Space.s8 * 6)
    }

    private var idle: some View {
        Island("Nothing is running") {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Start a configuration:").foregroundStyle(GlassInk.secondary)
                starters
            }
        }
        .frame(height: Space.s8 * 4)
    }

    private var others: some View {
        Island("Start another") { starters }
            .frame(height: Space.s8 * 3)
    }

    private var starters: some View {
        HStack(spacing: Space.s2) {
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

    private func label(_ state: String) -> String {
        switch state {
        case "starting": "Starting"
        case "running": "Running"
        case "stopping": "Stopping"
        case "failed": "Failed"
        default: "Stopped"
        }
    }
}

/// The newest log lines of the live run, newest at the bottom.
private struct LogBox: View {
    let lines: [ProjectLive.LogLine]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if lines.isEmpty { Text("No log lines yet.").foregroundStyle(GlassInk.secondary) }
                    ForEach(Array(lines.suffix(120).enumerated()), id: \.offset) { i, l in
                        Text("\(l.service)  \(l.text)").font(.system(size: MacTextSize.meta, design: .monospaced))
                            .foregroundStyle(GlassInk.secondary).textSelection(.enabled).id(i)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s3)
            }
            .onChange(of: lines.count) { _, _ in proxy.scrollTo(min(lines.count, 120) - 1, anchor: .bottom) }
        }
        .frame(height: Space.s8 * 4)
        .coreCard(GlassInk.well, radius: Radius.cardMac)
        .accessibilityLabel("Run log")
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
                            "\(runs.name(of: r.configID)) · \(r.runner)", subtitle: subtitle(r), symbol: icon(r),
                            selected: open == r.id, action: { open = open == r.id ? nil : r.id }
                        ) {
                            StateBadge(badge(r).0, tone: badge(r).1, symbol: "circle")
                            if let c = runs.configs.first(where: { $0.id == r.configID }) {
                                Button {
                                    Task { await runs.start(c, project: project) }
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

    private func badge(_ r: RunRecord) -> (String, Tone) {
        switch r.state {
        case "failed": ("Failed", .fail)
        case "stopped": ("Stopped", .queue)
        case "stopping": ("Stopping", .warn)
        case "starting": ("Starting", .run)
        default: ("Running", .run)
        }
    }

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
            Text("Ran on \(r.runner)").foregroundStyle(GlassInk.secondary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .coreCard(GlassInk.well, radius: Radius.row)
    }
}
