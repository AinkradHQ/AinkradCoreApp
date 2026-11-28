import AppKit
import CoreUI
import SwiftUI

/// The Services focused page (details v2): the services of the run with their state, image, port and memory, and for the picked
/// one its health, CPU and memory history and its last log lines. The Core restarts the whole run, not one service, so the
/// button says Restart All and its tooltip says why.
struct ModuleServices: View {
    let model: ProjectsModel
    let project: ProjectItem
    @State private var run: RunPageModel
    @State private var filter = ""
    @State private var selected: String?

    init(model: ProjectsModel, project: ProjectItem) {
        self.model = model
        self.project = project
        _run = State(initialValue: RunPageModel(model: model, projectID: project.id))
    }

    /// One line of the list: what the run engine says, with the setup's image and port.
    struct Row: Identifiable, Equatable {
        let name: String
        let state: ProjectLive.Service.State?
        let live: ProjectLive.Service?
        let spec: SpecService?
        var id: String { name }
    }

    private var rows: [Row] {
        var live = project.live?.services ?? []
        if live.isEmpty { live = run.services }
        let spec = run.spec?.services ?? []
        var out = live.map { s in Row(name: s.name, state: s.state, live: s, spec: spec.first { $0.name == s.name }) }
        for s in spec where !out.contains(where: { $0.name == s.name }) {
            out.append(Row(name: s.name, state: nil, live: nil, spec: s))
        }
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty
            ? out
            : out.filter { $0.name.lowercased().contains(q) || ($0.spec?.image.lowercased().contains(q) ?? false) }
    }

    private var current: Row? { rows.first { $0.id == selected } ?? rows.first }
    private var running: Bool { project.tag == .running }
    private var can: Bool { model.canControl(project) && project.startBlock == nil }

    var body: some View {
        ModulePage(
            title: "Services",
            tools: {
                FilterField(text: $filter, label: "Filter services")
                Button {
                    model.control(.restart, project)
                } label: {
                    Label("Restart All", systemImage: "arrow.clockwise")
                }
                .buttonStyle(CoreButtonStyle(.secondary, size: .small)).disabled(!running || !can)
                .help(running ? "Restart every service of \(project.name)" : "Start \(project.name) first")
            }
        ) {
            if rows.isEmpty {
                ModuleQuiet(
                    symbol: "server.rack",
                    title: filter.isEmpty ? "No Services Yet" : "No Service Matches",
                    line: filter.isEmpty
                        ? "The services appear once \(project.name) has a setup and runs."
                        : "No service is called “\(filter)”.")
            } else {
                PgSplit(key: current?.id ?? "") {
                    ForEach(rows) { r in
                        CoreRow(
                            r.name, subtitle: line(r), symbol: nil, selected: current?.id == r.id,
                            action: { selected = r.id }
                        ) {
                            if let m = r.live?.memory, r.live?.state == .up {
                                Text(m).foregroundStyle(GlassInk.secondary).monospacedDigit()
                            }
                            StatusDot(colour: tint(r))
                        }
                    }
                } detail: {
                    if let r = current { detail(r) }
                }
                .animation(Motion.out(Motion.ui), value: rows.map(\.id))
            }
        }
        .task(id: project.id) { await run.load() }
        .task(id: model.tick(project.id)) { if run.loaded { await run.refreshRun() } }
        .accessibilityIdentifier("project-page-Services")
    }

    private func tint(_ r: Row) -> Color {
        switch (r.state, r.live?.health) {
        case (.up, "unhealthy"?): GlassInk.red
        case (.up, _): GlassInk.green
        case (.exited, _): GlassInk.red
        default: failed ? GlassInk.red : GlassInk.secondary
        }
    }

    /// The project's last start failed: services that are not up failed with it.
    private var failed: Bool { project.tag == .failed }

    private func line(_ r: Row) -> String {
        var bits: [String] = []
        if let s = r.spec {
            bits.append(s.image)
            if let p = s.port { bits.append(":\(p)" + (s.isPublic ? " public" : "")) }
        }
        if r.state == nil { bits.append(failed ? "failed to start" : "not running") } else if r.state == .exited { bits.append("stopped") }
        return bits.joined(separator: " · ")
    }

    private func health(_ s: ProjectLive.Service?) -> String {
        guard let s else { return failed ? "Failed" : "Not running" }
        if failed, s.state != .up { return "Failed" }
        if s.state == .exited { return "Stopped" }
        if s.state == .down { return "Down" }
        switch s.health {
        case "healthy": return "Healthy"
        case "unhealthy": return "Unhealthy"
        case "starting": return "Starting"
        default: return "No health check"
        }
    }

    @ViewBuilder private func detail(_ r: Row) -> some View {
        let s = r.live
        let up = s?.state == .up
        PgHead(
            kicker: [health(s), s.map { "\($0.restarts) \($0.restarts == 1 ? "restart" : "restarts")" }].compactMap {
                $0
            }.joined(separator: " · "),
            title: r.name
        ) {
            Button {
                model.logService = r.name
                model.go(.logs, in: project.id)
            } label: {
                Label("Show Logs", systemImage: "text.alignleft")
            }
            .buttonStyle(CoreButtonStyle(.secondary)).help("Read the log of \(r.name)")
            if let port = r.spec?.port {
                let open = r.spec?.isPublic == true && running && model.siteTarget(project) != .none
                Button("Open Port \(String(port))") { model.openSite(project) }
                .buttonStyle(CoreButtonStyle(.secondary)).disabled(!open)
                .help(
                    open
                        ? (project.expose ? "Open the public link" : "Open the live site page, the private preview")
                        : "Only a public port of a running project opens from here. This port is on \(project.live?.runner ?? model.coreName)."
                )
            }
        }
        PgFacts(rows: facts(r))
        if up, let m = project.live?.metrics[r.name] {
            HStack(alignment: .top, spacing: Space.s3) {
                PgChart(
                    title: "CPU · last hour", values: m.cpu,
                    latest: m.cpu.last.map { String(format: "%.0f %%", $0) } ?? "–", floor: 10)
                PgChart(
                    title: "Memory", values: m.memory, latest: m.memory.last.map(Self.bytes) ?? "–", floor: 1)
            }
        } else if up {
            PgQuiet("CPU and memory appear once the Core has readings.")
        }
        PgBlock("Recent lines") {
            let lines = (project.live?.logs ?? []).filter { $0.service == r.name }.suffix(6)
            if lines.isEmpty {
                PgQuiet(up ? "No lines from \(r.name) yet." : failed ? "\(r.name) failed to start. Show Logs says why." : "\(r.name) is not running, so it has no lines to show.")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        Text(LogText.plain(l.text)).font(.system(size: MacTextSize.meta, design: .monospaced)).lineLimit(1)
                            .foregroundStyle(LogLevel.of(l.text) == .error ? GlassInk.redInk : GlassInk.primary)
                            .truncationMode(.tail)
                    }
                }
                .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                .coreCard(GlassInk.well, radius: Radius.row)
            }
        }
    }

    private func facts(_ r: Row) -> [(String, String)] {
        var out: [(String, String)] = []
        if let s = r.spec {
            out.append(("Image", s.image))
            if let p = s.port { out.append(("Port", "\(p) · \(s.isPublic ? "public" : "private")")) }
        }
        out.append(("Health", health(r.live)))
        if let c = r.live?.cpu, r.live?.state == .up { out.append(("CPU", "\(c) %")) }
        if let m = r.live?.memory, r.live?.state == .up { out.append(("Memory", m)) }
        return out
    }

    static func bytes(_ b: Double) -> String {
        let mb = b / 1_048_576
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}
