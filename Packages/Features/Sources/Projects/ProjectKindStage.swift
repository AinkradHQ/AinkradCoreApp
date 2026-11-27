import CoreUI
import SwiftUI

/// The top of the big island for a project that is not a web app: its kind, its name and what it is built for, where a web
/// project shows its link.
struct KindHeader: View {
    let project: ProjectItem

    var body: some View {
        let kind = project.kind
        let platforms = kind == .app ? ProjectKind.platforms(project.repos) : []
        HStack(spacing: Space.s3) {
            IconTile(kind.symbol, hue: GlassInk.blue, size: Space.s8 + Space.s3)
            VStack(alignment: .leading, spacing: 0) {
                Text(kind.title).coreFont(size: MacTextSize.title, weight: .semibold).lineLimit(1)
                Text(project.description.isEmpty ? kind.line : project.description)
                    .foregroundStyle(GlassInk.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if kind == .app {
                if platforms.isEmpty {
                    Text("Platform not known yet").foregroundStyle(GlassInk.secondary)
                } else {
                    ForEach(platforms, id: \.self) { StateBadge($0, tone: .queue, symbol: "macbook.and.iphone") }
                }
            }
        }
        .padding(.leading, Space.s1)
        .accessibilityElement(children: .combine)
    }
}

/// What the stage shows while an app or an infrastructure project runs: an app, where it runs; infrastructure, its services and
/// how healthy they are.
struct KindRunningStage: View {
    let model: ProjectsModel
    let project: ProjectItem

    var body: some View {
        if project.kind == .infra { health } else { appRunning }
    }

    private var appRunning: some View {
        VStack(spacing: Space.s2) {
            Text("\(project.name) is running").coreFont(size: MacTextSize.large, weight: .semibold)
                .accessibilityAddTraits(.isHeader)
            Text("On \(project.live?.runner ?? model.coreName)\(project.live?.idle.map { " · \($0)" } ?? "")")
                .foregroundStyle(GlassInk.secondary)
            StartStepsList(steps: project.live?.steps ?? [])
        }
    }

    private var health: some View {
        let services = project.live?.services ?? []
        let up = services.filter { $0.state == .up }.count
        return VStack(alignment: .leading, spacing: Space.s2) {
            if services.isEmpty {
                Text("Waiting for the Core to list the services…").foregroundStyle(GlassInk.secondary)
            } else {
                Text("\(up) of \(ProjectItem.count(services.count, "service")) up")
                    .coreFont(size: MacTextSize.large, weight: .semibold)
                CoreMeter(Double(up) / Double(services.count), label: "Services up")
                ForEach(Array(services.enumerated()), id: \.offset) { _, s in
                    HStack(spacing: Space.s3) {
                        StatusDot(
                            colour: s.state == .up
                                ? GlassInk.green : s.state == .exited ? GlassInk.red : GlassInk.secondary)
                        Text(s.name).coreFont(size: MacTextSize.headline, weight: .semibold)
                        Spacer(minLength: 0)
                        if s.state == .exited {
                            StateBadge("Exited", tone: .fail, symbol: "exclamationmark.triangle")
                        } else if s.state == .up {
                            StateBadge(
                                s.health == "unhealthy" ? "Unhealthy" : "Healthy",
                                tone: s.health == "unhealthy" ? .warn : .run,
                                symbol: s.health == "unhealthy" ? "exclamationmark.triangle" : "checkmark.circle")
                            Text(s.memory).foregroundStyle(GlassInk.secondary).monospacedDigit()
                        } else {
                            Text("Down").foregroundStyle(GlassInk.secondary)
                        }
                    }
                    .frame(minHeight: MacSize.controlLg)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: Space.s8 * 16)
    }
}

/// Project Settings: what the project is. Changing it changes the pages and buttons the project shows; nothing else.
struct KindSettings: View {
    let model: ProjectsModel
    let project: ProjectItem

    var body: some View {
        Island("What it is") {
            VStack(alignment: .leading, spacing: Space.s2) {
                CoreSelect(
                    "Kind", selection: Binding(get: { project.kind }, set: { model.setKind($0, for: project) }),
                    options: ProjectKind.allCases.map { CoreSelectOption($0, $0.title, symbol: $0.symbol) }
                )
                .disabled(model.readOnly)
                .help(model.readOnly ? "This device can look at projects but not change them." : "")
                Text(project.kind.line).foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                if !model.core111 {
                    Text("This Core does not keep the kind yet, so it is remembered on this Mac.")
                        .foregroundStyle(GlassInk.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("project-settings-kind")
    }
}
