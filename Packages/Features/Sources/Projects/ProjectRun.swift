import AppKit
import CoreUI
import Shell
import SwiftUI

/// The Run page: the services table, the public link, the secrets and the logs, as in the approved mockup
/// (`Designs/core/projects/index.html`, Run). The setup comes from the project's run spec (Core #306), the secrets from #316,
/// the run's state from #318. What the run engine does not report yet (health, CPU, memory, restarts, log lines) comes from
/// the Core's `run/services` and `run/logs` (polled while the page is open); the Debug demo fills `ProjectLive` instead.
struct RunPage: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var run: RunPageModel
    @State private var settled = false

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _run = State(initialValue: RunPageModel(model: model, projectID: project.id))
    }

    var body: some View {
        VStack(spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s2) {
                ServicesIsland(model: model, project: project, run: run).coreRise(settled, 0)
                VStack(spacing: Space.s2) {
                    PublicLinkIsland(model: model, project: project, run: run).coreRise(settled, 1)
                        .fixedSize(horizontal: false, vertical: true)
                    SecretsIsland(model: model, project: project, run: run).coreRise(settled, 2)
                }
                .frame(width: Space.s8 * 11)
            }
            .frame(maxHeight: .infinity)
            LogsIsland(model: model, project: project, run: run).coreRise(settled, 3).frame(maxHeight: .infinity)
        }
        .onAppear { settled = true }
        .task(id: project.id) { await run.watch() }
        // The Core says a run or its setup changed: read it now, not at the next minute.
        .task(id: model.runTick) {
            if run.loaded {
                await run.load()
                await run.refreshRun()
            }
        }
        .accessibilityIdentifier("project-page-Run")
    }
}

// MARK: Services

private struct ServicesIsland: View {
    let model: ProjectsModel
    let project: ProjectItem
    let run: RunPageModel

    private var sub: String {
        "\(ServicesTable(project: project, run: run).rows.count) · \(project.live?.runner ?? model.coreName) · up to \(ProjectRules.limits(cpu: project.cpuLimit, memMb: project.memLimitMb))"
    }

    var body: some View {
        Island(
            title: "Services", sub: sub,
            accessory: {
                HStack(spacing: Space.s2) {
                    // Where the project's latest heavy job ran (E15); nothing for a Core run or before hardware.
                    RanOnChip(model.host.shell.hardwareDeck.jobByProject[Int(project.id)])
                    Button("History…") { RunDialogs.openHistory(run, project: project) }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small))
                        .disabled(run.versions.count < 2)
                        .help(
                            run.versions.count < 2
                                ? "There is one version of the setup so far" : "Every saved version of the setup")
                    Button("Edit Setup…") { RunDialogs.openSetup(run, project: project) }
                        .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                        .disabled(model.readOnly || !run.loaded || run.loadError != nil)
                        .help("Change what this project runs")
                        .accessibilityIdentifier("project-edit-setup")
                }
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if let s = run.status, s.state == "failed" {
                    CoreNotice(
                        symbol: "exclamationmark.triangle", title: "The last start failed.",
                        text: s.error ?? ProjectsModel.reason(s.stopReason), tone: .fail)
                }
                if run.drafted, let spec = run.spec { DraftLine(project: project, run: run, spec: spec) }
                SetupContent(project: project, run: run)
            }
        }
    }
}

/// The setup's table, or why there is none: the same words on the earlier Run page and in the Default of the Runs page.
struct SetupContent: View {
    let project: ProjectItem
    let run: RunPageModel
    var showLogs: ((String) -> Void)?

    var body: some View {
        if let e = run.loadError {
            CoreNotice(symbol: "exclamationmark.triangle", title: "Unable to load the setup", text: e, tone: .fail) {
                Button("Try Again") { Task { await run.load() } }
                    .buttonStyle(CoreButtonStyle(.secondary, size: .small))
            }
        } else if !run.loaded {
            VStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    CoreSkeleton(coreShape(Radius.row)).frame(height: MacSize.controlLg)
                }
            }
            .accessibilityLabel("Loading the setup")
        } else if run.spec == nil && run.services.isEmpty && (project.live?.services.isEmpty ?? true) {
            Text("Not set up yet. It is drafted from your repos once you add them.")
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            ScrollView { ServicesTable(project: project, run: run, showLogs: showLogs) }
        }
    }
}

