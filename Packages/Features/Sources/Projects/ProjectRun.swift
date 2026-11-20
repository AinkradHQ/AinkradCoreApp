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
            LogsIsland(project: project, run: run).coreRise(settled, 3).frame(maxHeight: .infinity)
        }
        .onAppear { settled = true }
        .task(id: project.id) { await run.watch() }
        .accessibilityIdentifier("project-page-Run")
    }
}

// MARK: Services

private struct ServicesIsland: View {
    let model: ProjectsModel
    let project: ProjectItem
    let run: RunPageModel

    private struct Row: Identifiable {
        let name: String
        let image: String
        let port: String
        let state: ProjectLive.Service.State?
        let health: String
        let cpu: Int?
        let memory: String?
        let restarts: Int
        var id: String { name }
    }

    /// The spec's services with whatever the run reports of each; without a spec, the run's own list.
    private var rows: [Row] {
        let live = run.services.isEmpty ? (project.live?.services ?? []) : run.services
        if let spec = run.spec {
            return spec.services.map { s in
                let l = live.first { $0.name == s.name }
                return Row(
                    name: s.name, image: s.image,
                    port: s.port.map { "\($0)\(s.isPublic ? " · public" : "")" } ?? "–", state: l?.state,
                    health: l?.health ?? "none",
                    cpu: l?.cpu, memory: l?.memory, restarts: l?.restarts ?? 0)
            }
        }
        return live.map {
            Row(
                name: $0.name, image: "–", port: "–", state: $0.state, health: $0.health, cpu: $0.cpu,
                memory: $0.memory,
                restarts: $0.restarts)
        }
    }

    private var sub: String {
        "\(rows.count) · \(model.coreName) · up to \(ProjectRules.defaultLimits)"
    }

