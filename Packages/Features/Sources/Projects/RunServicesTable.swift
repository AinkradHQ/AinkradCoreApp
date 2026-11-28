import AppKit
import CoreUI
import SwiftUI

/// The services of a project's setup with what the run reports of each, in five columns: Service, Image, Port, Status and
/// Memory. CPU and restarts are in the Status tooltip (a column of dashes while nothing runs said nothing); a row's menu
/// copies the image or opens the logs. The Default's row of the Runs page and the earlier Run page show the same table.
struct ServicesTable: View {
    let project: ProjectItem
    let run: RunPageModel
    /// Opens the log of a service; nil hides the menu entry (the earlier Run page has its log under the table).
    var showLogs: ((String) -> Void)?

    struct Row: Identifiable {
        let name: String
        let image: String
        let port: String
        let state: ProjectLive.Service.State?
        let health: String
        let cpu: Int?
        let memory: String?
        let restarts: Int
        var series: ServiceSeries?
        var id: String { name }
    }

    /// The spec's services with whatever the run reports of each; without a spec, the run's own list.
    static func rows(spec: SpecVersionItem?, live: [ProjectLive.Service], metrics: [String: ServiceSeries]) -> [Row] {
        if let spec {
            return spec.services.map { s in
                let l = live.first { $0.name == s.name }
                return Row(
                    name: s.name, image: s.image,
                    port: s.port.map { "\($0)\(s.isPublic ? " · public" : "")" } ?? "–", state: l?.state,
                    health: l?.health ?? "none", cpu: l?.cpu, memory: l?.memory, restarts: l?.restarts ?? 0,
                    series: metrics[s.name])
            }
        }
        return live.map {
            Row(
                name: $0.name, image: "–", port: "–", state: $0.state, health: $0.health, cpu: $0.cpu,
                memory: $0.memory, restarts: $0.restarts, series: metrics[$0.name])
        }
    }

    var rows: [Row] {
        Self.rows(
            spec: run.spec, live: run.services.isEmpty ? (project.live?.services ?? []) : run.services,
            metrics: project.live?.metrics ?? [:])
    }

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.s5, verticalSpacing: Space.s3) {
            GridRow {
                ForEach(["Service", "Image", "Port", "Status", "Memory", ""], id: \.self) {
                    Text($0).foregroundStyle(GlassInk.secondary).frame(
                        maxWidth: $0 == "Image" ? .infinity : nil, alignment: .leading)
                }
            }
            ForEach(rows) { r in
                GridRow {
                    Text(r.name).coreFont(size: MacTextSize.headline, weight: .semibold).lineLimit(1)
                    runsMono(r.image).frame(maxWidth: .infinity, alignment: .leading)
                    runsMono(r.port)
                    status(r)
                    memory(r)
                    ServiceMenu(row: r, showLogs: showLogs)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func memory(_ r: Row) -> some View {
        HStack(spacing: Space.s2) {
            if r.state == .up {
                Text(r.memory ?? "–").monospacedDigit().lineLimit(1).fixedSize()
                if let m = r.series?.memory, m.count > 1 {
                    Sparkline(values: m, label: "\(r.name) memory, recent minutes", floor: 1)
                }
            }
        }
        .frame(minWidth: Space.s8 * 3, alignment: .leading)
    }

    @ViewBuilder private func status(_ r: Row) -> some View {
        Group {
            switch r.state {
            case .up? where r.health == "unhealthy":
                StateBadge("Unhealthy", tone: .fail, symbol: "exclamationmark.triangle")
            case .up? where r.health == "starting": StateBadge("Starting", tone: .queue, symbol: "clock")
            case .up? where r.health == "none": StateBadge("Running", tone: .done, symbol: "checkmark.circle")
            case .up?: StateBadge("Healthy", tone: .done, symbol: "checkmark.circle")
            case .exited?: StateBadge("Exited", tone: .fail, symbol: "exclamationmark.triangle")
            case .down?, nil:
                if project.tag == .failed {
                    StateBadge("Failed", tone: .fail, symbol: "exclamationmark.triangle")
                } else {
                    Text("Not running").foregroundStyle(GlassInk.secondary).lineLimit(1)
                }
            }
        }
        .help(Self.detail(r))
    }

    /// "CPU 12 % · restarted 2 times", the numbers the table no longer has columns for.
    static func detail(_ r: Row) -> String {
        guard r.state == .up || r.state == .exited else { return "Not running" }
        var parts: [String] = []
        if let c = r.cpu { parts.append("CPU \(c) %") }
        parts.append(r.restarts == 0 ? "never restarted" : "restarted \(ProjectItem.count(r.restarts, "time"))")
        return parts.joined(separator: " · ")
    }
}

private struct ServiceMenu: View {
    let row: ServicesTable.Row
    var showLogs: ((String) -> Void)?
    @State private var open = false

    var body: some View {
        CoreDropdown(items: items, isPresented: $open) {
            Image(systemName: "ellipsis").frame(width: MacSize.controlMd, height: MacSize.controlMd)
        }
        .accessibilityLabel("More for \(row.name)")
    }

    private var items: [CoreDropdownItem] {
        var out: [CoreDropdownItem] = []
        if let showLogs {
            out.append(CoreDropdownItem("Show Logs", symbol: "text.alignleft") { showLogs(row.name) })
        }
        out.append(
            CoreDropdownItem("Copy Image Name", symbol: "doc.on.doc", enabled: row.image != "–") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.image, forType: .string)
            })
        return out
    }
}