/// "Run drafted from docker-compose.yml: 3 services (web, api, postgres). See Changes · Undo". Undo makes the version before
/// the draft the newest again; the first version has nothing before it, so Undo is off there and Edit Setup… changes it.
struct DraftLine: View {
    let project: ProjectItem
    let run: RunPageModel
    let spec: SpecVersionItem

    private var summary: AttributedString {
        var a = AttributedString("Run drafted from ")
        var f = AttributedString(spec.source)
        f.font = .system(size: MacTextSize.body, design: .monospaced)
        a += f
        let names = spec.services.map(\.name).joined(separator: ", ")
        a += AttributedString(": \(ProjectItem.count(spec.services.count, "service")) (\(names)).")
        return a
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "sparkle").foregroundStyle(GlassInk.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(summary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s1) {
                    Button("See Changes") { RunDialogs.openChanges(run) }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small))
                    Button("Undo") { Task { await run.undoDraft(project.name) } }
                        .buttonStyle(CoreButtonStyle(.plain, size: .small))
                        .disabled(run.previous == nil || run.busy || run.model.readOnly)
                        .help(
                            run.previous.map { "Go back to version \($0.version), the setup before this draft" }
                                ?? "This is the first version, so nothing came before it. Edit Setup… changes it.")
                }
            }
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .coreCard(GlassInk.well, radius: Radius.cardMac)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-draft-line")
    }
}

// MARK: Public link

private struct PublicLinkIsland: View {
    let model: ProjectsModel
    let project: ProjectItem
    let run: RunPageModel

    var body: some View {
        Island(
            title: "Public link",
            accessory: {
                CoreSwitch(
                    "",
                    isOn: Binding(
                        get: { project.expose }, set: { on in Task { await model.setExpose(project, on) } })
                )
                .disabled(model.readOnly).accessibilityLabel("Public link")
                .help("While this project runs, anyone with \(project.link) can open it")
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Text(project.link).lineLimit(1)
                    Spacer(minLength: 0)
                    CoreIconButton(symbol: "doc.on.doc", label: "Copy the link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("https://\(project.link)", forType: .string)
                        model.host.shell.showToast("Link copied")
                    }
                }
                Text(words).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var words: String {
        guard project.expose else { return "Only your devices can open it." }
        var s =
            "Anyone with the link can open it while it runs. It stops \(ProjectRules.idleWords(minutes: project.idleMinutes, never: project.idleNever))."
        if let due = run.status?.idleStopAt, run.status?.state == "running" {
            let min = max(0, Int(due.timeIntervalSince(model.now()) / 60))
            s += " Stops in about \(min) min unless someone visits."
        }
        if let at = run.status?.lastActivityAt {
            s += " Last visited \(runsAgo(at, now: model.now()))."
        }
        return s
    }
}

// MARK: Logs

private struct LogsIsland: View {
    let model: ProjectsModel
    let project: ProjectItem
    let run: RunPageModel
    @State private var logs: RunLogsModel?

    private var names: [String] { run.spec?.services.map(\.name) ?? project.live?.services.map(\.name) ?? [] }
    private var live: Bool { run.status?.state == "running" || run.status?.state == "starting" }
    /// The Debug stand-in's lines, made once so the search and the times setting survive a redraw.
    @State private var fixed: RunLogsModel?

    var body: some View {
        Island(
            title: "Logs", sub: logs?.service ?? "all services",
            accessory: {
                if let logs, live {
                    RunLogToolbar(logs: logs, services: names, toast: { model.host.shell.showToast($0) })
                } else if let fixed {
                    RunLogToolbar(logs: fixed)
                }
            }
        ) {
            if let logs, live {
                RunLogView(logs: logs, toolbar: false)
            } else if let fixed {
                RunLogView(logs: fixed, toolbar: false)
            } else {
                Text("No logs yet. They appear while the project runs.").foregroundStyle(GlassInk.secondary)
            }
        }
        // The Core's stream while it runs; it starts again when a run starts or stops.
        .task(id: "\(project.id) \(live) \(model.runTick)") {
            guard live, let m = run.makeLogs() else {
                logs = nil
                if fixed == nil, project.live?.logs.isEmpty == false {
                    fixed = RunLogsModel.fixed(project.live?.logs ?? [], lost: 12, times: true)
                }
                return
            }
            logs = m
            await m.run()
        }
    }
}