    var body: some View {
        Island(
            title: "Services", sub: rows.isEmpty ? model.coreName : sub,
            accessory: {
                HStack(spacing: Space.s2) {
                    // Where the project's latest heavy job ran (E15); nothing for a Core run or before hardware.
                    RanOnChip(model.host.shell.hardwareDeck.jobByProject[Int(project.id)])
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
                        text: s.error ?? "", tone: .fail)
                }
                if run.drafted, let spec = run.spec { DraftLine(project: project, run: run, spec: spec) }
                content
            }
        }
    }

    @ViewBuilder private var content: some View {
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
        } else if rows.isEmpty {
            Text("Not set up yet. It is drafted from your repos once you add them.")
                .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            ScrollView { table }
        }
    }

    private var table: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s5, verticalSpacing: Space.s3) {
            GridRow {
                ForEach(["Service", "Image", "Port", "Health", "CPU", "Memory", "Restarts"], id: \.self) {
                    Text($0).foregroundStyle(GlassInk.secondary)
                }
            }
            ForEach(rows) { r in
                GridRow {
                    Text(r.name).coreFont(size: MacTextSize.headline, weight: .semibold)
                    mono(r.image)
                    mono(r.port)
                    health(r)
                    cpu(r)
                    Text(r.state == .up ? (r.memory ?? "–") : "–").monospacedDigit()
                    Text("\(r.restarts)").monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mono(_ s: String) -> some View {
        Text(s).font(.system(size: MacTextSize.body, design: .monospaced)).foregroundStyle(GlassInk.secondary)
            .lineLimit(1).truncationMode(.middle).help(s)
    }

    @ViewBuilder private func health(_ r: Row) -> some View {
        switch r.state {
        case .up? where r.health == "unhealthy":
            StateBadge("Unhealthy", tone: .fail, symbol: "exclamationmark.triangle")
        case .up? where r.health == "starting": StateBadge("Starting", tone: .queue, symbol: "clock")
        case .up? where r.health == "none": StateBadge("Running", tone: .done, symbol: "checkmark.circle")
        case .up?: StateBadge("Healthy", tone: .done, symbol: "checkmark.circle")
        case .exited?: StateBadge("Exited", tone: .fail, symbol: "exclamationmark.triangle")
        case .down?: StateBadge("Stopped", tone: .queue, symbol: "stop.circle")
        case nil: Text("–").foregroundStyle(GlassInk.secondary)
        }
    }

    @ViewBuilder private func cpu(_ r: Row) -> some View {
        if r.state == .up, let cpu = r.cpu {
            HStack(spacing: Space.s2) {
                CoreMeter(Double(cpu) / 100, low: cpu >= 90, label: "\(r.name) CPU").frame(width: Space.s8 * 3)
                Text("\(cpu)%").monospacedDigit()
            }
        } else {
            Text("–").foregroundStyle(GlassInk.secondary)
        }
    }
}

/// "Run drafted from docker-compose.yml: 3 services (web, api, postgres). See Changes · Undo". Undo makes the version before
/// the draft the newest again; the first version has nothing before it, so Undo is off there and Edit Setup… changes it.
private struct DraftLine: View {
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
            "Anyone with the link can open it while it runs. It stops after \(ProjectRules.idleMinutes) min with no visits."
        if let due = run.status?.idleStopAt, run.status?.state == "running" {
            let min = max(0, Int(due.timeIntervalSince(model.now()) / 60))
            s += " Stops in about \(min) min unless someone visits."
        }
        return s
    }
}

// MARK: Secrets

private struct SecretsIsland: View {
    let model: ProjectsModel
    let project: ProjectItem
    let run: RunPageModel

    var body: some View {
        let rows = run.secretRows
        Island(
            title: "Secrets", sub: rows.isEmpty ? nil : "\(rows.count)",
            accessory: {
                Button {
                    RunDialogs.openSecret(run, project: project, name: nil, replacing: false)
                } label: {
                    Label("Add…", systemImage: "plus")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small))
                .disabled(model.readOnly || !run.loaded)
                .help("Add a secret the setup can use as ${secret:NAME}")
                .accessibilityIdentifier("project-add-secret")
            }
        ) {
            VStack(alignment: .leading, spacing: Space.s3) {
                if rows.isEmpty {
                    Text("No secrets yet. The setup asks for one by writing ${secret:NAME}; add it here.")
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    VStack(spacing: Space.s1) {
                        ForEach(rows) { r in
                            CoreRow(r.name, symbol: "key") {
                                HStack(spacing: Space.s2) {
                                    if let at = r.item?.updatedAt {
                                        Text("Set \(PickRepo.ago(at, model.now()))").foregroundStyle(
                                            GlassInk.secondary)
                                    } else if r.item == nil {
                                        Text("Not set").foregroundStyle(GlassInk.redInk)
                                    }
                                    Button(r.item == nil ? "Set…" : "Replace…") {
                                        RunDialogs.openSecret(
                                            run, project: project, name: r.name, replacing: r.item != nil)
                                    }
                                    .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(model.readOnly)
                                    .accessibilityLabel("\(r.item == nil ? "Set" : "Replace") \(r.name)")
                                }
                            }
                        }
                    }
                }
                Text("Sealed in the Core and given to the run at start. Never shown again.")
                    .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Logs

private struct LogsIsland: View {
    let project: ProjectItem
    let run: RunPageModel

    private var names: [String] { run.spec?.services.map(\.name) ?? project.live?.services.map(\.name) ?? [] }

    private var lines: [ProjectLive.LogLine] {
        (run.logLines.isEmpty ? (project.live?.logs ?? []) : run.logLines).filter {
            run.logService == nil || $0.service == run.logService
        }
    }

    var body: some View {
        Island(
            title: "Logs", sub: run.logService ?? "all services",
            accessory: {
                if !names.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        CoreSegmented(
                            "Log service", segments: [CoreSegment("", "All")] + names.map { CoreSegment($0, $0) },
                            selection: Binding(
                                get: { run.logService ?? "" }, set: { run.logService = $0.isEmpty ? nil : $0 })
                        )
                    }
                    .frame(maxWidth: Space.s8 * 18)
                }
            }
        ) {
            if lines.isEmpty {
                Text(empty).foregroundStyle(GlassInk.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                                Text(l.service).foregroundStyle(GlassInk.secondary)
                                    .frame(width: Space.s8 * 2, alignment: .leading)
                                Text(l.text)
                            }
                            .font(.system(size: MacTextSize.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private var empty: String {
        if let s = run.logService { return "Nothing from \(s) yet." }
        return project.tag == .running ? "No log lines yet." : "No logs yet. They appear while the project runs."
    }
}
